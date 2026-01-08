#!/usr/bin/env bash
#
# deploy-storage.sh - Deploy Private Azure Storage Account with CMK
# 
# Purpose: Orchestrate deployment of storage resource group and CMK-enabled storage account
#          with private endpoint connectivity to core infrastructure
#
# Usage: ./scripts/deploy-storage.sh [--parameter-file <path>] [--skip-whatif] [--auto-approve]
#
# Prerequisites:
# - Core infrastructure deployed (run scripts/deploy-core.sh first)
# - VPN connection established (for DNS verification)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/storage/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/storage/main.bicep"
DEPLOYMENT_NAME="deploy-ai-storage-$(date +%Y%m%d-%H%M%S)"
SKIP_WHATIF=false
AUTO_APPROVE=false
LOCATION="eastus"

# NFR-002: Track deployment time
START_TIME=""
END_TIME=""

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Private Azure Storage Account with CMK encryption and private endpoint

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/storage/main.parameters.json)
    -s, --skip-whatif           Skip what-if analysis (not recommended)
    -a, --auto-approve          Skip confirmation prompt (use with caution)
    -h, --help                  Show this help message

EXAMPLES:
    # Standard deployment with what-if and confirmation
    $0

    # Use custom parameter file
    $0 --parameter-file bicep/storage/main.parameters.prod.json

    # Automated deployment (CI/CD)
    $0 --auto-approve

EOF
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Run 'az login' first."
        exit 1
    fi
    
    # Check parameter file exists
    if [[ ! -f "$PARAMETER_FILE" ]]; then
        log_error "Parameter file not found: $PARAMETER_FILE"
        log_info "Copy main.parameters.example.json and customize it."
        exit 1
    fi
    
    # Check template file exists
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        log_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi
    
    # Check core infrastructure exists
    local CORE_RG
    CORE_RG=$(jq -r '.parameters.coreResourceGroupName.value // "rg-ai-core"' "$PARAMETER_FILE")
    
    if ! az group show --name "$CORE_RG" &> /dev/null; then
        log_error "Core infrastructure resource group not found: $CORE_RG"
        log_info "Deploy core infrastructure first: ./scripts/deploy-core.sh"
        exit 1
    fi
    
    # Check Key Vault exists
    local KV_NAME
    KV_NAME=$(jq -r '.parameters.keyVaultName.value' "$PARAMETER_FILE")
    
    if [[ -z "$KV_NAME" || "$KV_NAME" == "null" ]]; then
        log_error "keyVaultName not set in parameter file"
        exit 1
    fi
    
    if ! az keyvault show --name "$KV_NAME" --resource-group "$CORE_RG" &> /dev/null; then
        log_error "Key Vault not found: $KV_NAME in $CORE_RG"
        exit 1
    fi
    
    # Check VNet exists
    local VNET_NAME
    VNET_NAME=$(jq -r '.parameters.vnetName.value // "vnet-ai-sharedservices"' "$PARAMETER_FILE")
    
    if ! az network vnet show --name "$VNET_NAME" --resource-group "$CORE_RG" &> /dev/null; then
        log_error "VNet not found: $VNET_NAME in $CORE_RG"
        exit 1
    fi
    
    # Check private DNS zone exists
    local DNS_ZONE
    DNS_ZONE=$(jq -r '.parameters.privateDnsZoneName.value // "privatelink.blob.core.windows.net"' "$PARAMETER_FILE")
    
    if ! az network private-dns zone show --name "$DNS_ZONE" --resource-group "$CORE_RG" &> /dev/null; then
        log_error "Private DNS zone not found: $DNS_ZONE in $CORE_RG"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

run_whatif() {
    log_info "Running what-if analysis..."
    
    local LOCATION
    LOCATION=$(jq -r '.parameters.location.value // "eastus"' "$PARAMETER_FILE")
    
    az deployment sub what-if \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --name "$DEPLOYMENT_NAME-whatif"
    
    echo ""
    log_info "Review the changes above before proceeding."
}

confirm_deployment() {
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    read -rp "Do you want to proceed with deployment? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        log_warning "Deployment cancelled by user"
        exit 0
    fi
}

