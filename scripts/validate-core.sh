#!/usr/bin/env bash
#
# validate-core.sh - Validate Core Azure vWAN Infrastructure Deployment
# 
# Purpose: Automated validation of deployed core infrastructure to verify:
#   - Resource existence and provisioning states
#   - Naming conventions and tagging compliance
#   - Virtual Hub routing readiness
#   - VPN Gateway BGP configuration for Global Secure Access
#   - Key Vault RBAC configuration and access
#   - Configuration drift detection (what-if analysis)
#
# Usage: ./scripts/validate-core.sh [--resource-group <name>]
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
RESOURCE_GROUP="rg-ai-core"
TEMPLATE_FILE="${REPO_ROOT}/bicep/main.bicep"
PARAMETER_FILE="${REPO_ROOT}/bicep/main.parameters.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# ============================================================================
# FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((CHECKS_PASSED++)) || true
}

log_fail() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((CHECKS_FAILED++)) || true
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
    ((CHECKS_WARNING++)) || true
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate Core Azure vWAN Infrastructure deployment

OPTIONS:
    -g, --resource-group NAME   Resource group name (default: rg-ai-core)
    -h, --help                  Show this help message

EXAMPLES:
    # Validate default resource group
    $0

    # Validate specific resource group
    $0 --resource-group rg-ai-core

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
        log_fail "Not logged in to Azure. Run: az login"
        exit 1
    fi

    # Configure Azure CLI to auto-install extensions without prompting
    az config set extension.use_dynamic_install=yes_without_prompt &> /dev/null || true

    # Ensure virtual-wan extension is installed
    if ! az extension show --name virtual-wan &> /dev/null; then
        log_info "Installing Azure CLI virtual-wan extension..."
        az extension add --name virtual-wan &> /dev/null
    fi

    log_success "Prerequisites validated"
    echo ""
}

validate_resource_group() {
    log_info "Validating Resource Group..."

    # Check resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_fail "Resource group '$RESOURCE_GROUP' not found"
        return 1
    fi
    log_success "Resource group exists: $RESOURCE_GROUP"

    # Check naming convention (should be rg-ai-core)
    if [[ ! "$RESOURCE_GROUP" =~ ^rg-ai-[a-z]+$ ]]; then
        log_warning "Resource group name doesn't follow convention: rg-ai-{service}"
    else
        log_success "Naming convention followed: $RESOURCE_GROUP"
    fi

    # Check required tags
    local tags=$(az group show --name "$RESOURCE_GROUP" --query tags -o json)
    
    if echo "$tags" | jq -e '.environment' > /dev/null; then
        log_success "Tag 'environment' present: $(echo "$tags" | jq -r '.environment')"
    else
        log_fail "Missing required tag: environment"
    fi

    if echo "$tags" | jq -e '.purpose' > /dev/null; then
        log_success "Tag 'purpose' present"
    else
        log_fail "Missing required tag: purpose"
    fi

    if echo "$tags" | jq -e '.owner' > /dev/null; then
        log_success "Tag 'owner' present: $(echo "$tags" | jq -r '.owner')"
    else
        log_fail "Missing required tag: owner"
    fi

    echo ""
}

validate_virtual_wan() {
    log_info "Validating Virtual WAN..."

    # Find Virtual WAN
    local vwan_name=$(az network vwan list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)
    
    if [ -z "$vwan_name" ]; then
        log_fail "Virtual WAN not found in resource group"
        return 1
    fi
    log_success "Virtual WAN found: $vwan_name"

    # Check provisioning state
    local vwan_state=$(az network vwan show --resource-group "$RESOURCE_GROUP" --name "$vwan_name" --query provisioningState -o tsv)
    if [ "$vwan_state" == "Succeeded" ]; then
        log_success "Virtual WAN provisioning state: $vwan_state"
    else
        log_fail "Virtual WAN provisioning state: $vwan_state (expected: Succeeded)"
    fi

    # Check SKU (should be Standard)
    local vwan_type=$(az network vwan show --resource-group "$RESOURCE_GROUP" --name "$vwan_name" --query 'typePropertiesType' -o tsv)
    if [ "$vwan_type" == "Standard" ]; then
        log_success "Virtual WAN SKU: Standard"
    else
        log_fail "Virtual WAN SKU: $vwan_type (expected: Standard)"
    fi

    echo ""
}

