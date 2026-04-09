#!/usr/bin/env bash
#
# deploy-apim-private.sh - Deploy Private Azure API Management Standard v2
# 
# Purpose: Deploy APIM with inbound private endpoint, Power Platform subnet,
#          and private DNS zone. No public network exposure.
#
# Usage: ./scripts/deploy-apim-private.sh [--parameter-file <path>] [--skip-whatif] [--auto-approve] [--what-if]
#
# Prerequisites:
# - Core infrastructure deployed (rg-ai-core, vnet-ai-shared)
# - ACA + ACR + MCP server deployed
# - Azure CLI logged in
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/apim-private/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/apim-private/main.bicep"
DEPLOYMENT_NAME="deploy-apim-private-$(date +%Y%m%d-%H%M%S)"
SKIP_WHATIF=false
AUTO_APPROVE=false
WHATIF_ONLY=false
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

Deploy Private Azure API Management Standard v2 with:
  - Inbound private endpoint (no public gateway access)
  - VNet integration (outbound to private backends)
  - Power Platform delegated subnet (for Copilot Studio VNet support)
  - Private DNS zone (privatelink.azure-api.net)

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/apim-private/main.parameters.json)
    -s, --skip-whatif           Skip what-if analysis (not recommended)
    -a, --auto-approve          Skip confirmation prompt
    -w, --what-if               Only run what-if analysis without deployment
    -h, --help                  Show this help message

EXAMPLES:
    $0                          # Standard deployment with what-if and confirmation
    $0 --what-if                # What-if analysis only
    $0 --auto-approve           # Automated deployment (CI/CD)

NOTES:
    - APIM deployment takes approximately 15-20 minutes
    - Publisher email must be set in parameter file
    - Requires core infrastructure (rg-ai-core) deployed first
    - Creates resources in rg-ai-apim-private (separate from rg-ai-apim)

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
    local cli_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log_success "Azure CLI found: $cli_version"

    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run: az login"
        exit 1
    fi
    local account_name=$(az account show --query name -o tsv)
    log_success "Logged in to Azure subscription: $account_name"

    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Install with: sudo apt install jq"
        exit 1
    fi
    log_success "jq found"

    # Check template file exists
    if [ ! -f "$TEMPLATE_FILE" ]; then
        log_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi
    log_success "Template file found: $TEMPLATE_FILE"

    # Check parameter file exists
    if [ ! -f "$PARAMETER_FILE" ]; then
        log_error "Parameter file not found: $PARAMETER_FILE"
        log_info "Create from example: cp ${REPO_ROOT}/bicep/apim-private/main.parameters.example.json $PARAMETER_FILE"
        exit 1
    fi
    log_success "Parameter file found: $PARAMETER_FILE"
}

check_core_infrastructure() {
    log_info "Checking core infrastructure prerequisites..."

    # Check if rg-ai-core exists
    if ! az group show --name rg-ai-core &> /dev/null; then
        log_error "Core resource group (rg-ai-core) not found."
        log_error "Deploy core infrastructure first: ./scripts/deploy-core.sh"
        exit 1
    fi
    log_success "Core resource group (rg-ai-core) exists"

    # Check if shared services VNet exists
    local vnet_name=$(jq -r '.parameters.sharedServicesVnetName.value // "vnet-ai-shared"' "$PARAMETER_FILE")
    local vnet_rg=$(jq -r '.parameters.sharedServicesVnetResourceGroup.value // "rg-ai-core"' "$PARAMETER_FILE")
    
    if ! az network vnet show --name "$vnet_name" --resource-group "$vnet_rg" &> /dev/null; then
        log_error "Shared services VNet ($vnet_name) not found in $vnet_rg"
        exit 1
    fi
    log_success "Shared services VNet ($vnet_name) exists"

    # Check PrivateEndpointSubnet exists
    local pe_subnet=$(jq -r '.parameters.privateEndpointSubnetName.value // "PrivateEndpointSubnet"' "$PARAMETER_FILE")
    if ! az network vnet subnet show --name "$pe_subnet" --vnet-name "$vnet_name" --resource-group "$vnet_rg" &> /dev/null; then
        log_error "Private endpoint subnet ($pe_subnet) not found"
        exit 1
    fi
    log_success "Private endpoint subnet ($pe_subnet) exists"
}

