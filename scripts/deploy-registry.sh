#!/usr/bin/env bash
#
# deploy-registry.sh - Deploy Private Azure Container Registry
# 
# Purpose: Orchestrate deployment of ACR resource group and private container registry
#          with private endpoint connectivity to core infrastructure
#
# Usage: ./scripts/deploy-registry.sh [--parameter-file <path>] [--skip-whatif] [--auto-approve]
#
# Prerequisites:
# - Core infrastructure deployed (run scripts/deploy-core.sh first)
# - VPN connection established (for DNS verification)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/registry/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/registry/main.bicep"
DEPLOYMENT_NAME="deploy-ai-acr-$(date +%Y%m%d-%H%M%S)"
CORE_DEPLOYMENT_NAME="deploy-ai-core"
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

Deploy Private Azure Container Registry with private endpoint connectivity

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/registry/main.parameters.json)
    -s, --skip-whatif           Skip what-if analysis (not recommended)
    -a, --auto-approve          Skip confirmation prompt (use with caution)
    -h, --help                  Show this help message

EXAMPLES:
    # Standard deployment with what-if and confirmation
    $0

    # Use custom parameter file
    $0 --parameter-file bicep/registry/main.parameters.prod.json

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

    # Get latest core deployment to retrieve outputs
    log_info "Retrieving core infrastructure outputs..."
    local latest_deployment=$(az deployment sub list \
        --query "[?contains(name, 'deploy-ai-core')].name | sort(@) | [-1]" \
        -o tsv)

    if [ -z "$latest_deployment" ]; then
        log_error "No core infrastructure deployment found"
        log_error "Deploy core infrastructure first: ./scripts/deploy-core.sh"
        exit 1
    fi

    log_info "Found core deployment: $latest_deployment"
    CORE_DEPLOYMENT_NAME="$latest_deployment"

    # Get required outputs
    local outputs=$(az deployment sub show --name "$CORE_DEPLOYMENT_NAME" --query properties.outputs -o json)
    
    PRIVATE_ENDPOINT_SUBNET_ID=$(echo "$outputs" | jq -r '.privateEndpointSubnetId.value // empty')
    ACR_DNS_ZONE_ID=$(echo "$outputs" | jq -r '.acrDnsZoneId.value // empty')

    if [ -z "$PRIVATE_ENDPOINT_SUBNET_ID" ] || [ -z "$ACR_DNS_ZONE_ID" ]; then
        log_error "Core infrastructure missing required outputs"
        log_error "Update core infrastructure: ./scripts/deploy-core.sh"
        exit 1
    fi

    log_success "Core infrastructure outputs retrieved"
    log_info "  - Private Endpoint Subnet: ${PRIVATE_ENDPOINT_SUBNET_ID##*/}"
    log_info "  - ACR DNS Zone: ${ACR_DNS_ZONE_ID##*/}"
}

prepare_parameters() {
    log_info "Preparing deployment parameters..."

    # Create temporary parameter file with core infrastructure references
    TEMP_PARAM_FILE=$(mktemp)
    
    jq --arg subnetId "$PRIVATE_ENDPOINT_SUBNET_ID" \
       --arg dnsZoneId "$ACR_DNS_ZONE_ID" \
       '.parameters.privateEndpointSubnetId.value = $subnetId | 
        .parameters.acrDnsZoneId.value = $dnsZoneId' \
       "$PARAMETER_FILE" > "$TEMP_PARAM_FILE"
    
    PARAMETER_FILE="$TEMP_PARAM_FILE"
    log_success "Parameters prepared with core infrastructure references"
}

run_whatif() {
    log_info "Running what-if analysis (dry-run)..."
    echo ""

    if ! az deployment sub what-if \
        --name "$DEPLOYMENT_NAME-whatif" \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE"; then
        log_error "What-if analysis failed. Please review errors above."
        exit 1
    fi

    echo ""
    log_success "What-if analysis completed successfully"
}