validate_virtual_hub() {
    log_info "Validating Virtual Hub..."

    # Find Virtual Hub
    local vhub_name=$(az network vhub list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)
    
    if [ -z "$vhub_name" ]; then
        log_fail "Virtual Hub not found in resource group"
        return 1
    fi
    log_success "Virtual Hub found: $vhub_name"

    # Check provisioning state
    local vhub_state=$(az network vhub show --resource-group "$RESOURCE_GROUP" --name "$vhub_name" --query provisioningState -o tsv)
    if [ "$vhub_state" == "Succeeded" ]; then
        log_success "Virtual Hub provisioning state: $vhub_state"
    else
        log_fail "Virtual Hub provisioning state: $vhub_state (expected: Succeeded)"
    fi

    # Check routing state (CRITICAL: must be "Provisioned" to accept spoke connections)
    local routing_state=$(az network vhub show --resource-group "$RESOURCE_GROUP" --name "$vhub_name" --query routingState -o tsv)
    if [ "$routing_state" == "Provisioned" ]; then
        log_success "Virtual Hub routing state: $routing_state (ready for spoke connections)"
    else
        log_warning "Virtual Hub routing state: $routing_state (expected: Provisioned)"
    fi

    # Check address prefix
    local address_prefix=$(az network vhub show --resource-group "$RESOURCE_GROUP" --name "$vhub_name" --query addressPrefix -o tsv)
    log_success "Virtual Hub address prefix: $address_prefix"

    echo ""
}

validate_vpn_gateway() {
    log_info "Validating VPN Gateway..."

    # Find VPN Gateway
    local vpngw_name=$(az network vpn-gateway list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)
    
    if [ -z "$vpngw_name" ]; then
        log_fail "VPN Gateway not found in resource group"
        return 1
    fi
    log_success "VPN Gateway found: $vpngw_name"

    # Check provisioning state
    local vpngw_state=$(az network vpn-gateway show --resource-group "$RESOURCE_GROUP" --name "$vpngw_name" --query provisioningState -o tsv)
    if [ "$vpngw_state" == "Succeeded" ]; then
        log_success "VPN Gateway provisioning state: $vpngw_state"
    else
        log_fail "VPN Gateway provisioning state: $vpngw_state (expected: Succeeded)"
    fi

    # Check BGP configuration (CRITICAL for Global Secure Access)
    local bgp_asn=$(az network vpn-gateway show --resource-group "$RESOURCE_GROUP" --name "$vpngw_name" --query 'bgpSettings.asn' -o tsv)
    if [ -n "$bgp_asn" ]; then
        log_success "VPN Gateway BGP enabled (ASN: $bgp_asn)"
    else
        log_fail "VPN Gateway BGP not configured (required for Global Secure Access)"
    fi

    # Get BGP peering address for Global Secure Access configuration
    local bgp_peering=$(az network vpn-gateway show --resource-group "$RESOURCE_GROUP" --name "$vpngw_name" --query 'bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0]' -o tsv)
    if [ -n "$bgp_peering" ]; then
        log_success "VPN Gateway BGP peering address: $bgp_peering"
        log_info "  ℹ Use this address for Global Secure Access configuration"
    fi

    # Check scale units
    local scale_units=$(az network vpn-gateway show --resource-group "$RESOURCE_GROUP" --name "$vpngw_name" --query 'vpnGatewayScaleUnit' -o tsv)
    log_success "VPN Gateway scale units: $scale_units ($(($scale_units * 500)) Mbps aggregate)"

    echo ""
}

