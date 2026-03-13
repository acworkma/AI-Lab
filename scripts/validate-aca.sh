#!/usr/bin/env bash
#
# validate-aca.sh - Validate ACA Deployment Prerequisites
# 
# Purpose: Pre-deployment validation of Azure login, core infrastructure, 
#          and Bicep template syntax for Container Apps environment
#
# Usage: ./scripts/validate-aca.sh [--parameter-file <path>] [--deployed]
#
# Prerequisites:
# - Azure CLI installed and logged in
# - Core infrastructure deployed (rg-ai-core with VNet, ACA subnet, and DNS zones)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/aca/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/aca/main.bicep"
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

Validate ACA environment deployment prerequisites and configuration

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/aca/main.parameters.json)
    -d, --deployed              Validate deployed resources (vs prerequisites only)
    -h, --help                  Show this help message

VALIDATION MODES:
    Default (prerequisites):
        - Azure CLI login status
        - Required permissions check
        - Parameter file syntax and required fields
        - Bicep template syntax
        - Core infrastructure (VNet, ACA subnet, PE subnet, DNS zone)

    Deployed (--deployed):
        - All prerequisite validations
        - ACA environment provisioning state
        - Internal-only ingress configuration
        - VNet injection status
        - Public network access disabled
        - Private endpoint status
        - Log Analytics connection

EXAMPLES:
    # Validate prerequisites before deployment
    $0

    # Validate deployed infrastructure
    $0 --deployed

    # Use custom parameter file
    $0 --parameter-file bicep/aca/main.parameters.prod.json

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
    
    # Check ACA subnet exists (for VNet injection)
    local ACA_SUBNET_NAME
    ACA_SUBNET_NAME=$(jq -r '.parameters.acaSubnetName.value // "AcaEnvironmentSubnet"' "$PARAMETER_FILE")
    
    if ! az network vnet subnet show --name "$ACA_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$CORE_RG" &> /dev/null; then
        log_error "ACA subnet not found: $ACA_SUBNET_NAME in $VNET_NAME"
        log_info "Core infrastructure may need redeployment to add ACA subnet"
        return 1
    fi
    log_success "ACA subnet exists: $ACA_SUBNET_NAME"
    
    # Check ACA subnet delegation
    local DELEGATION
    DELEGATION=$(az network vnet subnet show --name "$ACA_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$CORE_RG" \
        --query "delegations[?serviceName=='Microsoft.App/environments'].serviceName" -o tsv 2>/dev/null || true)
    if [[ "$DELEGATION" != "Microsoft.App/environments" ]]; then
        log_error "ACA subnet missing delegation: Microsoft.App/environments"
        return 1
    fi
    log_success "ACA subnet delegation configured: Microsoft.App/environments"
    
    # Check private endpoint subnet exists
    local PE_SUBNET_NAME
    PE_SUBNET_NAME=$(jq -r '.parameters.privateEndpointSubnetName.value // "PrivateEndpointSubnet"' "$PARAMETER_FILE")
    
    if ! az network vnet subnet show --name "$PE_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$CORE_RG" &> /dev/null; then
        log_error "Private endpoint subnet not found: $PE_SUBNET_NAME in $VNET_NAME"
        return 1
    fi
    log_success "Private endpoint subnet exists: $PE_SUBNET_NAME"
    
    # Check private DNS zone exists
    local DNS_ZONE="privatelink.azurecontainerapps.io"
    
    if ! az network private-dns zone show --name "$DNS_ZONE" --resource-group "$CORE_RG" &> /dev/null; then
        log_error "Private DNS zone not found: $DNS_ZONE in $CORE_RG"
        log_info "This zone should be created by core infrastructure deployment"
        return 1
    fi
    log_success "Private DNS zone exists: $DNS_ZONE"
}

validate_permissions() {
    log_info "Checking required permissions..."
    
    # Check if user can read role assignments (basic permission check)
    local SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    
    if ! az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[0]" &> /dev/null; then
        log_warning "Cannot verify permissions. Ensure you have Contributor role on subscription."
    else
        log_success "Permission check passed (can read role assignments)"
    fi
    
    # Advisory checks
    local CORE_RG
    CORE_RG=$(jq -r '.parameters.coreResourceGroupName.value // "rg-ai-core"' "$PARAMETER_FILE")
    local VNET_NAME
    VNET_NAME=$(jq -r '.parameters.vnetName.value // "vnet-ai-shared"' "$PARAMETER_FILE")
    
    log_info "Verify you have Network Contributor on: $VNET_NAME in $CORE_RG"
}

