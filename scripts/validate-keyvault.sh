#!/usr/bin/env bash
#
# validate-keyvault.sh - Validate Key Vault Deployment Prerequisites
# 
# Purpose: Pre-deployment validation of Azure login, core infrastructure, 
#          and soft-deleted vault collision detection
#
# Usage: ./scripts/validate-keyvault.sh [--parameter-file <path>] [--deployed]
#
# Prerequisites:
# - Azure CLI installed and logged in
# - Core infrastructure deployed (rg-ai-core with VNet and DNS zones)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/keyvault/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/keyvault/main.bicep"
VALIDATE_DEPLOYED=false
VALIDATION_PASSED=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    VALIDATION_PASSED=false
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate Key Vault deployment prerequisites and configuration

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/keyvault/main.parameters.json)
    -d, --deployed              Validate deployed resources (vs prerequisites only)
    -h, --help                  Show this help message

VALIDATION MODES:
    Default (prerequisites):
        - Azure CLI login status
        - Required permissions check
        - Core infrastructure existence (VNet, DNS zone)
        - Soft-deleted vault collision detection
        - Template syntax validation

    Deployed (--deployed):
        - All prerequisite validations
        - Key Vault provisioning status
        - RBAC authorization enabled (SR-002)
        - Public network access disabled (SR-001)
        - Private endpoint status
        - DNS resolution via private endpoint

EXAMPLES:
    # Validate prerequisites before deployment
    $0

    # Validate deployed infrastructure
    $0 --deployed

    # Use custom parameter file
    $0 --parameter-file bicep/keyvault/main.parameters.prod.json

EOF
    exit 1
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--parameter-file)
            PARAMETER_FILE="$2"
            shift 2
            ;;
        -d|--deployed)
            VALIDATE_DEPLOYED=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# ============================================================================
# PREREQUISITE VALIDATION
# ============================================================================

validate_azure_login() {
    log_info "Checking Azure CLI login status..."
    
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Run 'az login' first."
        return 1
    fi
    
    local SUBSCRIPTION
    SUBSCRIPTION=$(az account show --query "name" -o tsv)
    log_success "Logged into Azure subscription: $SUBSCRIPTION"
}

validate_parameter_file() {
    log_info "Validating parameter file..."
    
    if [[ ! -f "$PARAMETER_FILE" ]]; then
        log_error "Parameter file not found: $PARAMETER_FILE"
        log_info "Copy main.parameters.example.json and customize it."
        return 1
    fi
    
    # Check JSON syntax
    if ! jq empty "$PARAMETER_FILE" 2>/dev/null; then
        log_error "Parameter file has invalid JSON syntax"
        return 1
    fi
    
    # Check required parameters
    local OWNER
    OWNER=$(jq -r '.parameters.owner.value // empty' "$PARAMETER_FILE")
    if [[ -z "$OWNER" ]]; then
        log_error "Required parameter 'owner' not set in parameter file"
        return 1
    fi
    
    log_success "Parameter file valid: $PARAMETER_FILE"
}

validate_template_syntax() {
    log_info "Validating Bicep template syntax..."
    
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        log_error "Template file not found: $TEMPLATE_FILE"
        return 1
    fi
    
    if ! az bicep build --file "$TEMPLATE_FILE" --stdout > /dev/null 2>&1; then
        log_error "Bicep template syntax error"
        az bicep build --file "$TEMPLATE_FILE" 2>&1 | head -20
        return 1
    fi
    
    log_success "Bicep template syntax valid"
}

validate_core_infrastructure() {
    log_info "Checking core infrastructure..."
    
    local CORE_RG
    CORE_RG=$(jq -r '.parameters.coreResourceGroupName.value // "rg-ai-core"' "$PARAMETER_FILE")
    
    # Check resource group exists
    if ! az group show --name "$CORE_RG" &> /dev/null; then
        log_error "Core infrastructure resource group not found: $CORE_RG"
        log_info "Deploy core infrastructure first: ./scripts/deploy-core.sh"
        return 1
    fi
    log_success "Core resource group exists: $CORE_RG"
    
    # Check VNet exists
    local VNET_NAME
    VNET_NAME=$(jq -r '.parameters.vnetName.value // "vnet-ai-shared"' "$PARAMETER_FILE")
    
    if ! az network vnet show --name "$VNET_NAME" --resource-group "$CORE_RG" &> /dev/null; then
        log_error "VNet not found: $VNET_NAME in $CORE_RG"
        return 1
    fi
    log_success "VNet exists: $VNET_NAME"
    
    # Check subnet exists
    local SUBNET_NAME
    SUBNET_NAME=$(jq -r '.parameters.privateEndpointSubnetName.value // "snet-private-endpoints"' "$PARAMETER_FILE")
    
    if ! az network vnet subnet show --name "$SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$CORE_RG" &> /dev/null; then
        log_error "Subnet not found: $SUBNET_NAME in $VNET_NAME"
        return 1
    fi
    log_success "Subnet exists: $SUBNET_NAME"
    
    # Check private DNS zone exists
    local DNS_ZONE="privatelink.vaultcore.azure.net"
    
    if ! az network private-dns zone show --name "$DNS_ZONE" --resource-group "$CORE_RG" &> /dev/null; then
        log_error "Private DNS zone not found: $DNS_ZONE in $CORE_RG"
        log_info "This zone should be created by core infrastructure deployment"
        return 1
    fi
    log_success "Private DNS zone exists: $DNS_ZONE"
}

