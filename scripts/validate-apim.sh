#!/usr/bin/env bash
#
# validate-apim.sh - Validate Azure API Management Standard v2 Deployment
# 
# Purpose: Verify APIM deployment status, VNet integration, and connectivity
#
# Usage: ./scripts/validate-apim.sh [--resource-group <name>] [--apim-name <name>]
#

set -euo pipefail

# Default values
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ai-apim}"
APIM_NAME="${APIM_NAME:-apim-ai-lab}"
CORE_RG="${CORE_RG:-rg-ai-core}"
SHARED_VNET="${SHARED_VNET:-vnet-ai-shared-services}"

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

# ============================================================================
# FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASS_COUNT++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAIL_COUNT++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARN_COUNT++))
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate Azure API Management Standard v2 Deployment

OPTIONS:
    -g, --resource-group NAME   APIM resource group (default: rg-ai-apim)
    -n, --apim-name NAME        APIM instance name (default: apim-ai-lab)
    -h, --help                  Show this help message

EXAMPLES:
    # Validate with defaults
    $0

    # Validate specific deployment
    $0 --resource-group rg-ai-apim-prod --apim-name apim-ai-lab-prod

EOF
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_fail "Azure CLI not found"
        exit 1
    fi

    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        log_fail "Not logged in to Azure"
        exit 1
    fi
    
    local account=$(az account show --query name -o tsv)
    log_info "Using subscription: $account"
}

validate_resource_group() {
    log_info "Validating resource group..."

    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_pass "Resource group exists: $RESOURCE_GROUP"
        
        # Check location
        local location=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
        log_info "  Location: $location"
    else
        log_fail "Resource group not found: $RESOURCE_GROUP"
        return 1
    fi
}

