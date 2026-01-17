#!/bin/bash
# ============================================================================
# Script: deploy-storage-infra.sh
# Purpose: Deploy Private Azure Storage Account infrastructure
# Feature: 009-private-storage
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BICEP_DIR="${REPO_ROOT}/bicep/storage-infra"

# Defaults
PARAMETER_FILE="${BICEP_DIR}/main.parameters.json"
AUTO_APPROVE=false
DEPLOYMENT_NAME="storage-infra-$(date +%Y%m%d-%H%M%S)"

# ============================================================================
# Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Deploy Private Azure Storage Account infrastructure.

Options:
    -p, --parameters FILE    Parameter file path (default: main.parameters.json)
    -y, --yes                Skip confirmation prompts
    -h, --help               Show this help message

Examples:
    $(basename "$0")                           # Deploy with defaults
    $(basename "$0") --yes                     # Deploy without prompts
    $(basename "$0") -p custom.parameters.json # Use custom parameters

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Install from https://aka.ms/azure-cli"
        exit 1
    fi
    log_success "Azure CLI installed"
    
    # Check logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first."
        exit 1
    fi
    log_success "Azure CLI authenticated"
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Install with: sudo apt install jq"
        exit 1
    fi
    log_success "jq installed"
    
    # Check parameter file exists
    if [[ ! -f "$PARAMETER_FILE" ]]; then
        log_error "Parameter file not found: $PARAMETER_FILE"
        exit 1
    fi
    log_success "Parameter file exists: $PARAMETER_FILE"
    
    # Check Bicep files exist
    if [[ ! -f "${BICEP_DIR}/main.bicep" ]]; then
        log_error "Bicep template not found: ${BICEP_DIR}/main.bicep"
        exit 1
    fi
    log_success "Bicep template exists"
}

check_core_infrastructure() {
    log_info "Checking core infrastructure..."
    
    local core_rg=$(jq -r '.parameters.coreResourceGroupName.value' "$PARAMETER_FILE")
    local vnet_name=$(jq -r '.parameters.vnetName.value' "$PARAMETER_FILE")
    local subnet_name=$(jq -r '.parameters.subnetName.value' "$PARAMETER_FILE")
    
    # Check core resource group
    if ! az group show --name "$core_rg" &> /dev/null; then
        log_error "Core resource group not found: $core_rg"
        log_error "Deploy core infrastructure first with ./scripts/deploy-core.sh"
        exit 1
    fi
    log_success "Core resource group exists: $core_rg"
    
    # Check VNet
    if ! az network vnet show --resource-group "$core_rg" --name "$vnet_name" &> /dev/null; then
        log_error "VNet not found: $vnet_name in $core_rg"
        exit 1
    fi
    log_success "VNet exists: $vnet_name"
    
    # Check subnet
    if ! az network vnet subnet show --resource-group "$core_rg" --vnet-name "$vnet_name" --name "$subnet_name" &> /dev/null; then
        log_error "Subnet not found: $subnet_name in $vnet_name"
        exit 1
    fi
    log_success "Subnet exists: $subnet_name"
    
    # Check private DNS zone
    if ! az network private-dns zone show --resource-group "$core_rg" --name "privatelink.blob.core.windows.net" &> /dev/null; then
        log_error "Private DNS zone not found: privatelink.blob.core.windows.net"
        exit 1
    fi
    log_success "Private DNS zone exists: privatelink.blob.core.windows.net"
}

check_storage_name_available() {
    log_info "Checking storage account name availability..."
    
    local suffix=$(jq -r '.parameters.storageNameSuffix.value' "$PARAMETER_FILE")
    local storage_name="stailab${suffix}"
    
    # First check if it already exists in our resource group (allow update)
    if az storage account show --name "$storage_name" --resource-group "rg-ai-storage" &> /dev/null; then
        log_success "Storage account exists (update mode): $storage_name"
        return 0
    fi
    
    local result=$(az storage account check-name --name "$storage_name" --query 'nameAvailable' -o tsv)
    
    if [[ "$result" == "true" ]]; then
        log_success "Storage account name available: $storage_name"
    else
        local reason=$(az storage account check-name --name "$storage_name" --query 'reason' -o tsv)
        log_error "Storage account name not available: $storage_name"
        log_error "Reason: $reason"
        log_error "Try a different storageNameSuffix in your parameter file"
        exit 1
    fi
}

run_what_if() {
    log_info "Running what-if analysis..."
    
    az deployment sub what-if \
        --location "$(jq -r '.parameters.location.value' "$PARAMETER_FILE")" \
        --template-file "${BICEP_DIR}/main.bicep" \
        --parameters "$PARAMETER_FILE" \
        --name "$DEPLOYMENT_NAME"
    
    echo ""
}

