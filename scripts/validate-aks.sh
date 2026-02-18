#!/usr/bin/env bash
#
# validate-aks.sh - Validate Private AKS Deployment
#
# Purpose: Validate AKS cluster configuration, connectivity, and functionality
#
# Usage: ./scripts/validate-aks.sh [--full]
#
# Prerequisites:
# - AKS cluster deployed (run scripts/deploy-aks.sh first)
# - VPN connection established
# - kubectl installed
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
RESOURCE_GROUP="rg-ai-aks"
CLUSTER_NAME="aks-ai-lab"
FULL_VALIDATION=false

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
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate Private AKS cluster deployment

OPTIONS:
    -f, --full         Run full validation including kubectl tests
    -c, --cluster      Cluster name (default: aks-ai-lab)
    -g, --resource-group  Resource group (default: rg-ai-aks)
    -h, --help         Show this help message

EXAMPLES:
    # Basic validation (Azure resource checks only)
    $0

    # Full validation including kubectl connectivity
    $0 --full

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
        log_error "Not logged in to Azure"
        exit 1
    fi
    log_success "Azure CLI authenticated"
}

check_resource_group() {
    log_info "Checking resource group: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group not found: $RESOURCE_GROUP"
        exit 1
    fi
    log_success "Resource group exists"
}

check_cluster_exists() {
    log_info "Checking AKS cluster: $CLUSTER_NAME"
    
    if ! az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" &> /dev/null; then
        log_error "AKS cluster not found: $CLUSTER_NAME"
        exit 1
    fi
    log_success "AKS cluster exists"
}

check_private_cluster() {
    log_info "Validating private cluster configuration..."
    
    local is_private=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "apiServerAccessProfile.enablePrivateCluster" \
        -o tsv)
    
    if [ "$is_private" != "true" ]; then
        log_error "Cluster is not private (enablePrivateCluster: $is_private)"
        exit 1
    fi
    log_success "Private cluster enabled"
    
    # Check no public FQDN
    local public_fqdn=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "apiServerAccessProfile.enablePrivateClusterPublicFQDN" \
        -o tsv)
    
    if [ "$public_fqdn" = "true" ]; then
        log_warning "Public FQDN is enabled (less secure)"
    else
        log_success "Public FQDN disabled"
    fi
}

check_rbac_enabled() {
    log_info "Validating RBAC configuration..."
    
    local enable_rbac=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "enableRbac" \
        -o tsv)
    
    if [ "$enable_rbac" != "true" ]; then
        log_error "RBAC not enabled"
        exit 1
    fi
    log_success "RBAC enabled"
    
    local disable_local=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "disableLocalAccounts" \
        -o tsv)
    
    if [ "$disable_local" != "true" ]; then
        log_warning "Local accounts are enabled (less secure)"
    else
        log_success "Local accounts disabled (Azure AD only)"
    fi
    
    local azure_rbac=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "aadProfile.enableAzureRbac" \
        -o tsv)
    
    if [ "$azure_rbac" = "true" ]; then
        log_success "Azure RBAC for Kubernetes enabled"
    else
        log_warning "Azure RBAC for Kubernetes not enabled"
    fi
}

check_node_pools() {
    log_info "Validating node pool configuration..."
    
    local node_count=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "agentPoolProfiles[0].count" \
        -o tsv)
    
    log_success "Node count: $node_count"
    
    local vm_size=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "agentPoolProfiles[0].vmSize" \
        -o tsv)
    
    log_success "VM size: $vm_size"
    
    local zones=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "agentPoolProfiles[0].availabilityZones" \
        -o tsv)
    
    if [ -n "$zones" ]; then
        log_success "Availability zones: $zones"
    else
        log_warning "No availability zones configured"
    fi
    
    local os_sku=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "agentPoolProfiles[0].osSku" \
        -o tsv)
    
    if [ "$os_sku" = "AzureLinux" ]; then
        log_success "Node OS: Azure Linux (CBL-Mariner)"
    else
        log_info "Node OS: $os_sku"
    fi
}

