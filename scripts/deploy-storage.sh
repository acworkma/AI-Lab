#!/usr/bin/env bash
#
# deploy-storage.sh - Enable CMK Encryption on Existing Storage Account
# 
# Feature: 010-storage-cmk-refactor
# Purpose: Enable customer-managed key encryption on pre-deployed storage account
#          using key from pre-deployed Key Vault
#
# Usage: ./scripts/deploy-storage.sh [--parameter-file <path>] [--skip-whatif] [--auto-approve]
#
# Prerequisites:
# - Key Vault deployed in rg-ai-keyvault (008-private-keyvault)
# - Storage Account deployed in rg-ai-storage (009-private-storage)
# - VPN connection established (for DNS verification)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/storage/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/storage/main.bicep"
DEPLOYMENT_NAME="deploy-cmk-storage-$(date +%Y%m%d-%H%M%S)"
SKIP_WHATIF=false
AUTO_APPROVE=false
LOCATION="eastus2"

# NFR-002: Track deployment time (target: < 3 minutes)
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

Enable CMK encryption on existing Storage Account using Key Vault key

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

PREREQUISITES:
    - Key Vault deployed: ./scripts/deploy-keyvault.sh
    - Storage Account deployed: Deploy via 009-private-storage

EOF
    exit 1
}

