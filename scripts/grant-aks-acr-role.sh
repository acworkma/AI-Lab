#!/usr/bin/env bash
#
# grant-aks-acr-role.sh - Grant AcrPull Role to AKS Kubelet Identity
#
# Purpose: Assign AcrPull role to AKS kubelet identity for private ACR access
#
# Usage: ./scripts/grant-aks-acr-role.sh [--cluster <name>] [--acr <name>]
#
# Prerequisites:
# - AKS cluster deployed
# - ACR deployed
#

set -euo pipefail

# Default values
AKS_RESOURCE_GROUP="rg-ai-aks"
AKS_CLUSTER_NAME="aks-ai-lab"
ACR_RESOURCE_GROUP="rg-ai-acr"
ACR_NAME=""

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

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Grant AcrPull role to AKS kubelet identity

OPTIONS:
    -c, --cluster      AKS cluster name (default: aks-ai-lab)
    -g, --aks-rg       AKS resource group (default: rg-ai-aks)
    -a, --acr          ACR name (auto-detected from rg-ai-acr if not specified)
    --acr-rg           ACR resource group (default: rg-ai-acr)
    -h, --help         Show this help message

EXAMPLES:
    # Auto-detect ACR from rg-ai-acr
    $0

    # Specify ACR name
    $0 --acr myacr

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster)
            AKS_CLUSTER_NAME="$2"
            shift 2
            ;;
        -g|--aks-rg)
            AKS_RESOURCE_GROUP="$2"
            shift 2
            ;;
        -a|--acr)
            ACR_NAME="$2"
            shift 2
            ;;
        --acr-rg)
            ACR_RESOURCE_GROUP="$2"
            shift 2
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
echo "=========================================="
echo "  AKS-ACR Role Assignment"
echo "=========================================="
echo ""

# Check AKS cluster exists
log_info "Checking AKS cluster: $AKS_CLUSTER_NAME"
if ! az aks show --resource-group "$AKS_RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" &> /dev/null; then
    log_error "AKS cluster not found: $AKS_CLUSTER_NAME in $AKS_RESOURCE_GROUP"
    exit 1
fi
log_success "AKS cluster found"

# Get kubelet identity
log_info "Getting kubelet identity..."
KUBELET_ID=$(az aks show \
    --resource-group "$AKS_RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --query "identityProfile.kubeletidentity.objectId" \
    -o tsv)

if [ -z "$KUBELET_ID" ]; then
    log_error "Could not get kubelet identity"
    exit 1
fi
log_success "Kubelet identity: $KUBELET_ID"

# Auto-detect ACR if not specified
if [ -z "$ACR_NAME" ]; then
    log_info "Auto-detecting ACR from $ACR_RESOURCE_GROUP..."
    ACR_NAME=$(az acr list --resource-group "$ACR_RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)
    
    if [ -z "$ACR_NAME" ]; then
        log_error "No ACR found in $ACR_RESOURCE_GROUP"
        log_info "Specify ACR name with --acr option"
        exit 1
    fi
fi

# Check ACR exists
log_info "Checking ACR: $ACR_NAME"
if ! az acr show --name "$ACR_NAME" --resource-group "$ACR_RESOURCE_GROUP" &> /dev/null; then
    log_error "ACR not found: $ACR_NAME in $ACR_RESOURCE_GROUP"
    exit 1
fi
log_success "ACR found: $ACR_NAME"

# Get ACR resource ID
ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$ACR_RESOURCE_GROUP" --query id -o tsv)

# Check existing role assignment
log_info "Checking existing role assignments..."
EXISTING=$(az role assignment list \
    --assignee "$KUBELET_ID" \
    --scope "$ACR_ID" \
    --query "[?roleDefinitionName=='AcrPull'].id" \
    -o tsv 2>/dev/null)

if [ -n "$EXISTING" ]; then
    log_success "AcrPull role already assigned"
    exit 0
fi

# Assign role
log_info "Assigning AcrPull role..."
if az role assignment create \
    --assignee-object-id "$KUBELET_ID" \
    --assignee-principal-type ServicePrincipal \
    --role AcrPull \
    --scope "$ACR_ID" \
    --output none; then
    log_success "AcrPull role assigned successfully"
else
    log_error "Failed to assign AcrPull role"
    exit 1
fi

# Verify
log_info "Verifying role assignment..."
sleep 5  # Wait for propagation

VERIFY=$(az role assignment list \
    --assignee "$KUBELET_ID" \
    --scope "$ACR_ID" \
    --query "[?roleDefinitionName=='AcrPull'].id" \
    -o tsv 2>/dev/null)

if [ -n "$VERIFY" ]; then
    log_success "Role assignment verified"
else
    log_warning "Role assignment created but verification pending (may take 1-2 minutes to propagate)"
fi

echo ""
log_success "AKS-ACR role assignment complete!"
log_info "AKS can now pull images from: $ACR_NAME.azurecr.io"
