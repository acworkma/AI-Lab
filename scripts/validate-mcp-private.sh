#!/usr/bin/env bash
#
# validate-mcp-private.sh - Validate Private MCP Server Solution
# 
# Purpose: Verify MCP API deployment on private APIM, Power Platform VNet
#          enterprise policy readiness, and end-to-end connectivity
#
# Prerequisites: Private APIM deployed (015-apim-private)
#
# Usage: ./scripts/validate-mcp-private.sh
#

set -euo pipefail

# Default values
APIM_RG="${APIM_RG:-rg-ai-apim-private}"
APIM_NAME="${APIM_NAME:-apim-ai-lab-private}"
CORE_RG="${CORE_RG:-rg-ai-core}"
SHARED_VNET="${SHARED_VNET:-vnet-ai-shared}"
ACA_RG="${ACA_RG:-rg-ai-aca}"
MCP_APP="${MCP_APP:-mcp-server}"

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
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS_COUNT++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL_COUNT++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN_COUNT++)); }

echo ""
echo "=============================================="
echo "  Private MCP Server Solution Validation"
echo "=============================================="
echo ""

# ============================================================================
# 1. PREREQUISITE: PRIVATE APIM EXISTS
# ============================================================================

log_info "=== Prerequisite: Private APIM ==="

if az apim show --name "$APIM_NAME" --resource-group "$APIM_RG" &> /dev/null; then
    log_pass "Private APIM $APIM_NAME exists in $APIM_RG"
else
    log_fail "Private APIM $APIM_NAME not found — deploy infrastructure first (015-apim-private)"
    echo ""
    echo "Run: ./scripts/deploy-apim-private.sh"
    exit 1
fi

# ============================================================================
# 2. MCP API DEFINITION
# ============================================================================

log_info "=== MCP API Definition ==="

MCP_API=$(az apim api show --api-id "mcp-api" --service-name "$APIM_NAME" --resource-group "$APIM_RG" --query "name" -o tsv 2>/dev/null || echo "")

if [ -n "$MCP_API" ]; then
    log_pass "MCP API definition deployed to private APIM"

    # Check service URL
    SERVICE_URL=$(az apim api show --api-id "mcp-api" --service-name "$APIM_NAME" --resource-group "$APIM_RG" --query "serviceUrl" -o tsv 2>/dev/null || echo "")
    if [ -n "$SERVICE_URL" ]; then
        log_pass "MCP API backend URL: $SERVICE_URL"
    else
        log_warn "Could not determine MCP API backend URL"
    fi

    # Check API path
    API_PATH=$(az apim api show --api-id "mcp-api" --service-name "$APIM_NAME" --resource-group "$APIM_RG" --query "path" -o tsv 2>/dev/null || echo "")
    if [ "$API_PATH" = "mcp" ]; then
        log_pass "MCP API path: /mcp"
    else
        log_warn "MCP API path: /$API_PATH (expected /mcp)"
    fi
else
    log_fail "MCP API not deployed — run: ./scripts/deploy-mcp-api-private.sh"
fi

# ============================================================================
# 3. BACKEND: ACA MCP SERVER
# ============================================================================

log_info "=== Backend: ACA MCP Server ==="

if az containerapp show --name "$MCP_APP" --resource-group "$ACA_RG" &> /dev/null; then
    log_pass "MCP server container app exists in $ACA_RG"

    # Check running status
    PROVISIONING=$(az containerapp show --name "$MCP_APP" --resource-group "$ACA_RG" --query "properties.provisioningState" -o tsv 2>/dev/null || echo "unknown")
    if [ "$PROVISIONING" = "Succeeded" ]; then
        log_pass "MCP server provisioning state: Succeeded"
    else
        log_warn "MCP server provisioning state: $PROVISIONING"
    fi

    # Check FQDN
    FQDN=$(az containerapp show --name "$MCP_APP" --resource-group "$ACA_RG" --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || echo "")
    if [ -n "$FQDN" ]; then
        log_pass "MCP server FQDN: $FQDN"
    else
        log_warn "Could not determine MCP server FQDN"
    fi
else
    log_fail "MCP server container app not found in $ACA_RG — deploy via: ./scripts/deploy-mcp-server.sh"
fi

# ============================================================================
# 4. POWER PLATFORM SUBNET DELEGATION
# ============================================================================

log_info "=== Power Platform Subnet ==="

PP_SUBNET="PowerPlatformSubnet"
if az network vnet subnet show --name "$PP_SUBNET" --vnet-name "$SHARED_VNET" --resource-group "$CORE_RG" &> /dev/null; then
    log_pass "Power Platform subnet $PP_SUBNET exists"

    DELEGATION=$(az network vnet subnet show --name "$PP_SUBNET" --vnet-name "$SHARED_VNET" --resource-group "$CORE_RG" \
        --query "delegations[0].serviceName" -o tsv 2>/dev/null || echo "")
    if [ "$DELEGATION" = "Microsoft.PowerPlatform/enterprisePolicies" ]; then
        log_pass "Subnet delegated to Microsoft.PowerPlatform/enterprisePolicies"
    else
        log_fail "Subnet delegation: $DELEGATION (expected Microsoft.PowerPlatform/enterprisePolicies)"
    fi
else
    log_fail "Power Platform subnet $PP_SUBNET not found — deploy infrastructure first (015-apim-private)"
fi

# ============================================================================
# 5. PRIVATE DNS RESOLUTION (VPN required)
# ============================================================================

log_info "=== DNS Resolution (VPN required) ==="

GATEWAY_HOST="${APIM_NAME}.azure-api.net"
RESOLVED_IP=$(nslookup "$GATEWAY_HOST" 2>/dev/null | awk '/^Address: / { print $2 }' | tail -1 || echo "")

if [ -n "$RESOLVED_IP" ]; then
    if [[ "$RESOLVED_IP" == 10.* ]]; then
        log_pass "DNS resolves to private IP: $RESOLVED_IP"
    else
        log_warn "DNS resolves to $RESOLVED_IP (expected 10.x.x.x private IP — are you on VPN?)"
    fi
else
    log_warn "Could not resolve $GATEWAY_HOST (VPN may not be connected)"
fi

# ============================================================================
# 6. CONNECTIVITY TEST (VPN required)
# ============================================================================

log_info "=== Connectivity Test (VPN required) ==="

GATEWAY_URL="https://${GATEWAY_HOST}/mcp/"

# Test unauthenticated — should get 401 (JWT validation) not timeout
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$GATEWAY_URL" \
    -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "401" ]; then
    log_pass "Unauthenticated request correctly returned 401 (JWT validation working)"
elif [ "$HTTP_CODE" = "000" ]; then
    log_warn "Connection failed — VPN may not be connected or MCP API not deployed"
elif [ "$HTTP_CODE" = "200" ]; then
    log_warn "Request returned 200 without auth — JWT validation may not be configured"
else
    log_warn "Unauthenticated request returned HTTP $HTTP_CODE"
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
    log_info "Fix failures above, then re-run: ./scripts/validate-mcp-private.sh"
    exit 1
else
    log_info "Validation complete!"
    if [ "$WARN_COUNT" -gt 0 ]; then
        log_info "Review warnings above."
    fi
    echo ""
    log_info "Next steps:"
    echo "  1. Link PP environment to VNet:  ./scripts/setup-pp-vnet.sh"
    echo "  2. Create custom connector in Copilot Studio (see docs/mcp-private/README.md)"
fi