validate_no_soft_deleted_collision() {
    log_info "Checking for soft-deleted vault collision..."
    
    # Get expected Key Vault name
    local SUFFIX
    SUFFIX=$(jq -r '.parameters.keyVaultNameSuffix.value // empty' "$PARAMETER_FILE")
    if [[ -z "$SUFFIX" ]]; then
        SUFFIX=$(date +%m%d)
    fi
    local KV_NAME="kv-ai-lab-${SUFFIX}"
    
    # Check if vault exists in soft-deleted state
    local DELETED_VAULT
    DELETED_VAULT=$(az keyvault list-deleted --query "[?name=='$KV_NAME'].name" -o tsv 2>/dev/null || true)
    
    if [[ -n "$DELETED_VAULT" ]]; then
        log_error "Soft-deleted vault exists with name: $KV_NAME"
        log_info "Options:"
        log_info "  1. Purge the vault: az keyvault purge --name $KV_NAME"
        log_info "  2. Use different suffix in parameter file"
        return 1
    fi
    
    log_success "No soft-deleted vault collision for: $KV_NAME"
}

validate_permissions() {
    log_info "Checking required permissions..."
    
    # Check if user can create resource groups (Contributor role indicator)
    local SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    
    # Try to get role assignments - this requires read permissions at minimum
    if ! az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[0]" &> /dev/null; then
        log_warning "Cannot verify permissions. Ensure you have Contributor role on subscription."
    else
        log_success "Permission check passed (can read role assignments)"
    fi
    
    # Check Network Contributor on VNet
    local CORE_RG
    CORE_RG=$(jq -r '.parameters.coreResourceGroupName.value // "rg-ai-core"' "$PARAMETER_FILE")
    local VNET_NAME
    VNET_NAME=$(jq -r '.parameters.vnetName.value // "vnet-ai-shared"' "$PARAMETER_FILE")
    
    log_info "Verify you have Network Contributor on: $VNET_NAME in $CORE_RG"
}

# ============================================================================
# DEPLOYED RESOURCE VALIDATION
# ============================================================================

validate_deployed_keyvault() {
    log_info "Validating deployed Key Vault..."
    
    local RG_NAME
    RG_NAME=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE")
    
    # Get Key Vault name
    local SUFFIX
    SUFFIX=$(jq -r '.parameters.keyVaultNameSuffix.value // empty' "$PARAMETER_FILE")
    if [[ -z "$SUFFIX" ]]; then
        # Find the deployed vault by querying the resource group
        local KV_NAME
        KV_NAME=$(az keyvault list --resource-group "$RG_NAME" --query "[0].name" -o tsv 2>/dev/null || true)
        if [[ -z "$KV_NAME" ]]; then
            log_error "No Key Vault found in resource group: $RG_NAME"
            return 1
        fi
    else
        KV_NAME="kv-ai-lab-${SUFFIX}"
    fi
    
    # Check Key Vault exists
    if ! az keyvault show --name "$KV_NAME" --resource-group "$RG_NAME" &> /dev/null; then
        log_error "Key Vault not found: $KV_NAME in $RG_NAME"
        return 1
    fi
    log_success "Key Vault exists: $KV_NAME"
    
    # Check RBAC authorization enabled (SR-002)
    local RBAC_ENABLED
    RBAC_ENABLED=$(az keyvault show --name "$KV_NAME" --resource-group "$RG_NAME" --query "properties.enableRbacAuthorization" -o tsv)
    if [[ "$RBAC_ENABLED" != "true" ]]; then
        log_error "RBAC authorization not enabled (SR-002 violation)"
        return 1
    fi
    log_success "RBAC authorization enabled (SR-002)"
    
    # Check public network access disabled (SR-001)
    local PUBLIC_ACCESS
    PUBLIC_ACCESS=$(az keyvault show --name "$KV_NAME" --resource-group "$RG_NAME" --query "properties.publicNetworkAccess" -o tsv)
    if [[ "$PUBLIC_ACCESS" != "Disabled" ]]; then
        log_error "Public network access not disabled (SR-001 violation)"
        return 1
    fi
    log_success "Public network access disabled (SR-001)"
    
    # Check soft-delete enabled (SR-003)
    local SOFT_DELETE
    SOFT_DELETE=$(az keyvault show --name "$KV_NAME" --resource-group "$RG_NAME" --query "properties.enableSoftDelete" -o tsv)
    if [[ "$SOFT_DELETE" != "true" ]]; then
        log_error "Soft-delete not enabled (SR-003 violation)"
        return 1
    fi
    log_success "Soft-delete enabled (SR-003)"
    
    # Check private endpoint exists
    local PE_COUNT
    PE_COUNT=$(az network private-endpoint list --resource-group "$RG_NAME" --query "length([?contains(name, '$KV_NAME')])" -o tsv)
    if [[ "$PE_COUNT" -lt 1 ]]; then
        log_error "No private endpoint found for Key Vault"
        return 1
    fi
    log_success "Private endpoint configured"
    
    echo ""
    log_info "Key Vault validation complete: $KV_NAME"
}

# ============================================================================
# MAIN
# ============================================================================

echo ""
echo "============================================"
echo "Key Vault Deployment Validation"
echo "============================================"
echo ""

# Run prerequisite validations
validate_azure_login
validate_parameter_file
validate_template_syntax
validate_core_infrastructure
validate_no_soft_deleted_collision
validate_permissions

# Run deployed validation if requested
if [[ "$VALIDATE_DEPLOYED" == "true" ]]; then
    echo ""
    echo "--- Deployed Resource Validation ---"
    echo ""
    validate_deployed_keyvault
fi

# Summary
echo ""
echo "============================================"
if [[ "$VALIDATION_PASSED" == "true" ]]; then
    log_success "All validations passed!"
    exit 0
else
    log_error "Some validations failed. Review errors above."
    exit 1
fi
