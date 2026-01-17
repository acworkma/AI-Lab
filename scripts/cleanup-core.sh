#!/usr/bin/env bash
#
# cleanup-core.sh - Safely delete Core Azure vWAN Infrastructure
# 
# Purpose: Clean removal of all core infrastructure resources with safety checks
#   - Warns if spoke connections exist
#   - Prompts for confirmation
#   - Deletes resource group (cascades to all resources)
#
# Usage: ./scripts/cleanup-core.sh [--auto-approve]
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
RESOURCE_GROUP="rg-ai-core"
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

Safely delete Core Azure vWAN Infrastructure

OPTIONS:
    -a, --auto-approve      Skip confirmation prompts (use with caution)
    -h, --help              Show this help message

EXAMPLES:
    # Standard cleanup with confirmation
    $0

    # Automated cleanup (CI/CD)
    $0 --auto-approve

WARNING:
    This will permanently delete all resources in rg-ai-core:
    - Virtual WAN hub and VPN Gateway
    - DNS Resolver and Private DNS Zones
    - Shared Services VNet
    - All spoke connections (if any)

EOF
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found"
        exit 1
    fi

    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run: az login"
        exit 1
    fi

    log_success "Prerequisites validated"
    echo ""
}

check_resource_group_exists() {
    log_info "Checking if resource group exists..."

    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' not found - nothing to delete"
        exit 0
    fi

    log_success "Resource group found: $RESOURCE_GROUP"
    echo ""
}

check_spoke_connections() {
    log_info "Checking for spoke connections..."

    # Find Virtual Hub
    local vhub_name=$(az network vhub list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv 2>/dev/null || echo "")
    
    if [ -z "$vhub_name" ]; then
        log_info "No Virtual Hub found (resource group may be partially deployed)"
        echo ""
        return 0
    fi

    # Check for spoke connections
    local connections=$(az network vhub connection list \
        --resource-group "$RESOURCE_GROUP" \
        --vhub-name "$vhub_name" \
        --query '[].name' -o tsv 2>/dev/null || echo "")

    if [ -n "$connections" ]; then
        log_warning "Spoke connections detected:"
        echo "$connections" | while read conn; do
            echo "  - $conn"
        done
        echo ""
        log_warning "These connections will be deleted automatically with the hub"
        log_warning "Spoke VNets will NOT be deleted (they are in separate resource groups)"
        echo ""
    else
        log_success "No spoke connections found"
        echo ""
    fi
}

list_resources() {
    log_info "Resources to be deleted in $RESOURCE_GROUP:"
    echo ""

    az resource list --resource-group "$RESOURCE_GROUP" \
        --query '[].{Name:name, Type:type, Location:location}' -o table

    echo ""
}

confirm_deletion() {
    if [ "$AUTO_APPROVE" = true ]; then
        log_warning "Auto-approve enabled, skipping confirmation"
        return 0
    fi

    echo ""
    log_warning "⚠️  THIS IS A DESTRUCTIVE OPERATION ⚠️"
    echo ""
    echo "This will DELETE all resources in resource group: $RESOURCE_GROUP"
    echo ""
    echo "Resources to be deleted:"
    echo "  - Virtual WAN (vwan-ai-hub)"
    echo "  - Virtual Hub (hub-ai-eastus2)"
    echo "  - VPN Gateway (vpngw-ai-hub)"
    echo "  - Shared Services VNet (vnet-ai-shared)"
    echo "  - DNS Resolver (dnsr-ai-shared)"
    echo "  - Private DNS Zones"
    echo "  - All spoke connections (spoke VNets remain intact)"
    echo ""
    
    read -p "Type 'DELETE' to confirm deletion: " -r
    echo
    if [[ ! $REPLY == "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
}

delete_spoke_connections() {
    log_info "Deleting spoke connections..."

    # Find Virtual Hub
    local vhub_name=$(az network vhub list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv 2>/dev/null || echo "")
    
    if [ -z "$vhub_name" ]; then
        log_info "No Virtual Hub found, skipping spoke connection cleanup"
        return 0
    fi

    # Delete all connections
    local connections=$(az network vhub connection list \
        --resource-group "$RESOURCE_GROUP" \
        --vhub-name "$vhub_name" \
        --query '[].name' -o tsv 2>/dev/null || echo "")

    if [ -n "$connections" ]; then
        echo "$connections" | while read conn; do
            log_info "  Deleting connection: $conn"
            az network vhub connection delete \
                --resource-group "$RESOURCE_GROUP" \
                --vhub-name "$vhub_name" \
                --name "$conn" \
                --yes &>/dev/null || log_warning "Failed to delete connection: $conn"
        done
        log_success "Spoke connections deleted"
    else
        log_info "No spoke connections to delete"
    fi

    echo ""
}

delete_resource_group() {
    log_info "Deleting resource group: $RESOURCE_GROUP"
    log_warning "This may take 10-15 minutes (VPN Gateway deletion is slow)..."
    echo ""

    if ! az group delete --name "$RESOURCE_GROUP" --yes --no-wait; then
        log_error "Failed to initiate resource group deletion"
        exit 1
    fi

    log_success "Resource group deletion initiated (running in background)"
    log_info "Monitor status with: az group show --name $RESOURCE_GROUP"
    echo ""
}

    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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

# Main execution
log_info "Core Azure vWAN Infrastructure Cleanup"
log_info "========================================"
echo ""

check_prerequisites
check_resource_group_exists
check_spoke_connections
list_resources
confirm_deletion
delete_spoke_connections
delete_resource_group

echo ""
log_success "Cleanup initiated successfully!"
echo ""
log_info "Deletion Status:"
echo "  - Resource group deletion: In progress (background)"
echo "  - Estimated time: 10-15 minutes"
echo ""
log_info "Verify deletion:"
echo "  az group show --name $RESOURCE_GROUP"
echo "  (Should return: ResourceGroupNotFound)"
echo ""
log_info "To redeploy infrastructure: ./scripts/deploy-core.sh"
