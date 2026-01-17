#!/bin/bash
# ============================================================================
# Script: cleanup-storage-infra.sh
# Purpose: Remove Private Storage Account infrastructure
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
FORCE=false
DELETE_DNS_RECORDS=true

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

Remove Private Storage Account infrastructure.

Options:
    -p, --parameters FILE    Parameter file path (default: main.parameters.json)
    -f, --force              Skip confirmation prompts
    --keep-dns               Keep DNS records in private DNS zone
    -h, --help               Show this help message

What gets deleted:
    - Storage account and all data
    - Private endpoint
    - DNS zone group
    - Private DNS records
    - Resource group (rg-ai-storage)

WARNING: This operation is destructive and cannot be undone!

EOF
}

get_storage_name() {
    local suffix=$(jq -r '.parameters.storageNameSuffix.value' "$PARAMETER_FILE")
    echo "stailab${suffix}"
}

get_resource_group() {
    echo "rg-ai-storage"
}

get_core_resource_group() {
    jq -r '.parameters.coreResourceGroupName.value' "$PARAMETER_FILE"
}

list_resources() {
    log_info "Resources to be deleted:"
    echo ""
    
    local rg_name=$(get_resource_group)
    local storage_name=$(get_storage_name)
    local core_rg=$(get_core_resource_group)
    
    echo "Resource Group: $rg_name"
    
    # Check if RG exists
    if ! az group show --name "$rg_name" &> /dev/null; then
        log_warn "Resource group does not exist: $rg_name"
        return 1
    fi
    
    # List resources in the group
    echo ""
    echo "Resources in $rg_name:"
    az resource list --resource-group "$rg_name" --query "[].{Name:name, Type:type}" -o table 2>/dev/null || true
    
    # Check DNS records
    echo ""
    echo "DNS records to remove (in $core_rg):"
    az network private-dns record-set a list \
        --resource-group "$core_rg" \
        --zone-name "privatelink.blob.core.windows.net" \
        --query "[?name=='$storage_name'].{Name:name, IPs:aRecords[0].ipv4Address}" \
        -o table 2>/dev/null || echo "  (none found)"
    
    return 0
}

confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${RED}WARNING: This will permanently delete all listed resources!${NC}"
    echo ""
    read -p "Type 'DELETE' to confirm: " -r
    echo ""
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log_warn "Deletion cancelled (input did not match 'DELETE')"
        exit 2
    fi
}

delete_dns_records() {
    if [[ "$DELETE_DNS_RECORDS" != "true" ]]; then
        log_info "Skipping DNS record deletion (--keep-dns specified)"
        return 0
    fi
    
    log_info "Deleting DNS records..."
    
    local storage_name=$(get_storage_name)
    local core_rg=$(get_core_resource_group)
    
    # Delete A record if exists
    if az network private-dns record-set a show \
        --resource-group "$core_rg" \
        --zone-name "privatelink.blob.core.windows.net" \
        --name "$storage_name" &> /dev/null; then
        
        az network private-dns record-set a delete \
            --resource-group "$core_rg" \
            --zone-name "privatelink.blob.core.windows.net" \
            --name "$storage_name" \
            --yes
        
        log_success "DNS A record deleted: $storage_name"
    else
        log_info "DNS A record not found (may have been auto-deleted)"
    fi
}

delete_private_endpoint() {
    log_info "Deleting private endpoint..."
    
    local storage_name=$(get_storage_name)
    local rg_name=$(get_resource_group)
    local pe_name="pe-${storage_name}"
    
    if az network private-endpoint show --name "$pe_name" --resource-group "$rg_name" &> /dev/null; then
        # First delete DNS zone group (if not already deleted)
        log_info "Deleting DNS zone group..."
        az network private-endpoint dns-zone-group delete \
            --endpoint-name "$pe_name" \
            --resource-group "$rg_name" \
            --name "default" \
            --yes 2>/dev/null || true
        
        # Delete the private endpoint
        az network private-endpoint delete \
            --name "$pe_name" \
            --resource-group "$rg_name"
        
        log_success "Private endpoint deleted: $pe_name"
    else
        log_info "Private endpoint not found: $pe_name"
    fi
}

delete_storage_account() {
    log_info "Deleting storage account..."
    
    local storage_name=$(get_storage_name)
    local rg_name=$(get_resource_group)
    
    if az storage account show --name "$storage_name" --resource-group "$rg_name" &> /dev/null; then
        az storage account delete \
            --name "$storage_name" \
            --resource-group "$rg_name" \
            --yes
        
        log_success "Storage account deleted: $storage_name"
    else
        log_info "Storage account not found: $storage_name"
    fi
}

delete_resource_group() {
    log_info "Deleting resource group..."
    
    local rg_name=$(get_resource_group)
    
    if az group show --name "$rg_name" &> /dev/null; then
        az group delete \
            --name "$rg_name" \
            --yes \
            --no-wait
        
        log_success "Resource group deletion initiated: $rg_name"
        log_info "Resource group deletion runs in background and may take a few minutes"
    else
        log_info "Resource group not found: $rg_name"
    fi
}

wait_for_deletion() {
    log_info "Waiting for resource group deletion..."
    
    local rg_name=$(get_resource_group)
    local max_wait=300  # 5 minutes
    local wait_interval=10
    local elapsed=0
    
    while az group show --name "$rg_name" &> /dev/null; do
        if [[ $elapsed -ge $max_wait ]]; then
            log_warn "Timeout waiting for deletion. RG may still be deleting in background."
            return 1
        fi
        
        echo -n "."
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    echo ""
    log_success "Resource group deleted: $rg_name"
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
        -f|--force)
            FORCE=true
            shift
            ;;
        --keep-dns)
            DELETE_DNS_RECORDS=false
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
echo "  Storage Infrastructure Cleanup"
echo "=========================================="
echo ""

# Check parameter file exists
if [[ ! -f "$PARAMETER_FILE" ]]; then
    log_error "Parameter file not found: $PARAMETER_FILE"
    exit 1
fi

# List what will be deleted
if ! list_resources; then
    log_info "Nothing to delete"
    exit 0
fi

# Confirm
confirm_deletion

# Perform deletion in order
echo ""
delete_dns_records
delete_private_endpoint
delete_storage_account
delete_resource_group

# Optionally wait
if [[ "$FORCE" != "true" ]]; then
    read -p "Wait for deletion to complete? [y/N]: " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        wait_for_deletion
    fi
fi

echo ""
log_success "Cleanup complete!"
echo ""
echo "Note: Some resources may still be deleting in background."
echo "Run 'az group show -n rg-ai-storage' to check status."
echo ""