check_network_profile() {
    log_info "Validating network configuration..."
    
    local network_plugin=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "networkProfile.networkPlugin" \
        -o tsv)
    
    log_success "Network plugin: $network_plugin"
    
    local network_mode=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "networkProfile.networkPluginMode" \
        -o tsv)
    
    if [ "$network_mode" = "overlay" ]; then
        log_success "Network mode: Azure CNI Overlay"
    else
        log_info "Network mode: $network_mode"
    fi
    
    local pod_cidr=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "networkProfile.podCidr" \
        -o tsv)
    
    log_success "Pod CIDR: $pod_cidr"
}

check_vpn_connection() {
    log_info "Checking VPN connection..."
    
    # Check for VPN route (typically 172.16.0.0/12 or similar)
    if ip route 2>/dev/null | grep -qE "172\\.16\\.|10\\.0\\." ; then
        log_success "VPN routes detected"
    else
        log_warning "No VPN routes detected - kubectl commands may fail"
        return 1
    fi
    return 0
}

check_kubectl_connectivity() {
    log_info "Testing kubectl connectivity..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        return 1
    fi
    
    # Get credentials
    log_info "Getting AKS credentials..."
    if ! az aks get-credentials \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --overwrite-existing 2>/dev/null; then
        log_error "Failed to get AKS credentials"
        return 1
    fi
    
    # Test connectivity
    log_info "Running kubectl get nodes..."
    if kubectl get nodes --request-timeout=30s &> /dev/null; then
        local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        local ready_count=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
        log_success "kubectl connected: $ready_count/$node_count nodes Ready"
        
        # Show node details
        echo ""
        kubectl get nodes -o wide
        echo ""
    else
        log_error "kubectl connection failed (ensure VPN is connected)"
        return 1
    fi
    
    # Test namespace creation
    log_info "Testing namespace creation..."
    local test_ns="validation-test-$(date +%s)"
    if kubectl create namespace "$test_ns" &> /dev/null; then
        log_success "Namespace creation successful"
        kubectl delete namespace "$test_ns" &> /dev/null || true
    else
        log_warning "Namespace creation failed (may lack permissions)"
    fi
    
    return 0
}

check_acr_integration() {
    log_info "Checking ACR integration..."
    
    # Get kubelet identity
    local kubelet_id=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "identityProfile.kubeletidentity.objectId" \
        -o tsv)
    
    if [ -z "$kubelet_id" ]; then
        log_warning "Could not get kubelet identity"
        return 1
    fi
    
    # Check if ACR exists
    if ! az group show --name rg-ai-acr &> /dev/null; then
        log_warning "ACR resource group not found - ACR integration not configured"
        return 0
    fi
    
    local acr_name=$(az acr list --resource-group rg-ai-acr --query "[0].name" -o tsv 2>/dev/null)
    if [ -z "$acr_name" ]; then
        log_warning "No ACR found in rg-ai-acr"
        return 0
    fi
    
    local acr_id=$(az acr show --name "$acr_name" --resource-group rg-ai-acr --query id -o tsv)
    
    # Check role assignment
    local has_role=$(az role assignment list \
        --assignee "$kubelet_id" \
        --scope "$acr_id" \
        --query "[?roleDefinitionName=='AcrPull'].id" \
        -o tsv 2>/dev/null)
    
    if [ -n "$has_role" ]; then
        log_success "ACR integration configured: AcrPull role on $acr_name"
    else
        log_warning "AcrPull role not found for kubelet identity on $acr_name"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--full)
            FULL_VALIDATION=true
            shift
            ;;
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
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
echo "  AKS Validation"
echo "=========================================="
echo ""

# Run validations
check_prerequisites
check_resource_group
check_cluster_exists
check_private_cluster
check_rbac_enabled
check_node_pools
check_network_profile
check_acr_integration

# Full validation with kubectl
if [ "$FULL_VALIDATION" = true ]; then
    echo ""
    log_info "Running full validation (kubectl tests)..."
    if check_vpn_connection; then
        check_kubectl_connectivity
    else
        log_warning "Skipping kubectl tests - VPN not connected"
    fi
fi

echo ""
log_success "AKS validation complete!"