validate_key_vault() {
    log_info "Validating Key Vault..."

    # Find Key Vault
    local kv_name=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)
    
    if [ -z "$kv_name" ]; then
        log_fail "Key Vault not found in resource group"
        return 1
    fi
    log_success "Key Vault found: $kv_name"

    # Check RBAC authorization (constitutional requirement)
    local rbac_enabled=$(az keyvault show --name "$kv_name" --query 'properties.enableRbacAuthorization' -o tsv)
    if [ "$rbac_enabled" == "true" ]; then
        log_success "Key Vault RBAC authorization enabled"
    else
        log_fail "Key Vault RBAC authorization disabled (constitution requires RBAC)"
    fi

    # Check soft-delete
    local soft_delete=$(az keyvault show --name "$kv_name" --query 'properties.enableSoftDelete' -o tsv)
    if [ "$soft_delete" == "true" ]; then
        log_success "Key Vault soft-delete enabled"
    else
        log_warning "Key Vault soft-delete disabled (recommended to enable)"
    fi

    # Test access with secret operations (with timeout to prevent hanging)
    log_info "Testing Key Vault access..."
    if timeout 10 az keyvault secret set --vault-name "$kv_name" --name "validation-test" --value "success" &> /dev/null; then
        log_success "Key Vault write access verified"
        
        # Test read
        local secret_value=$(timeout 10 az keyvault secret show --vault-name "$kv_name" --name "validation-test" --query value -o tsv 2>/dev/null)
        if [ "$secret_value" == "success" ]; then
            log_success "Key Vault read access verified"
        else
            log_fail "Key Vault read access failed"
        fi
        
        # Cleanup test secret
        timeout 10 az keyvault secret delete --vault-name "$kv_name" --name "validation-test" &> /dev/null || true
    else
        log_warning "Key Vault write access denied (may need RBAC role assignment)"
        log_info "  ℹ Assign role: az role assignment create --role 'Key Vault Secrets Officer' --assignee <user> --scope <vault-id>"
    fi

    echo ""
}

validate_configuration_drift() {
    log_info "Checking configuration drift (what-if analysis)..."

    if [ ! -f "$TEMPLATE_FILE" ] || [ ! -f "$PARAMETER_FILE" ]; then
        log_warning "Template or parameter file not found, skipping drift detection"
        echo ""
        return 0
    fi

    # Run what-if in no-change mode
    local whatif_output=$(az deployment sub what-if \
        --name "validate-drift-$(date +%s)" \
        --location eastus2 \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --no-pretty-print 2>&1)

    if echo "$whatif_output" | grep -q "No changes"; then
        log_success "No configuration drift detected (deployment is idempotent)"
    elif echo "$whatif_output" | grep -q "Create\|Delete\|Modify"; then
        log_warning "Configuration drift detected - manual changes may have been made"
        log_info "  ℹ Review what-if output for details"
    else
        log_info "What-if analysis completed (check output for details)"
    fi

    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
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

# Main execution
log_info "Core Azure vWAN Infrastructure Validation"
log_info "=========================================="
echo ""

check_prerequisites
validate_resource_group
validate_virtual_wan
validate_virtual_hub
validate_vpn_gateway
validate_key_vault
validate_configuration_drift

# Summary
echo "========================================"
echo "Validation Summary"
echo "========================================"
echo -e "${GREEN}Passed: $CHECKS_PASSED${NC}"
echo -e "${YELLOW}Warnings: $CHECKS_WARNING${NC}"
echo -e "${RED}Failed: $CHECKS_FAILED${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    log_success "All critical validations passed!"
    echo ""
    log_info "Next steps:"
    echo "  1. Configure Global Secure Access: docs/core-infrastructure/global-secure-access.md"
    echo "  2. Deploy spoke labs and connect to hub"
    echo ""
    exit 0
else
    log_fail "Validation failed with $CHECKS_FAILED error(s)"
    echo ""
    log_info "Review errors above and resolve before proceeding"
    exit 1
fi
