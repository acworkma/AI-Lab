#!/usr/bin/env bash
#
# deploy-aks.sh - Deploy Private Azure Kubernetes Service
#
# Purpose: Orchestrate deployment of AKS resource group and private Kubernetes cluster
#          with private endpoint, Azure RBAC, and ACR integration
#
# Usage: ./scripts/deploy-aks.sh [--parameter-file <path>] [--skip-whatif] [--auto-approve]
#
# Prerequisites:
# - Core infrastructure deployed (run scripts/deploy-core.sh first)
# - Private ACR deployed (run scripts/deploy-registry.sh first)
# - VPN connection established (for validation)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/aks/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/aks/main.bicep"
DEPLOYMENT_NAME="deploy-ai-aks-$(date +%Y%m%d-%H%M%S)"
SKIP_WHATIF=false
AUTO_APPROVE=false
LOCATION="eastus2"

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

Deploy Private Azure Kubernetes Service with private endpoint connectivity

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/aks/main.parameters.json)
    -s, --skip-whatif           Skip what-if analysis (not recommended)
    -a, --auto-approve          Skip confirmation prompt (use with caution)
    -h, --help                  Show this help message

EXAMPLES:
    # Standard deployment with what-if and confirmation
    $0

    # Use custom parameter file
    $0 --parameter-file bicep/aks/main.parameters.prod.json

    # Automated deployment (CI/CD)
    $0 --auto-approve

EOF
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Install from: https://aka.ms/azure-cli"
        exit 1
    fi
    log_success "Azure CLI found: $(az version --query '\"azure-cli\"' -o tsv)"

    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run: az login"
        exit 1
    fi
    local account_name=$(az account show --query name -o tsv)
    log_success "Logged in to Azure subscription: $account_name"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl not found. Install for cluster management: https://kubernetes.io/docs/tasks/tools/"
    else
        log_success "kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client -o yaml | grep gitVersion | head -1)"
    fi

    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Install from: https://jqlang.github.io/jq/"
        exit 1
    fi

    # Check template file exists
    if [ ! -f "$TEMPLATE_FILE" ]; then
        log_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi
    log_success "Template file found: $TEMPLATE_FILE"

    # Check parameter file exists
    if [ ! -f "$PARAMETER_FILE" ]; then
        log_error "Parameter file not found: $PARAMETER_FILE"
        exit 1
    fi
    log_success "Parameter file found: $PARAMETER_FILE"
}

check_core_infrastructure() {
    log_info "Checking core infrastructure..."

    # Check if core resource group exists
    if ! az group show --name rg-ai-core &> /dev/null; then
        log_error "Core infrastructure not found (rg-ai-core does not exist)"
        log_error "Deploy core infrastructure first: ./scripts/deploy-core.sh"
        exit 1
    fi
    log_success "Core infrastructure resource group found: rg-ai-core"
}

check_acr_infrastructure() {
    log_info "Checking ACR infrastructure..."

    # Check if ACR resource group exists
    if ! az group show --name rg-ai-acr &> /dev/null; then
        log_warning "ACR infrastructure not found (rg-ai-acr does not exist)"
        log_warning "ACR integration will be skipped. Deploy ACR first: ./scripts/deploy-registry.sh"
        return 1
    fi
    
    # Get ACR name
    local acr_name=$(az acr list --resource-group rg-ai-acr --query "[0].name" -o tsv 2>/dev/null)
    if [ -z "$acr_name" ]; then
        log_warning "No ACR found in rg-ai-acr"
        return 1
    fi
    
    log_success "ACR found: $acr_name"
    echo "$acr_name"
    return 0
}

check_quota() {
    log_info "Checking VM quota for Standard_D2s_v3..."
    
    local vm_size="Standard_D2s_v3"
    local node_count=3
    local required_cores=$((node_count * 2))  # D2s_v3 has 2 cores
    
    # Get current usage for DSv3 family
    local usage=$(az vm list-usage --location "$LOCATION" --query "[?name.value=='standardDSv3Family'].{current:currentValue, limit:limit}" -o json 2>/dev/null)
    
    if [ -n "$usage" ] && [ "$usage" != "[]" ]; then
        local current=$(echo "$usage" | jq -r '.[0].current // 0')
        local limit=$(echo "$usage" | jq -r '.[0].limit // 0')
        local available=$((limit - current))
        
        if [ "$available" -lt "$required_cores" ]; then
            log_error "Insufficient quota for $vm_size"
            log_error "Required: $required_cores cores, Available: $available cores"
            log_error "Request quota increase: https://aka.ms/ProdportalCRP/?#blade/Microsoft_Azure_Capacity/UsageAndQuota.ReactView"
            exit 1
        fi
        log_success "VM quota sufficient: $available cores available (need $required_cores)"
    else
        log_warning "Could not verify quota. Proceeding anyway..."
    fi
}