validate_apim_instance() {
    log_info "Validating APIM instance..."

    if ! az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_fail "APIM instance not found: $APIM_NAME"
        return 1
    fi
    
    log_pass "APIM instance exists: $APIM_NAME"

    # Get APIM details
    local apim_json=$(az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" --output json)
    
    # Check provisioning state
    local state=$(echo "$apim_json" | jq -r '.provisioningState')
    if [ "$state" = "Succeeded" ]; then
        log_pass "APIM provisioning state: Succeeded"
    else
        log_fail "APIM provisioning state: $state (expected: Succeeded)"
    fi

    # Check SKU
    local sku=$(echo "$apim_json" | jq -r '.sku.name')
    if [ "$sku" = "Standardv2" ]; then
        log_pass "APIM SKU: Standardv2"
    else
        log_warn "APIM SKU: $sku (expected: Standardv2)"
    fi

    # Check capacity
    local capacity=$(echo "$apim_json" | jq -r '.sku.capacity')
    log_info "  APIM capacity: $capacity units"

    # Check managed identity
    local identity_type=$(echo "$apim_json" | jq -r '.identity.type // "None"')
    if [ "$identity_type" = "SystemAssigned" ]; then
        log_pass "System-assigned managed identity enabled"
        local principal_id=$(echo "$apim_json" | jq -r '.identity.principalId')
        log_info "  Principal ID: $principal_id"
    else
        log_warn "Managed identity not enabled (type: $identity_type)"
    fi

    # Check developer portal status
    local portal_status=$(echo "$apim_json" | jq -r '.developerPortalStatus // "Unknown"')
    if [ "$portal_status" = "Enabled" ]; then
        log_pass "Developer portal: Enabled"
    else
        log_warn "Developer portal: $portal_status"
    fi
}

validate_vnet_integration() {
    log_info "Validating VNet integration..."

    local apim_json=$(az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" --output json)
    
    # Check VNet type
    local vnet_type=$(echo "$apim_json" | jq -r '.virtualNetworkType // "None"')
    
    if [ "$vnet_type" = "None" ]; then
        log_warn "VNet integration not enabled (virtualNetworkType: None)"
        return 0
    fi

    log_pass "VNet integration type: $vnet_type"

    # Check subnet configuration
    local subnet_id=$(echo "$apim_json" | jq -r '.virtualNetworkConfiguration.subnetResourceId // empty')
    if [ -n "$subnet_id" ]; then
        log_pass "VNet integration subnet configured"
        log_info "  Subnet: $(basename "$subnet_id")"
    else
        log_fail "VNet integration subnet not configured"
    fi
}

validate_apim_subnet() {
    log_info "Validating APIM integration subnet..."

    # Check if ApimIntegrationSubnet exists in shared services VNet
    if az network vnet subnet show \
        --name "ApimIntegrationSubnet" \
        --vnet-name "$SHARED_VNET" \
        --resource-group "$CORE_RG" &> /dev/null; then
        
        log_pass "APIM integration subnet exists in $SHARED_VNET"

        # Get subnet details
        local subnet_json=$(az network vnet subnet show \
            --name "ApimIntegrationSubnet" \
            --vnet-name "$SHARED_VNET" \
            --resource-group "$CORE_RG" \
            --output json)

        # Check address prefix
        local prefix=$(echo "$subnet_json" | jq -r '.addressPrefix')
        log_info "  Address prefix: $prefix"

        # Check delegation
        local delegation=$(echo "$subnet_json" | jq -r '.delegations[0].serviceName // "None"')
        if [ "$delegation" = "Microsoft.Web/serverFarms" ]; then
            log_pass "Subnet delegation: Microsoft.Web/serverFarms"
        else
            log_warn "Subnet delegation: $delegation (expected: Microsoft.Web/serverFarms)"
        fi

        # Check NSG
        local nsg_id=$(echo "$subnet_json" | jq -r '.networkSecurityGroup.id // empty')
        if [ -n "$nsg_id" ]; then
            log_pass "NSG attached: $(basename "$nsg_id")"
        else
            log_warn "No NSG attached to APIM subnet"
        fi

        # Check service endpoints
        local endpoints=$(echo "$subnet_json" | jq -r '[.serviceEndpoints[].service] | join(", ")')
        if [ -n "$endpoints" ]; then
            log_info "  Service endpoints: $endpoints"
        fi
    else
        log_warn "APIM integration subnet not found (optional if not using VNet integration)"
    fi
}

validate_nsg() {
    log_info "Validating APIM NSG..."

    local nsg_name="nsg-apim-integration"
    
    if az network nsg show --name "$nsg_name" --resource-group "$CORE_RG" &> /dev/null; then
        log_pass "APIM NSG exists: $nsg_name"

        # Count rules
        local inbound_count=$(az network nsg rule list \
            --nsg-name "$nsg_name" \
            --resource-group "$CORE_RG" \
            --query "[?direction=='Inbound'] | length(@)" \
            --output tsv)
        local outbound_count=$(az network nsg rule list \
            --nsg-name "$nsg_name" \
            --resource-group "$CORE_RG" \
            --query "[?direction=='Outbound'] | length(@)" \
            --output tsv)

        log_info "  Inbound rules: $inbound_count"
        log_info "  Outbound rules: $outbound_count"

        # Check for critical outbound rules
        if az network nsg rule show \
            --nsg-name "$nsg_name" \
            --resource-group "$CORE_RG" \
            --name "AllowStorageOutbound" &> /dev/null; then
            log_pass "Storage outbound rule exists"
        else
            log_warn "Storage outbound rule not found"
        fi

        if az network nsg rule show \
            --nsg-name "$nsg_name" \
            --resource-group "$CORE_RG" \
            --name "AllowKeyVaultOutbound" &> /dev/null; then
            log_pass "Key Vault outbound rule exists"
        else
            log_warn "Key Vault outbound rule not found"
        fi
    else
        log_warn "APIM NSG not found: $nsg_name (optional if not using VNet integration)"
    fi
}

validate_endpoints() {
    log_info "Validating APIM endpoints..."

    local apim_json=$(az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" --output json)

    # Gateway URL
    local gateway_url=$(echo "$apim_json" | jq -r '.gatewayUrl')
    log_info "  Gateway URL: $gateway_url"

    # Developer Portal URL
    local portal_url=$(echo "$apim_json" | jq -r '.developerPortalUrl')
    log_info "  Developer Portal URL: $portal_url"

    # Management URL
    local mgmt_url=$(echo "$apim_json" | jq -r '.managementApiUrl')
    log_info "  Management URL: $mgmt_url"

    # Test gateway connectivity (basic HTTP check)
    if command -v curl &> /dev/null; then
        log_info "Testing gateway connectivity..."
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "${gateway_url}/status-0123456789abcdef" 2>/dev/null || echo "000")
        
        if [ "$http_code" = "200" ] || [ "$http_code" = "401" ] || [ "$http_code" = "404" ]; then
            log_pass "Gateway responding (HTTP $http_code)"
        elif [ "$http_code" = "000" ]; then
            log_warn "Gateway not reachable (timeout or network issue)"
        else
            log_warn "Gateway returned HTTP $http_code"
        fi
    fi
}

validate_vpn_access() {
    log_info "Validating VPN client access configuration..."

    local nsg_name="nsg-apim-integration"
    
    if az network nsg show --name "$nsg_name" --resource-group "$CORE_RG" &> /dev/null; then
        # Check for VPN client inbound rule
        if az network nsg rule show \
            --nsg-name "$nsg_name" \
            --resource-group "$CORE_RG" \
            --name "AllowVpnClientInbound" &> /dev/null; then
            
            local rule_json=$(az network nsg rule show \
                --nsg-name "$nsg_name" \
                --resource-group "$CORE_RG" \
                --name "AllowVpnClientInbound" \
                --output json)
            
            local source=$(echo "$rule_json" | jq -r '.sourceAddressPrefix')
            log_pass "VPN client inbound rule exists (source: $source)"
        else
            log_warn "VPN client inbound rule not found"
        fi
    else
        log_warn "NSG not found - cannot validate VPN access rules"
    fi
}

print_summary() {
    echo ""
    echo "=============================================="
    echo "  Validation Summary"
    echo "=============================================="
    echo ""
    echo -e "  ${GREEN}PASSED:${NC} $PASS_COUNT"
    echo -e "  ${RED}FAILED:${NC} $FAIL_COUNT"
    echo -e "  ${YELLOW}WARNINGS:${NC} $WARN_COUNT"
    echo ""

    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo -e "${RED}Validation FAILED - please review the issues above${NC}"
        exit 1
    elif [ "$WARN_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}Validation PASSED with warnings${NC}"
        exit 0
    else
        echo -e "${GREEN}Validation PASSED${NC}"
        exit 0
    fi
}

# ============================================================================
# MAIN
# ============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -n|--apim-name)
            APIM_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_fail "Unknown option: $1"
            usage
            ;;
    esac
done

echo ""
echo "=============================================="
echo "  APIM Deployment Validation"
echo "=============================================="
echo ""
echo "  Resource Group: $RESOURCE_GROUP"
echo "  APIM Name: $APIM_NAME"
echo ""

check_prerequisites
validate_resource_group
validate_apim_instance
validate_vnet_integration
validate_apim_subnet
validate_nsg
validate_endpoints
validate_vpn_access

print_summary
