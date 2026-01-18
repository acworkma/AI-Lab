#!/usr/bin/env bash
#
# cleanup-keyvault.sh - Clean Up Key Vault Resources
# 
# Purpose: Delete Key Vault resource group and optionally purge soft-deleted vault
#
# Usage: ./scripts/cleanup-keyvault.sh [--purge] [--auto-approve]
#
# WARNING: This will permanently delete the Key Vault and all secrets!
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/keyvault/main.parameters.json"
PURGE_VAULT=false
AUTO_APPROVE=false

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

Delete Key Vault resource group and optionally purge soft-deleted vault

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file
    --purge                     Also purge the soft-deleted vault (permanent deletion)
    -a, --auto-approve          Skip confirmation prompt (DANGEROUS)
    -h, --help                  Show this help message

WARNING:
    This script will PERMANENTLY DELETE:
    - The Key Vault resource group (rg-ai-keyvault)
    - The Key Vault and all secrets within it
    - With --purge: Permanently purge the soft-deleted vault

    Soft-deleted vaults retain their name for the retention period (90 days).
    Use --purge only if you need to redeploy with the same vault name immediately.

EXAMPLES:
    # Delete resource group (vault goes to soft-deleted state)
    $0

    # Delete and purge (allows immediate redeployment with same name)
    $0 --purge

    # Automated cleanup (CI/CD)
    $0 --purge --auto-approve

EOF
    exit 1
}

confirm_deletion() {
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${RED}WARNING: This will permanently delete Key Vault resources!${NC}"
    echo ""
    
    local RG_NAME
    RG_NAME=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE")
    
    echo "Resources to be deleted:"
    echo "  - Resource Group: $RG_NAME"
    echo "  - All Key Vaults in the resource group"
    echo "  - All secrets, keys, and certificates"
    
    if [[ "$PURGE_VAULT" == "true" ]]; then
        echo ""
        echo -e "${RED}  - PURGE: Soft-deleted vault will be permanently destroyed${NC}"
    fi
    
    echo ""
    read -p "Type 'DELETE' to confirm: " -r
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
}

get_vault_name() {
    local RG_NAME
    RG_NAME=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE")
    
    # Get vault name from resource group
    az keyvault list --resource-group "$RG_NAME" --query "[0].name" -o tsv 2>/dev/null || true
}

delete_resource_group() {
    local RG_NAME
    RG_NAME=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE")
    
    log_info "Deleting resource group: $RG_NAME"
    
    if ! az group show --name "$RG_NAME" &> /dev/null; then
        log_warning "Resource group does not exist: $RG_NAME"
        return 0
    fi
    
    if ! az group delete --name "$RG_NAME" --yes --no-wait; then
        log_error "Failed to initiate resource group deletion"
        return 1
    fi
    
    log_info "Resource group deletion initiated (running in background)"
    
    # Wait for deletion
    log_info "Waiting for deletion to complete..."
    local TIMEOUT=300
    local ELAPSED=0
    
    while az group show --name "$RG_NAME" &> /dev/null; do
        if [[ $ELAPSED -ge $TIMEOUT ]]; then
            log_warning "Timeout waiting for deletion. Check Azure Portal for status."
            return 0
        fi
        sleep 10
        ELAPSED=$((ELAPSED + 10))
        echo -n "."
    done
    
    echo ""
    log_success "Resource group deleted: $RG_NAME"
}

purge_soft_deleted_vault() {
    local VAULT_NAME="$1"
    
    if [[ -z "$VAULT_NAME" ]]; then
        log_warning "No vault name provided for purge"
        return 0
    fi
    
    log_info "Checking for soft-deleted vault: $VAULT_NAME"
    
    # Check if vault is in soft-deleted state
    local DELETED_VAULT
    DELETED_VAULT=$(az keyvault list-deleted --query "[?name=='$VAULT_NAME'].name" -o tsv 2>/dev/null || true)
    
    if [[ -z "$DELETED_VAULT" ]]; then
        log_info "No soft-deleted vault found with name: $VAULT_NAME"
        return 0
    fi
    
    log_info "Purging soft-deleted vault: $VAULT_NAME"
    
    if ! az keyvault purge --name "$VAULT_NAME"; then
        log_error "Failed to purge vault: $VAULT_NAME"
        log_info "The vault may have purge protection enabled, preventing permanent deletion"
        return 1
    fi
    
    log_success "Vault purged: $VAULT_NAME"
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
        --purge)
            PURGE_VAULT=true
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

# ============================================================================
# MAIN
# ============================================================================

echo ""
echo "============================================"
echo "Key Vault Cleanup"
echo "============================================"
echo ""

# Check Azure CLI login
if ! az account show &> /dev/null; then
    log_error "Not logged into Azure. Run 'az login' first."
    exit 1
fi

# Get vault name before deletion (for purge)
VAULT_NAME=$(get_vault_name)
if [[ -n "$VAULT_NAME" ]]; then
    log_info "Found Key Vault: $VAULT_NAME"
fi

# Confirm deletion
confirm_deletion

# Delete resource group
delete_resource_group

# Purge vault if requested
if [[ "$PURGE_VAULT" == "true" ]] && [[ -n "$VAULT_NAME" ]]; then
    echo ""
    purge_soft_deleted_vault "$VAULT_NAME"
fi

echo ""
echo "============================================"
log_success "Cleanup complete!"
echo ""
if [[ "$PURGE_VAULT" != "true" ]] && [[ -n "$VAULT_NAME" ]]; then
    log_info "Note: Vault '$VAULT_NAME' is in soft-deleted state for 90 days"
    log_info "Run with --purge to permanently delete, or use a different vault name"
fi
echo "============================================"