# ============================================================================
# PREREQUISITE VALIDATION (US2: T015-T020)
# ============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    local PREREQ_FAILED=false
    
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
    
    # Read parameters
    local KV_RG STORAGE_RG STORAGE_SUFFIX KV_NAME_PARAM
    KV_RG=$(jq -r '.parameters.keyVaultResourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE")
    STORAGE_RG=$(jq -r '.parameters.storageResourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    STORAGE_SUFFIX=$(jq -r '.parameters.storageNameSuffix.value' "$PARAMETER_FILE")
    KV_NAME_PARAM=$(jq -r '.parameters.keyVaultName.value // ""' "$PARAMETER_FILE")
    
    local STORAGE_NAME="stailab${STORAGE_SUFFIX}"
    
    # T015: Check Key Vault resource group exists
    if ! az group show --name "$KV_RG" &> /dev/null; then
        log_error "Key Vault resource group not found: $KV_RG"
        log_info "Deploy Key Vault infrastructure first: ./scripts/deploy-keyvault.sh"
        PREREQ_FAILED=true
    else
        log_success "Key Vault resource group exists: $KV_RG"
    fi
    
    # T016: Check Key Vault exists in RG
    local KV_NAME
    if [[ -n "$KV_NAME_PARAM" && "$KV_NAME_PARAM" != "null" ]]; then
        KV_NAME="$KV_NAME_PARAM"
    else
        # Auto-discover Key Vault in resource group
        KV_NAME=$(az keyvault list --resource-group "$KV_RG" --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "$KV_NAME" ]]; then
        log_error "No Key Vault found in $KV_RG"
        log_info "Deploy Key Vault infrastructure first: ./scripts/deploy-keyvault.sh"
        PREREQ_FAILED=true
    else
        if ! az keyvault show --name "$KV_NAME" --resource-group "$KV_RG" &> /dev/null; then
            log_error "Key Vault not found: $KV_NAME in $KV_RG"
            PREREQ_FAILED=true
        else
            log_success "Key Vault exists: $KV_NAME"
            
            # T019: Check soft-delete and purge protection
            local SOFT_DELETE PURGE_PROTECTION
            SOFT_DELETE=$(az keyvault show --name "$KV_NAME" --resource-group "$KV_RG" --query "properties.enableSoftDelete" -o tsv 2>/dev/null || echo "false")
            PURGE_PROTECTION=$(az keyvault show --name "$KV_NAME" --resource-group "$KV_RG" --query "properties.enablePurgeProtection" -o tsv 2>/dev/null || echo "false")
            
            if [[ "$SOFT_DELETE" != "true" ]]; then
                log_error "Key Vault soft-delete not enabled (required for CMK)"
                PREREQ_FAILED=true
            else
                log_success "Key Vault soft-delete enabled"
            fi
            
            if [[ "$PURGE_PROTECTION" != "true" ]]; then
                log_error "Key Vault purge protection not enabled (required for CMK)"
                PREREQ_FAILED=true
            else
                log_success "Key Vault purge protection enabled"
            fi
        fi
    fi
    
    # T017: Check Storage resource group exists
    if ! az group show --name "$STORAGE_RG" &> /dev/null; then
        log_error "Storage resource group not found: $STORAGE_RG"
        log_info "Deploy Storage infrastructure first via 009-private-storage"
        PREREQ_FAILED=true
    else
        log_success "Storage resource group exists: $STORAGE_RG"
    fi
    
    # T018: Check Storage Account exists
    if ! az storage account show --name "$STORAGE_NAME" --resource-group "$STORAGE_RG" &> /dev/null; then
        log_error "Storage Account not found: $STORAGE_NAME in $STORAGE_RG"
        log_info "Deploy Storage infrastructure first via 009-private-storage"
        PREREQ_FAILED=true
    else
        log_success "Storage Account exists: $STORAGE_NAME"
        
        # Check if CMK already configured (edge case detection)
        local CURRENT_KEY_SOURCE
        CURRENT_KEY_SOURCE=$(az storage account show --name "$STORAGE_NAME" --resource-group "$STORAGE_RG" --query "encryption.keySource" -o tsv 2>/dev/null || echo "")
        
        if [[ "$CURRENT_KEY_SOURCE" == "Microsoft.Keyvault" ]]; then
            log_warning "Storage Account already has CMK configured - will update with new key"
        fi
    fi
    
    # T020: Display clear error messages with remediation steps
    if [[ "$PREREQ_FAILED" == "true" ]]; then
        echo ""
        log_error "Prerequisites check failed. Please resolve the issues above before continuing."
        echo ""
        echo "Deployment order:"
        echo "  1. Core infrastructure: ./scripts/deploy-core.sh"
        echo "  2. Key Vault: ./scripts/deploy-keyvault.sh"
        echo "  3. Storage Account: Deploy via 009-private-storage"
        echo "  4. CMK Encryption: $0 (this script)"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

run_whatif() {
    log_info "Running what-if analysis..."
    
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
    read -rp "Do you want to proceed with CMK deployment? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        log_warning "Deployment cancelled by user"
        exit 0
    fi
}

deploy() {
    log_info "Starting CMK deployment..."
    START_TIME=$(date +%s)
    
    az deployment sub create \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --name "$DEPLOYMENT_NAME"
    
    END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    
    log_success "Deployment completed in ${DURATION} seconds"
    
    # NFR-002: Check if deployment time exceeded 3 minutes (180 seconds)
    if [[ $DURATION -gt 180 ]]; then
        log_warning "Deployment exceeded NFR-002 target of 3 minutes (${DURATION}s > 180s)"
    else
        log_success "NFR-002 PASS: Deployment completed within 3 minutes (${DURATION}s)"
    fi
}

show_outputs() {
    log_info "Deployment outputs:"
    
    local STORAGE_RG STORAGE_SUFFIX KV_RG
    STORAGE_RG=$(jq -r '.parameters.storageResourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    STORAGE_SUFFIX=$(jq -r '.parameters.storageNameSuffix.value' "$PARAMETER_FILE")
    KV_RG=$(jq -r '.parameters.keyVaultResourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE")
    
    local STORAGE_NAME="stailab${STORAGE_SUFFIX}"
    local IDENTITY_NAME="id-${STORAGE_NAME}-cmk"
    
    echo ""
    echo "Storage Account: $STORAGE_NAME"
    echo "Resource Group: $STORAGE_RG"
    echo "Managed Identity: $IDENTITY_NAME"
    
    # Verify CMK encryption
    local KEY_SOURCE KEY_NAME KEY_VAULT_URI
    KEY_SOURCE=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "encryption.keySource" \
        --output tsv 2>/dev/null || echo "N/A")
    
    KEY_NAME=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "encryption.keyvaultproperties.keyname" \
        --output tsv 2>/dev/null || echo "N/A")
    
    KEY_VAULT_URI=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "encryption.keyvaultproperties.keyvaulturi" \
        --output tsv 2>/dev/null || echo "N/A")
    
    echo ""
    if [[ "$KEY_SOURCE" == "Microsoft.Keyvault" ]]; then
        log_success "CMK encryption enabled"
        echo "  Key Source: $KEY_SOURCE"
        echo "  Key Name: $KEY_NAME"
        echo "  Key Vault URI: $KEY_VAULT_URI"
    else
        log_error "CMK encryption not configured (keySource: $KEY_SOURCE)"
    fi
    
    # Verify user-assigned identity
    local IDENTITY_ID
    IDENTITY_ID=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "encryption.encryptionIdentity.encryptionUserAssignedIdentity" \
        --output tsv 2>/dev/null || echo "N/A")
    
    if [[ -n "$IDENTITY_ID" && "$IDENTITY_ID" != "null" && "$IDENTITY_ID" != "N/A" ]]; then
        log_success "User-assigned identity configured for CMK"
    else
        log_warning "User-assigned identity not detected"
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
echo " Enable CMK Encryption on Storage Account"
echo " Feature: 010-storage-cmk-refactor"
echo "=============================================="
echo ""

check_prerequisites

if [[ "$SKIP_WHATIF" != "true" ]]; then
    run_whatif
    confirm_deployment
fi

deploy
show_outputs

echo ""
log_success "CMK deployment complete!"
log_info "Validate: ./scripts/validate-storage.sh --deployed"