get_kubernetes_version() {
    log_info "Getting default Kubernetes version for $LOCATION..."
    
    local default_version=$(az aks get-versions \
        --location "$LOCATION" \
        --query "values[?isDefault].version | [0]" \
        -o tsv 2>/dev/null)
    
    if [ -n "$default_version" ]; then
        log_success "Default Kubernetes version: $default_version"
        echo "$default_version"
    else
        log_warning "Could not determine default version, Azure will select"
    fi
}

run_whatif() {
    if [ "$SKIP_WHATIF" = true ]; then
        log_warning "Skipping what-if analysis (--skip-whatif specified)"
        return 0
    fi

    log_info "Running what-if analysis..."
    echo ""
    
    az deployment sub what-if \
        --name "$DEPLOYMENT_NAME-whatif" \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE"
    
    echo ""
    log_success "What-if analysis complete"
}

confirm_deployment() {
    if [ "$AUTO_APPROVE" = true ]; then
        log_warning "Auto-approve enabled, skipping confirmation"
        return 0
    fi

    echo ""
    read -p "Do you want to proceed with the deployment? (y/N) " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

deploy() {
    log_info "Starting AKS deployment..."
    log_info "Deployment name: $DEPLOYMENT_NAME"
    
    local start_time=$(date +%s)
    
    az deployment sub create \
        --name "$DEPLOYMENT_NAME" \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --output none
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "AKS deployment completed in $duration seconds"
}

assign_acr_role() {
    local acr_name="$1"
    
    log_info "Assigning AcrPull role to AKS kubelet identity..."
    
    # Get kubelet identity from deployment outputs
    local kubelet_id=$(az deployment sub show \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs.kubeletIdentityObjectId.value" \
        -o tsv)
    
    if [ -z "$kubelet_id" ]; then
        log_error "Could not get kubelet identity from deployment"
        return 1
    fi
    
    # Get ACR resource ID
    local acr_id=$(az acr show --name "$acr_name" --resource-group rg-ai-acr --query id -o tsv)
    
    # Assign AcrPull role
    log_info "Assigning AcrPull role to identity: $kubelet_id"
    
    az role assignment create \
        --assignee-object-id "$kubelet_id" \
        --assignee-principal-type ServicePrincipal \
        --role AcrPull \
        --scope "$acr_id" \
        --output none 2>/dev/null || {
            log_warning "Role assignment may already exist or require propagation time"
        }
    
    log_success "AcrPull role assigned to AKS kubelet identity"
}

assign_cluster_admin_role() {
    log_info "Assigning Azure Kubernetes Service Cluster Admin role to deploying user..."
    
    # Get current user object ID
    local user_id=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)
    
    if [ -z "$user_id" ]; then
        log_warning "Could not get current user ID. Skipping cluster admin role assignment."
        return 0
    fi
    
    # Get cluster resource ID
    local cluster_id=$(az deployment sub show \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs.clusterResourceId.value" \
        -o tsv)
    
    # Assign cluster admin role
    az role assignment create \
        --assignee-object-id "$user_id" \
        --assignee-principal-type User \
        --role "Azure Kubernetes Service Cluster Admin Role" \
        --scope "$cluster_id" \
        --output none 2>/dev/null || {
            log_warning "Role assignment may already exist"
        }
    
    log_success "Cluster admin role assigned to current user"
}

show_outputs() {
    log_info "Deployment outputs:"
    echo ""
    
    local outputs=$(az deployment sub show \
        --name "$DEPLOYMENT_NAME" \
        --query properties.outputs \
        -o json)
    
    echo "$outputs" | jq -r 'to_entries[] | "  \(.key): \(.value.value)"'
    
    echo ""
    log_info "Next steps:"
    echo "  1. Connect to VPN"
    echo "  2. Get credentials: az aks get-credentials --resource-group rg-ai-aks --name $(echo "$outputs" | jq -r '.clusterName.value')"
    echo "  3. Verify nodes: kubectl get nodes"
    echo "  4. Run validation: ./scripts/validate-aks.sh"
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
echo "=========================================="
echo "  Private AKS Deployment"
echo "=========================================="
echo ""

# Run checks
check_prerequisites
check_core_infrastructure
check_quota

# Check ACR (optional)
ACR_NAME=""
if acr_result=$(check_acr_infrastructure 2>&1); then
    ACR_NAME=$(echo "$acr_result" | tail -1)
fi

# Get K8s version info
get_kubernetes_version

# Run what-if
run_whatif

# Confirm
confirm_deployment

# Deploy
deploy

# Assign roles
if [ -n "$ACR_NAME" ]; then
    assign_acr_role "$ACR_NAME"
fi
assign_cluster_admin_role

# Show outputs
show_outputs

echo ""
log_success "AKS deployment complete!"