confirm_deployment() {
    if [ "$AUTO_APPROVE" = true ]; then
        log_warning "Auto-approve enabled, skipping confirmation"
        return 0
    fi

    echo ""
    log_warning "This will create the following resources in Azure:"
    echo "  - Resource Group: rg-ai-acr"
    echo "  - Azure Container Registry: acraihub<unique> (Standard SKU)"
    echo "  - Private Endpoint in: vnet-ai-shared/PrivateEndpointSubnet"
    echo "  - DNS Integration: privatelink.azurecr.io"
    echo ""
    log_warning "Estimated deployment time: 5-10 minutes"
    echo ""

    read -p "Do you want to proceed with deployment? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

deploy() {
    log_info "Starting ACR deployment..."
    log_info "Deployment name: $DEPLOYMENT_NAME"
    echo ""

    if ! az deployment sub create \
        --name "$DEPLOYMENT_NAME" \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE"; then
        log_error "Deployment failed. Check errors above."
        echo ""
        log_info "To view deployment details:"
        log_info "  az deployment sub show --name $DEPLOYMENT_NAME"
        exit 1
    fi

    echo ""
    log_success "Deployment completed successfully!"
}

assign_rbac_roles() {
    log_info "Assigning RBAC roles..."
    
    # Get ACR resource ID
    local outputs=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs -o json)
    local acr_id=$(echo "$outputs" | jq -r '.acrId.value')
    local acr_name=$(echo "$outputs" | jq -r '.acrName.value')
    
    # Get current user object ID
    local user_id=$(az ad signed-in-user show --query id -o tsv)
    
    log_info "Assigning AcrPush role to current user..."
    if az role assignment create \
        --assignee "$user_id" \
        --role "AcrPush" \
        --scope "$acr_id" &> /dev/null; then
        log_success "AcrPush role assigned"
    else
        log_warning "Failed to assign AcrPush role (may already exist)"
    fi
    
    log_info "Assigning AcrPull role to current user..."
    if az role assignment create \
        --assignee "$user_id" \
        --role "AcrPull" \
        --scope "$acr_id" &> /dev/null; then
        log_success "AcrPull role assigned"
    else
        log_warning "Failed to assign AcrPull role (may already exist)"
    fi
    
    echo ""
    log_warning "Note: RBAC role assignments may take up to 5 minutes to propagate"
    log_info "If 'az acr login' fails, wait a few minutes and retry"
}

verify_dns() {
    log_info "Verifying private DNS resolution..."
    echo ""
    
    # Get ACR login server
    local outputs=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs -o json)
    local acr_login_server=$(echo "$outputs" | jq -r '.acrLoginServer.value')
    
    log_info "ACR Login Server: $acr_login_server"
    log_info "Attempting DNS resolution (requires VPN connection)..."
    echo ""
    
    # Retry DNS resolution up to 10 times with 15 second intervals
    local max_retries=10
    local retry_interval=15
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if nslookup "$acr_login_server" &> /dev/null; then
            local resolved_ip=$(nslookup "$acr_login_server" | grep -A1 "Name:" | tail -1 | awk '{print $2}')
            
            # Check if resolved to private IP (10.x.x.x)
            if [[ "$resolved_ip" == 10.* ]]; then
                log_success "DNS resolved to private IP: $resolved_ip"
                return 0
            else
                log_warning "DNS resolved to public IP: $resolved_ip (expected private 10.x.x.x)"
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log_info "DNS not yet propagated. Retry $retry_count/$max_retries in ${retry_interval}s..."
            sleep $retry_interval
        fi
    done
    
    log_error "DNS resolution failed after $max_retries attempts"
    log_error "Ensure you are connected to the VPN and DNS is properly configured"
    log_info "You can manually verify with: nslookup $acr_login_server"
    return 1
}

show_outputs() {
    log_info "Retrieving deployment outputs..."
    echo ""

    # Get outputs
    local outputs=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs -o json)

    echo "Deployment Outputs:"
    echo "==================="
    echo "$outputs" | jq -r '
        "Resource Group: \(.resourceGroupName.value)",
        "ACR Name: \(.acrName.value)",
        "ACR Login Server: \(.acrLoginServer.value)",
        "ACR SKU: \(.acrSku.value)",
        "Private Endpoint: \(.privateEndpointId.value | split(\"/\") | .[-1])"
    '

    echo ""
    log_info "Next Steps:"
    echo "  1. Connect to VPN if not already connected"
    echo "  2. Login to ACR: az acr login --name $(echo "$outputs" | jq -r '.acrName.value')"
    echo "  3. Import image: az acr import --name $(echo "$outputs" | jq -r '.acrName.value') \\"
    echo "       --source ghcr.io/owner/image:tag \\"
    echo "       --image image:tag"
    echo ""
    log_info "See docs/registry/README.md for detailed image import workflows"
}

cleanup() {
    # Clean up temporary parameter file
    if [ -n "${TEMP_PARAM_FILE:-}" ] && [ -f "$TEMP_PARAM_FILE" ]; then
        rm -f "$TEMP_PARAM_FILE"
    fi
}

trap cleanup EXIT

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

# Main execution
log_info "Private Azure Container Registry Deployment"
log_info "==========================================="
echo ""

check_prerequisites
check_core_infrastructure
prepare_parameters

if [ "$SKIP_WHATIF" = false ]; then
    run_whatif
fi

confirm_deployment
deploy
assign_rbac_roles
verify_dns
show_outputs

echo ""
log_success "Deployment complete!"
