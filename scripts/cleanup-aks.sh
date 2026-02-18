#!/usr/bin/env bash
#
# cleanup-aks.sh - Cleanup AKS Infrastructure
#
# Purpose: Remove AKS resource group and all contained resources
#
# Usage: ./scripts/cleanup-aks.sh [--force]
#
# WARNING: This will delete ALL resources in rg-ai-aks including:
#   - AKS cluster and all node pools
#   - All deployments/pods/services in the cluster
#   - Role assignments
#

set -euo pipefail

RESOURCE_GROUP="rg-ai-aks"
FORCE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--force] [--resource-group <name>]"
            echo ""
            echo "Options:"
            echo "  -f, --force           Skip confirmation prompt"
            echo "  -g, --resource-group  Resource group to delete (default: rg-ai-aks)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo "=========================================="
echo "  AKS Cleanup"
echo "=========================================="
echo ""

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    log_info "Resource group '$RESOURCE_GROUP' does not exist. Nothing to clean up."
    exit 0
fi

# List resources
log_info "Resources in $RESOURCE_GROUP:"
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" -o table

# Get cluster info if it exists
CLUSTER_NAME=$(az aks list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || true)
if [ -n "$CLUSTER_NAME" ]; then
    # Try to get node resource group
    NODE_RG=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query "nodeResourceGroup" -o tsv 2>/dev/null || true)
    if [ -n "$NODE_RG" ]; then
        log_warning "Node resource group will also be deleted: $NODE_RG"
    fi
fi

echo ""

# Confirmation
if [ "$FORCE" != true ]; then
    log_warning "This will permanently delete resource group: $RESOURCE_GROUP"
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    echo ""
    
    if [ "$REPLY" != "yes" ]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
fi

# Remove kubectl context if exists
if command -v kubectl &> /dev/null && [ -n "$CLUSTER_NAME" ]; then
    log_info "Removing kubectl context..."
    kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
    kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true
fi

# Delete resource group
log_info "Deleting resource group: $RESOURCE_GROUP"
log_info "This may take several minutes..."

if az group delete --name "$RESOURCE_GROUP" --yes --no-wait; then
    log_success "Resource group deletion initiated"
    log_info "Deletion is running in background. Check status with:"
    log_info "  az group show --name $RESOURCE_GROUP --query properties.provisioningState -o tsv"
else
    log_error "Failed to initiate resource group deletion"
    exit 1
fi

echo ""
log_success "AKS cleanup initiated!"