validate_parameters() {
    log_info "Validating parameters..."

    # Check if publisherEmail is set and not a placeholder
    local publisher_email=$(jq -r '.parameters.publisherEmail.value // empty' "$PARAMETER_FILE")
    if [ -z "$publisher_email" ] || [[ "$publisher_email" == *"REPLACE"* ]] || [[ "$publisher_email" == *"example.com"* ]]; then
        log_error "Publisher email must be set in $PARAMETER_FILE"
        log_error "Current value: ${publisher_email:-<not set>}"
        exit 1
    fi

    if [[ ! "$publisher_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email format: $publisher_email"
        exit 1
    fi
    log_success "Publisher email validated: $publisher_email"

    # Check APIM name
    local apim_name=$(jq -r '.parameters.apimName.value // "apim-ai-lab-private"' "$PARAMETER_FILE")
    log_success "APIM name: $apim_name"

    log_success "Parameters validated successfully"
}

run_whatif() {
    log_info "Running what-if analysis (dry-run)..."
    echo ""

    az deployment sub what-if \
        --name "$DEPLOYMENT_NAME-whatif" \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE"

    echo ""
}

confirm_deployment() {
    if [ "$AUTO_APPROVE" = true ]; then
        log_info "Auto-approve enabled, proceeding with deployment..."
        return 0
    fi

    echo ""
    log_warning "This deployment creates:"
    echo "  - Private APIM instance (Standard v2) with inbound private endpoint"
    echo "  - Power Platform delegated subnet"
    echo "  - Private DNS zone (privatelink.azure-api.net)"
    echo "  - APIM integration subnet + NSG"
    echo ""
    log_warning "APIM deployment takes approximately 15-20 minutes"
    echo ""
    read -p "Do you want to proceed with the deployment? (yes/no): " response
    case "$response" in
        [Yy][Ee][Ss])
            return 0
            ;;
        *)
            log_info "Deployment cancelled."
            exit 0
            ;;
    esac
}

deploy() {
    log_info "Starting private APIM deployment..."
    log_info "Deployment name: $DEPLOYMENT_NAME"
    log_warning "This may take 15-20 minutes..."
    echo ""

    az deployment sub create \
        --name "$DEPLOYMENT_NAME" \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --output table

    echo ""
    log_success "Private APIM deployment completed!"
}

show_outputs() {
    log_info "Retrieving deployment outputs..."
    
    local outputs=$(az deployment sub show \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs" \
        --output json 2>/dev/null || echo "{}")
    
    if [ "$outputs" != "{}" ]; then
        echo ""
        echo "=== Deployment Outputs ==="
        echo "$outputs" | jq -r 'to_entries[] | "\(.key): \(.value.value)"'
        echo ""
    fi
}

show_post_deployment_steps() {
    echo ""
    log_info "=== Post-Deployment Steps ==="
    echo ""
    echo "1. Set up Power Platform VNet delegation:"
    echo "   ./scripts/setup-pp-vnet.sh"
    echo ""
    echo "2. Deploy MCP API to private APIM:"
    echo "   ./scripts/deploy-mcp-api-private.sh"
    echo ""
    echo "3. Run validation:"
    echo "   ./scripts/validate-apim-private.sh"
    echo ""
    echo "4. Create custom connector in Copilot Studio (see docs/apim-private/README.md)"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

# Parse command line arguments
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
        -w|--what-if)
            WHATIF_ONLY=true
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
echo "======================================================="
echo "  Private Azure API Management Standard v2 Deployment"
echo "======================================================="
echo ""

# Run deployment steps
check_prerequisites
check_core_infrastructure
validate_parameters

# Run what-if analysis
if [ "$SKIP_WHATIF" = false ]; then
    run_whatif
fi

# If what-if only mode, exit here
if [ "$WHATIF_ONLY" = true ]; then
    log_success "What-if analysis complete. No deployment performed."
    exit 0
fi

# Confirm and deploy
confirm_deployment
deploy
show_outputs
show_post_deployment_steps

log_success "Done!"