# ============================================================================
# DEPLOYED RESOURCE VALIDATION
# ============================================================================

validate_deployed_aca() {
    log_info "Validating deployed ACA environment..."
    
    local RG_NAME
    RG_NAME=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-aca"' "$PARAMETER_FILE")
    local ENV_NAME
    ENV_NAME=$(jq -r '.parameters.environmentName.value // "cae-ai-lab"' "$PARAMETER_FILE")
    
    # Check resource group exists
    if ! az group show --name "$RG_NAME" &> /dev/null; then
        log_error "Resource group not found: $RG_NAME"
        return 1
    fi
    log_success "Resource group exists: $RG_NAME"
    
    # Check ACA environment exists
    if ! az containerapp env show --name "$ENV_NAME" --resource-group "$RG_NAME" &> /dev/null; then
        log_error "ACA environment not found: $ENV_NAME in $RG_NAME"
        return 1
    fi
    log_success "ACA environment exists: $ENV_NAME"
    
    # Check provisioning state
    local PROV_STATE
    PROV_STATE=$(az containerapp env show --name "$ENV_NAME" --resource-group "$RG_NAME" \
        --query "properties.provisioningState" -o tsv)
    if [[ "$PROV_STATE" != "Succeeded" ]]; then
        log_error "ACA environment provisioning state: $PROV_STATE (expected: Succeeded)"
        return 1
    fi
    log_success "ACA environment provisioned: $PROV_STATE"
    
    # Check VNet configuration (internal only)
    local INTERNAL
    INTERNAL=$(az containerapp env show --name "$ENV_NAME" --resource-group "$RG_NAME" \
        --query "properties.vnetConfiguration.internal" -o tsv)
    if [[ "$INTERNAL" != "true" ]]; then
        log_error "ACA environment not configured as internal-only"
        return 1
    fi
    log_success "Internal-only ingress configured"
    
    # Check default domain
    local DOMAIN
    DOMAIN=$(az containerapp env show --name "$ENV_NAME" --resource-group "$RG_NAME" \
        --query "properties.defaultDomain" -o tsv)
    log_success "Default domain: $DOMAIN"
    
    # Check static IP
    local STATIC_IP
    STATIC_IP=$(az containerapp env show --name "$ENV_NAME" --resource-group "$RG_NAME" \
        --query "properties.staticIp" -o tsv)
    log_success "Static IP: $STATIC_IP"
    
    # Check private endpoint
    local PE_COUNT
    PE_COUNT=$(az network private-endpoint list --resource-group "$RG_NAME" \
        --query "length([?contains(name, '$(echo "$ENV_NAME" | tr '[:upper:]' '[:lower:]')')])" -o tsv 2>/dev/null || echo "0")
    if [[ "$PE_COUNT" -lt 1 ]]; then
        # Broader search for any PE in the resource group
        PE_COUNT=$(az network private-endpoint list --resource-group "$RG_NAME" --query "length([])" -o tsv 2>/dev/null || echo "0")
    fi
    if [[ "$PE_COUNT" -lt 1 ]]; then
        log_error "No private endpoint found for ACA environment"
        return 1
    fi
    log_success "Private endpoint configured ($PE_COUNT endpoints)"
    
    # Check Log Analytics connection
    local LA_CUSTOMER_ID
    LA_CUSTOMER_ID=$(az containerapp env show --name "$ENV_NAME" --resource-group "$RG_NAME" \
        --query "properties.appLogsConfiguration.logAnalyticsConfiguration.customerId" -o tsv 2>/dev/null || true)
    if [[ -z "$LA_CUSTOMER_ID" || "$LA_CUSTOMER_ID" == "null" ]]; then
        log_warning "Log Analytics not connected to ACA environment"
    else
        log_success "Log Analytics connected (customer ID: ${LA_CUSTOMER_ID:0:8}...)"
    fi
    
    echo ""
    log_info "ACA environment validation complete: $ENV_NAME"
}

# ============================================================================
# MAIN
# ============================================================================

echo ""
echo "============================================"
echo "ACA Environment Deployment Validation"
echo "============================================"
echo ""

# Run prerequisite validations
validate_azure_login
validate_parameter_file
validate_template_syntax
validate_core_infrastructure
validate_permissions

# Run deployed validation if requested
if [[ "$VALIDATE_DEPLOYED" == "true" ]]; then
    echo ""
    echo "--- Deployed Resource Validation ---"
    echo ""
    validate_deployed_aca
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
