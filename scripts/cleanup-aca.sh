#!/usr/bin/env bash
#
# cleanup-aca.sh - Clean Up ACA Environment Resources
# 
# Purpose: Delete the ACA resource group and all contained resources
#          Includes safety confirmation before deletion
#
# Usage: ./scripts/cleanup-aca.sh [--parameter-file <path>] [--force]
#
# Warning: This is a destructive operation. It permanently deletes the resource group.
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/aca/main.parameters.json"
FORCE=false

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

Clean up ACA environment resources (destructive operation)

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/aca/main.parameters.json)
    -f, --force                 Skip confirmation prompt (use with extreme caution)
    -h, --help                  Show this help message

WARNING:
    This script permanently deletes the resource group and ALL resources within it.
    This action cannot be undone.

RESOURCES DELETED:
    - Container Apps Environment
    - Private Endpoint
    - Log Analytics Workspace (if created by this feature)
    - Managed Identity
    - Resource Group

Note: Core infrastructure resources (VNet, DNS zones) are NOT affected.

EXAMPLES:
    # Interactive cleanup with confirmation
    $0

    # Automated cleanup (CI/CD teardown)
    $0 --force

EOF
    exit 1
}

confirm_deletion() {
    local RG_NAME="$1"
    
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete resource group: $RG_NAME"
    log_warning "All resources in the group will be destroyed."
    echo ""
    
    # List resources in the group
    log_info "Resources in $RG_NAME:"
    az resource list --resource-group "$RG_NAME" --query "[].{Name:name, Type:type}" -o table 2>/dev/null || true
    echo ""
    
    read -p "Type 'DELETE' to confirm deletion: " CONFIRM
    
    if [[ "$CONFIRM" != "DELETE" ]]; then
        log_info "Deletion cancelled."
        exit 0
    fi
}

delete_resource_group() {
    local RG_NAME="$1"
    
    log_info "Checking if resource group exists: $RG_NAME"
    
    if ! az group show --name "$RG_NAME" &> /dev/null; then
        log_info "Resource group does not exist: $RG_NAME. Nothing to clean up."
        return 0
    fi
    
    log_info "Deleting resource group: $RG_NAME (this may take several minutes)..."
    
    if ! az group delete --name "$RG_NAME" --yes --no-wait; then
        log_error "Failed to initiate resource group deletion"
        return 1
    fi
    
    # Wait for deletion to complete
    log_info "Waiting for deletion to complete..."
    local WAIT_COUNT=0
    local MAX_WAIT=60  # 5 minutes (60 x 5s)
    
    while az group show --name "$RG_NAME" &> /dev/null; do
        WAIT_COUNT=$((WAIT_COUNT + 1))
        if [[ $WAIT_COUNT -ge $MAX_WAIT ]]; then
            log_warning "Deletion still in progress after 5 minutes. Check Azure portal."
            return 0
        fi
        sleep 5
    done
    
    log_success "Resource group deleted: $RG_NAME"
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
        -f|--force)
            FORCE=true
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
echo "ACA Environment Cleanup"
echo "============================================"
echo ""

# Check Azure login
if ! az account show &> /dev/null; then
    log_error "Not logged into Azure. Run 'az login' first."
    exit 1
fi

# Get resource group name from parameters
RG_NAME=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-aca"' "$PARAMETER_FILE")

echo "Resource Group:  $RG_NAME"
echo "Parameter File:  $PARAMETER_FILE"
echo ""

# Confirm deletion
confirm_deletion "$RG_NAME"

# Delete resource group
delete_resource_group "$RG_NAME"

echo ""
echo "============================================"
log_success "ACA cleanup complete!"
echo ""
echo "Note: Core infrastructure (VNet, DNS zones) remains intact."
echo "To redeploy: ./scripts/deploy-aca.sh"
echo "============================================"
