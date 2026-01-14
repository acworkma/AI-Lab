#!/usr/bin/env bash
#
# deploy-apim.sh - Deploy Azure API Management Standard v2 with VNet Integration
# 
# Purpose: Orchestrate deployment of APIM resource group, NSG, subnet, and APIM instance
#          with what-if validation and error handling
#
# Usage: ./scripts/deploy-apim.sh [--parameter-file <path>] [--skip-whatif] [--auto-approve] [--what-if]
#
# Constitutional Requirements:
# - Azure CLI deployment (Principle 5: Deployment Standards)
# - What-if analysis before applying (Principle 5: Deployment Standards)
# - Validation gates (Principle 5: Deployment Standards)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/apim/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/apim/main.bicep"
DEPLOYMENT_NAME="deploy-apim-$(date +%Y%m%d-%H%M%S)"
SKIP_WHATIF=false
AUTO_APPROVE=false
WHATIF_ONLY=false
LOCATION="australiaeast"

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

Deploy Azure API Management Standard v2 with VNet Integration

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/apim/main.parameters.json)
    -s, --skip-whatif           Skip what-if analysis (not recommended)
    -a, --auto-approve          Skip confirmation prompt (use with caution)
    -w, --what-if               Only run what-if analysis without deployment
    -h, --help                  Show this help message

EXAMPLES:
    # Standard deployment with what-if and confirmation
    $0

    # Use custom parameter file
    $0 --parameter-file bicep/apim/main.parameters.prod.json

    # What-if analysis only (no deployment)
    $0 --what-if

    # Automated deployment (CI/CD)
    $0 --auto-approve

NOTES:
    - APIM deployment takes approximately 15-20 minutes
    - Publisher email must be set in parameter file
    - Requires core infrastructure (rg-ai-core) to be deployed first

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

    # Check Azure CLI version (2.50.0+ required)
    if [[ "$cli_version" != "unknown" ]]; then
        local major=$(echo "$cli_version" | cut -d. -f1)
        local minor=$(echo "$cli_version" | cut -d. -f2)
        if [[ "$major" -lt 2 ]] || [[ "$major" -eq 2 && "$minor" -lt 50 ]]; then
            log_warning "Azure CLI 2.50.0+ recommended. Current: $cli_version"
        fi
    fi

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
        log_info "Create from example: cp ${REPO_ROOT}/bicep/apim/main.parameters.example.json $PARAMETER_FILE"
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
        log_error "Ensure core infrastructure is deployed correctly"
        exit 1
    fi
    log_success "Shared services VNet ($vnet_name) exists"
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

    # Validate email format (basic check)
    if [[ ! "$publisher_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email format: $publisher_email"
        exit 1
    fi

    log_success "Publisher email validated: $publisher_email"

    # Check APIM name format
    local apim_name=$(jq -r '.parameters.apimName.value // "apim-ai-lab"' "$PARAMETER_FILE")
    if [[ ! "$apim_name" =~ ^[a-zA-Z][a-zA-Z0-9-]{0,48}[a-zA-Z0-9]$ ]]; then
        log_error "Invalid APIM name format: $apim_name"
        log_error "Must start with letter, 1-50 characters, alphanumeric and hyphens only"
        exit 1
    fi
    log_success "APIM name validated: $apim_name"

    # Check subnet prefix doesn't overlap with existing subnets
    local subnet_prefix=$(jq -r '.parameters.apimSubnetPrefix.value // "10.1.0.64/26"' "$PARAMETER_FILE")
    log_info "APIM subnet prefix: $subnet_prefix"

    log_success "Parameters validated successfully"
}

detect_deployment_mode() {
    log_info "Checking deployment mode..."
    
    # Check if APIM resource group exists
    if az group show --name rg-ai-apim &> /dev/null; then
        DEPLOYMENT_MODE="update"
        log_info "Detected existing rg-ai-apim - this is an UPDATE deployment"
    else
        DEPLOYMENT_MODE="initial"
        log_info "No existing rg-ai-apim found - this is an INITIAL deployment"
    fi
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
    log_warning "⚠️  APIM deployment takes approximately 15-20 minutes"
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
    log_info "Starting APIM deployment..."
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
    log_success "APIM deployment completed!"
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
    echo "1. Publish Developer Portal:"
    echo "   az apim portalsetting update --resource-group rg-ai-apim --service-name apim-ai-lab"
    echo ""
    echo "2. Verify VNet Integration:"
    echo "   az apim show --name apim-ai-lab --resource-group rg-ai-apim --query 'virtualNetworkConfiguration'"
    echo ""
    echo "3. Run validation script:"
    echo "   ./scripts/validate-apim.sh"
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
echo "=============================================="
echo "  Azure API Management Standard v2 Deployment"
echo "=============================================="
echo ""

# Run deployment steps
check_prerequisites
check_core_infrastructure
validate_parameters
detect_deployment_mode

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

log_success "APIM deployment completed successfully!"
