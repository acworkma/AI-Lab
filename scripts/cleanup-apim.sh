#!/usr/bin/env bash
#
# cleanup-apim.sh - Clean up Azure API Management Standard v2 deployment
# 
# Purpose: Remove APIM resource group and optionally clean up subnet/NSG from shared services VNet
#
# Usage: ./scripts/cleanup-apim.sh [--include-subnet] [--auto-approve]
#

set -euo pipefail

# Default values
RESOURCE_GROUP="rg-ai-apim"
CORE_RG="rg-ai-core"
SHARED_VNET="vnet-ai-shared-services"
APIM_SUBNET="ApimIntegrationSubnet"
APIM_NSG="nsg-apim-integration"
INCLUDE_SUBNET=false
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

Clean up Azure API Management Standard v2 deployment

OPTIONS:
    --include-subnet    Also remove APIM subnet and NSG from shared services VNet
    -a, --auto-approve  Skip confirmation prompt (use with caution)
    -h, --help          Show this help message

EXAMPLES:
    # Remove APIM resource group only (preserves subnet)
    $0

    # Full cleanup including subnet and NSG
    $0 --include-subnet

    # Automated cleanup (CI/CD)
    $0 --auto-approve

NOTES:
    - This will permanently delete all resources in rg-ai-apim
    - Use --include-subnet to also remove the APIM subnet from shared services VNet
    - The subnet cleanup may fail if other resources are still using it

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
    
    local account=$(az account show --query name -o tsv)
    log_info "Using subscription: $account"
}

discover_resources() {
    log_info "Discovering resources to clean up..."
    echo ""

    # Check APIM resource group
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Resource group: $RESOURCE_GROUP (will be deleted)"
        
        # List resources in the group
        local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, type:type}" --output table 2>/dev/null || echo "")
        if [ -n "$resources" ]; then
            echo "$resources"
        fi
    else
        log_warning "Resource group not found: $RESOURCE_GROUP"
    fi

    echo ""

    # Check subnet and NSG if --include-subnet
    if [ "$INCLUDE_SUBNET" = true ]; then
        # Check subnet
        if az network vnet subnet show \
            --name "$APIM_SUBNET" \
            --vnet-name "$SHARED_VNET" \
            --resource-group "$CORE_RG" &> /dev/null; then
            log_info "Subnet: $APIM_SUBNET in $SHARED_VNET (will be deleted)"
        else
            log_warning "Subnet not found: $APIM_SUBNET"
        fi

        # Check NSG
        if az network nsg show --name "$APIM_NSG" --resource-group "$CORE_RG" &> /dev/null; then
            log_info "NSG: $APIM_NSG (will be deleted)"
        else
            log_warning "NSG not found: $APIM_NSG"
        fi
    fi

    echo ""
}

confirm_cleanup() {
    if [ "$AUTO_APPROVE" = true ]; then
        log_info "Auto-approve enabled, proceeding with cleanup..."
        return 0
    fi

    echo ""
    log_warning "⚠️  This action is IRREVERSIBLE!"
    log_warning "All resources listed above will be permanently deleted."
    echo ""
    read -p "Type 'DELETE' to confirm: " response
    if [ "$response" = "DELETE" ]; then
        return 0
    else
        log_info "Cleanup cancelled."
        exit 0
    fi
}

cleanup_subnet() {
    if [ "$INCLUDE_SUBNET" = false ]; then
        return 0
    fi

    log_info "Cleaning up APIM subnet and NSG..."

    # Delete subnet first (must be done before NSG)
    if az network vnet subnet show \
        --name "$APIM_SUBNET" \
        --vnet-name "$SHARED_VNET" \
        --resource-group "$CORE_RG" &> /dev/null; then
        
        log_info "Deleting subnet: $APIM_SUBNET..."
        if az network vnet subnet delete \
            --name "$APIM_SUBNET" \
            --vnet-name "$SHARED_VNET" \
            --resource-group "$CORE_RG"; then
            log_success "Subnet deleted: $APIM_SUBNET"
        else
            log_error "Failed to delete subnet: $APIM_SUBNET"
            log_warning "The subnet may still be in use by APIM. Try again after resource group is deleted."
        fi
    else
        log_info "Subnet already deleted or doesn't exist"
    fi

    # Delete NSG
    if az network nsg show --name "$APIM_NSG" --resource-group "$CORE_RG" &> /dev/null; then
        log_info "Deleting NSG: $APIM_NSG..."
        if az network nsg delete --name "$APIM_NSG" --resource-group "$CORE_RG"; then
            log_success "NSG deleted: $APIM_NSG"
        else
            log_error "Failed to delete NSG: $APIM_NSG"
        fi
    else
        log_info "NSG already deleted or doesn't exist"
    fi
}

cleanup_resource_group() {
    log_info "Cleaning up APIM resource group..."

    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting resource group: $RESOURCE_GROUP..."
        log_warning "This may take several minutes..."
        
        if az group delete --name "$RESOURCE_GROUP" --yes --no-wait; then
            log_success "Resource group deletion initiated: $RESOURCE_GROUP"
            log_info "Deletion is running in background. Check Azure Portal for status."
        else
            log_error "Failed to initiate resource group deletion"
            exit 1
        fi
    else
        log_info "Resource group already deleted or doesn't exist"
    fi
}

wait_for_deletion() {
    log_info "Waiting for resource group deletion to complete..."
    
    local max_wait=600  # 10 minutes
    local elapsed=0
    local interval=30

    while [ $elapsed -lt $max_wait ]; do
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_success "Resource group deleted: $RESOURCE_GROUP"
            return 0
        fi
        
        log_info "Still deleting... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log_warning "Timeout waiting for deletion. Check Azure Portal for status."
}

# ============================================================================
# MAIN
# ============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --include-subnet)
            INCLUDE_SUBNET=true
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
echo "  APIM Cleanup"
echo "=============================================="
echo ""

check_prerequisites
discover_resources
confirm_cleanup

# Delete resource group first (this deletes APIM which frees the subnet)
cleanup_resource_group

# If including subnet cleanup, wait for RG deletion then clean subnet
if [ "$INCLUDE_SUBNET" = true ]; then
    wait_for_deletion
    cleanup_subnet
fi

echo ""
log_success "Cleanup completed!"
echo ""
log_info "To redeploy, run: ./scripts/deploy-apim.sh"