confirm_deployment() {
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    read -p "Proceed with deployment? [y/N]: " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Deployment cancelled by user"
        exit 2
    fi
}

deploy() {
    log_info "Deploying Private Storage Account infrastructure..."
    
    local start_time=$(date +%s)
    
    az deployment sub create \
        --location "$(jq -r '.parameters.location.value' "$PARAMETER_FILE")" \
        --template-file "${BICEP_DIR}/main.bicep" \
        --parameters "$PARAMETER_FILE" \
        --name "$DEPLOYMENT_NAME" \
        --output json > /tmp/deployment-output.json
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "Deployment completed in ${duration} seconds"
    
    # Extract outputs
    local storage_name=$(jq -r '.properties.outputs.storageAccountName.value' /tmp/deployment-output.json)
    local blob_endpoint=$(jq -r '.properties.outputs.blobEndpoint.value' /tmp/deployment-output.json)
    local pe_name=$(jq -r '.properties.outputs.privateEndpointName.value' /tmp/deployment-output.json)
    local rg_name=$(jq -r '.properties.outputs.resourceGroupName.value' /tmp/deployment-output.json)
    
    # Get private IP via network interface (not available in Bicep output)
    local nic_id=$(az network private-endpoint show --name "$pe_name" --resource-group "$rg_name" --query 'networkInterfaces[0].id' -o tsv 2>/dev/null)
    local private_ip="(pending)"
    if [[ -n "$nic_id" ]]; then
        private_ip=$(az network nic show --ids "$nic_id" --query 'ipConfigurations[0].privateIPAddress' -o tsv 2>/dev/null || echo "(pending)")
    fi
    
    echo ""
    echo "=========================================="
    echo "         Deployment Summary"
    echo "=========================================="
    echo "Resource Group:    $rg_name"
    echo "Storage Account:   $storage_name"
    echo "Blob Endpoint:     $blob_endpoint"
    echo "Private IP:        $private_ip"
    echo "Deployment Time:   ${duration}s"
    echo "=========================================="
}

post_deployment_validation() {
    log_info "Running post-deployment validation..."
    
    local storage_name=$(jq -r '.properties.outputs.storageAccountName.value' /tmp/deployment-output.json)
    local rg_name=$(jq -r '.properties.outputs.resourceGroupName.value' /tmp/deployment-output.json)
    
    # Check storage account exists
    if az storage account show --name "$storage_name" --resource-group "$rg_name" &> /dev/null; then
        log_success "Storage account created: $storage_name"
    else
        log_error "Storage account not found: $storage_name"
        exit 4
    fi
    
    # Check shared key access disabled
    local shared_key=$(az storage account show --name "$storage_name" --resource-group "$rg_name" --query 'allowSharedKeyAccess' -o tsv)
    if [[ "$shared_key" == "false" ]]; then
        log_success "Shared key access disabled"
    else
        log_warn "Shared key access is enabled (expected: disabled)"
    fi
    
    # Check public access disabled
    local public_access=$(az storage account show --name "$storage_name" --resource-group "$rg_name" --query 'publicNetworkAccess' -o tsv)
    if [[ "$public_access" == "Disabled" ]]; then
        log_success "Public network access disabled"
    else
        log_warn "Public network access: $public_access (expected: Disabled)"
    fi
    
    # Check TLS version
    local tls_version=$(az storage account show --name "$storage_name" --resource-group "$rg_name" --query 'minimumTlsVersion' -o tsv)
    if [[ "$tls_version" == "TLS1_2" ]]; then
        log_success "TLS 1.2 enforced"
    else
        log_warn "TLS version: $tls_version (expected: TLS1_2)"
    fi
    
    log_success "Post-deployment validation complete"
}

# ============================================================================
# Main
# ============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--parameters)
            PARAMETER_FILE="$2"
            shift 2
            ;;
        -y|--yes)
            AUTO_APPROVE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

echo ""
echo "=========================================="
echo "  Private Storage Account Deployment"
echo "=========================================="
echo ""

# Run deployment steps
check_prerequisites
check_core_infrastructure
check_storage_name_available
run_what_if
confirm_deployment
deploy
post_deployment_validation

echo ""
log_success "Deployment complete!"
echo ""
echo "Next steps:"
echo "  1. Connect to VPN"
echo "  2. Run ./scripts/validate-storage-infra-dns.sh to verify DNS"
echo "  3. Run ./scripts/grant-storage-infra-roles.sh to assign RBAC roles"
echo ""
