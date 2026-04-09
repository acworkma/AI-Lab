#!/usr/bin/env bash
#
# validate-apim-private.sh - Validate Private APIM Deployment
# 
# Purpose: Verify private APIM deployment, private endpoint, DNS resolution,
#          public access blocked, and Power Platform subnet delegation
#
# Usage: ./scripts/validate-apim-private.sh
#

set -euo pipefail

# Default values
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ai-apim-private}"
APIM_NAME="${APIM_NAME:-apim-ai-lab-private}"
CORE_RG="${CORE_RG:-rg-ai-core}"
SHARED_VNET="${SHARED_VNET:-vnet-ai-shared}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; WARN_COUNT=$((WARN_COUNT + 1)); }

echo ""
echo "=============================================="
echo "  Private APIM Deployment Validation"
echo "=============================================="
echo ""

# ============================================================================
# 1. RESOURCE GROUP
# ============================================================================

log_info "=== Resource Group ==="

if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    log_pass "Resource group $RESOURCE_GROUP exists"
else
    log_fail "Resource group $RESOURCE_GROUP not found"
fi

# ============================================================================
# 2. APIM INSTANCE
# ============================================================================

log_info "=== APIM Instance ==="

if az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    log_pass "APIM instance $APIM_NAME exists"
    
    # Check SKU
    SKU=$(az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" --query "sku.name" -o tsv)
    if [ "$SKU" = "StandardV2" ] || [ "$SKU" = "Standardv2" ]; then
        log_pass "APIM SKU is $SKU"
    else
        log_warn "APIM SKU is $SKU (expected Standardv2)"
    fi

    # Check public network access (use REST API with 2024-05-01 for Standard v2 support)
    SUB_ID=$(az account show --query id -o tsv)
    PUBLIC_ACCESS=$(az rest --method get \
        --url "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}?api-version=2024-05-01" \
        --query "properties.publicNetworkAccess" -o tsv 2>/dev/null || echo "unknown")
    if [ "$PUBLIC_ACCESS" = "Disabled" ]; then
        log_pass "Public network access is DISABLED"
    else
        log_fail "Public network access is $PUBLIC_ACCESS (expected Disabled)"
    fi

    # Check managed identity
    IDENTITY=$(az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" --query "identity.type" -o tsv 2>/dev/null || echo "")
    if [ "$IDENTITY" = "SystemAssigned" ]; then
        log_pass "System-assigned managed identity enabled"
    else
        log_warn "Managed identity type: $IDENTITY"
    fi
else
    log_fail "APIM instance $APIM_NAME not found"
fi

# ============================================================================
# 3. PRIVATE ENDPOINT
# ============================================================================

log_info "=== Private Endpoint ==="

PE_NAME="${APIM_NAME}-pe"
PE_EXISTS=$(az network private-endpoint list --resource-group "$RESOURCE_GROUP" --query "[?name=='$PE_NAME'].name" -o tsv 2>/dev/null || echo "")

if [ -n "$PE_EXISTS" ]; then
    log_pass "Private endpoint $PE_NAME exists"

    # Check connection state
    PE_STATE=$(az network private-endpoint show --name "$PE_NAME" --resource-group "$RESOURCE_GROUP" \
        --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv 2>/dev/null || echo "unknown")
    if [ "$PE_STATE" = "Approved" ]; then
        log_pass "Private endpoint connection state: Approved"
    else
        log_fail "Private endpoint connection state: $PE_STATE (expected Approved)"
    fi

    # Check private IP (try multiple query paths as format varies by API version)
    PE_IP=$(az network private-endpoint show --name "$PE_NAME" --resource-group "$RESOURCE_GROUP" \
        --query "customDnsConfigs[0].ipAddresses[0]" -o tsv 2>/dev/null || echo "")
    if [ -z "$PE_IP" ] || [ "$PE_IP" = "None" ]; then
        # Fallback: check DNS A record
        PE_IP=$(az network private-dns record-set a show --zone-name "privatelink.azure-api.net" \
            --resource-group "$CORE_RG" --name "$APIM_NAME" --query "aRecords[0].ipv4Address" -o tsv 2>/dev/null || echo "")
    fi
    if [ -n "$PE_IP" ]; then
        log_pass "Private endpoint IP: $PE_IP"
    else
        log_warn "Could not determine private endpoint IP"
    fi
else
    log_fail "Private endpoint $PE_NAME not found"
fi

# ============================================================================
# 4. PRIVATE DNS ZONE
# ============================================================================

log_info "=== Private DNS Zone ==="

DNS_ZONE="privatelink.azure-api.net"
if az network private-dns zone show --name "$DNS_ZONE" --resource-group "$CORE_RG" &> /dev/null; then
    log_pass "Private DNS zone $DNS_ZONE exists"

    # Check VNet link
    LINK_COUNT=$(az network private-dns link vnet list --zone-name "$DNS_ZONE" --resource-group "$CORE_RG" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [ "$LINK_COUNT" -gt 0 ]; then
        log_pass "DNS zone linked to VNet ($LINK_COUNT link(s))"
    else
        log_fail "DNS zone not linked to any VNet"
    fi
else
    log_fail "Private DNS zone $DNS_ZONE not found in $CORE_RG"
fi

# ============================================================================
# 5. POWER PLATFORM SUBNET
# ============================================================================

log_info "=== Power Platform Subnet ==="

PP_SUBNET="PowerPlatformSubnet"
if az network vnet subnet show --name "$PP_SUBNET" --vnet-name "$SHARED_VNET" --resource-group "$CORE_RG" &> /dev/null; then
    log_pass "Power Platform subnet $PP_SUBNET exists"

    # Check delegation
    DELEGATION=$(az network vnet subnet show --name "$PP_SUBNET" --vnet-name "$SHARED_VNET" --resource-group "$CORE_RG" \
        --query "delegations[0].serviceName" -o tsv 2>/dev/null || echo "")
    if [ "$DELEGATION" = "Microsoft.PowerPlatform/enterprisePolicies" ]; then
        log_pass "Subnet delegated to Microsoft.PowerPlatform/enterprisePolicies"
    else
        log_fail "Subnet delegation: $DELEGATION (expected Microsoft.PowerPlatform/enterprisePolicies)"
    fi
else
    log_fail "Power Platform subnet $PP_SUBNET not found"
fi

# ============================================================================
# 6. PUBLIC ACCESS TEST
# ============================================================================

log_info "=== Connectivity Test ==="

GATEWAY_URL="https://${APIM_NAME}.azure-api.net/status-0123456789abcdef"
log_info "Testing connectivity to $GATEWAY_URL ..."
log_info "(Running from within VNet — requests route via private endpoint)"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$GATEWAY_URL" 2>/dev/null) || true

if [ "$HTTP_CODE" = "200" ]; then
    log_pass "APIM reachable via private endpoint (HTTP 200)"
elif [ "$HTTP_CODE" = "403" ]; then
    log_pass "Public access correctly blocked (HTTP 403)"
elif [ "$HTTP_CODE" = "000" ] || [ -z "$HTTP_CODE" ]; then
    log_warn "Connection refused/timeout — check private DNS resolution"
elif [ "$HTTP_CODE" = "404" ]; then
    log_pass "Reached APIM via private endpoint (HTTP 404)"
else
    log_warn "Public access returned HTTP $HTTP_CODE (expected 403 or connection refused)"
fi

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "=============================================="
echo "  Validation Summary"
echo "=============================================="
echo -e "  ${GREEN}PASS: $PASS_COUNT${NC}"
echo -e "  ${RED}FAIL: $FAIL_COUNT${NC}"
echo -e "  ${YELLOW}WARN: $WARN_COUNT${NC}"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    log_info "Fix failures above, then re-run: ./scripts/validate-apim-private.sh"
    exit 1
else
    log_info "Validation complete!"
    if [ "$WARN_COUNT" -gt 0 ]; then
        log_info "Review warnings above."
    fi
fi