deploy() {
    log_info "Starting deployment..."
    START_TIME=$(date +%s)
    
    local LOCATION
    LOCATION=$(jq -r '.parameters.location.value // "eastus"' "$PARAMETER_FILE")
    
    az deployment sub create \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --name "$DEPLOYMENT_NAME"
    
    END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    
    log_success "Deployment completed in ${DURATION} seconds"
    
    # NFR-002: Check if deployment time exceeded 5 minutes (300 seconds)
    if [[ $DURATION -gt 300 ]]; then
        log_warning "Deployment exceeded NFR-002 target of 5 minutes (${DURATION}s > 300s)"
    else
        log_success "NFR-002 PASS: Deployment completed within 5 minutes (${DURATION}s)"
    fi
}

show_outputs() {
    log_info "Deployment outputs:"
    
    local STORAGE_RG
    STORAGE_RG=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    echo ""
    echo "Storage Account Name: $STORAGE_NAME"
    echo "Resource Group: $STORAGE_RG"
    
    # Get private endpoint IP
    local PE_IP
    PE_IP=$(az network private-endpoint show \
        --name "pe-${STORAGE_NAME}-blob" \
        --resource-group "$STORAGE_RG" \
        --query "customDnsConfigs[0].ipAddresses[0]" \
        --output tsv 2>/dev/null || echo "N/A")
    
    echo "Private Endpoint IP: $PE_IP"
    echo ""
    
    # Verify CMK encryption
    local KEY_SOURCE
    KEY_SOURCE=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "encryption.keySource" \
        --output tsv 2>/dev/null || echo "N/A")
    
    if [[ "$KEY_SOURCE" == "Microsoft.Keyvault" ]]; then
        log_success "CMK encryption verified: $KEY_SOURCE"
    else
        log_warning "CMK encryption status: $KEY_SOURCE"
    fi
    
    # Verify public access disabled
    local PUBLIC_ACCESS
    PUBLIC_ACCESS=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "publicNetworkAccess" \
        --output tsv 2>/dev/null || echo "N/A")
    
    if [[ "$PUBLIC_ACCESS" == "Disabled" ]]; then
        log_success "Public access disabled: $PUBLIC_ACCESS"
    else
        log_warning "Public access status: $PUBLIC_ACCESS"
    fi
}

grant_deployer_access() {
    log_info "Granting deployer data access..."
    
    local STORAGE_RG
    STORAGE_RG=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    # Get current user
    local CURRENT_USER
    CURRENT_USER=$(az account show --query user.name -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$CURRENT_USER" ]]; then
        log_warning "Could not determine current user - skipping data access grant"
        return
    fi
    
    # Get storage account resource ID
    local STORAGE_ID
    STORAGE_ID=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query id -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$STORAGE_ID" ]]; then
        log_warning "Could not get storage account ID - skipping data access grant"
        return
    fi
    
    # Check if role already assigned
    local EXISTING
    EXISTING=$(az role assignment list \
        --assignee "$CURRENT_USER" \
        --role "Storage Blob Data Contributor" \
        --scope "$STORAGE_ID" \
        --query "[].id" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$EXISTING" ]]; then
        log_success "Deployer already has Storage Blob Data Contributor role"
        return
    fi
    
    # Assign role
    if az role assignment create \
        --assignee "$CURRENT_USER" \
        --role "Storage Blob Data Contributor" \
        --scope "$STORAGE_ID" \
        --output none 2>/dev/null; then
        log_success "Granted Storage Blob Data Contributor to: $CURRENT_USER"
    else
        log_warning "Could not grant data access - run: ./scripts/grant-storage-roles.sh --user $CURRENT_USER"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--parameter-file)
            PARAMETER_FILE="$2"
            shift 2
            ;;
        -s|--skip-whatif)
            SKIP_WHATIF=true
            shift
            ;;
        -a|--auto-approve)
            AUTO_APPROVE=true
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

echo ""
echo "=============================================="
echo " Deploy Private Storage Account with CMK"
echo "=============================================="
echo ""

check_prerequisites

if [[ "$SKIP_WHATIF" != "true" ]]; then
    run_whatif
    confirm_deployment
fi

deploy
show_outputs
grant_deployer_access

echo ""
log_success "Storage deployment complete!"
log_info "Test connectivity: nslookup <storage-name>.blob.core.windows.net 10.1.0.68"
