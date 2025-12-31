#!/usr/bin/env bash
#
# deploy-core.sh - Deploy Core Azure vWAN Infrastructure with Global Secure Access
# 
# Purpose: Orchestrate deployment of resource group, Virtual WAN hub, site-to-site VPN Gateway, 
#          and Key Vault with what-if validation and error handling
#
# Usage: ./scripts/deploy-core.sh [--parameter-file <path>] [--skip-whatif] [--auto-approve]
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
PARAMETER_FILE="${REPO_ROOT}/bicep/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/main.bicep"
DEPLOYMENT_NAME="deploy-ai-core-$(date +%Y%m%d-%H%M%S)"
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

Deploy Core Azure vWAN Infrastructure with Global Secure Access

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/main.parameters.json)
    -s, --skip-whatif           Skip what-if analysis (not recommended)
    -a, --auto-approve          Skip confirmation prompt (use with caution)
    -h, --help                  Show this help message

EXAMPLES:
    # Standard deployment with what-if and confirmation
    $0

    # Use custom parameter file
    $0 --parameter-file bicep/main.parameters.prod.json

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

validate_parameters() {
    log_info "Validating parameters..."

    # Check if keyVaultName contains CHANGEME placeholder
    local kv_name=$(jq -r '.parameters.keyVaultName.value // empty' "$PARAMETER_FILE")
    if [[ "$kv_name" == *"CHANGEME"* ]]; then
        log_error "Key Vault name contains placeholder 'CHANGEME'. Please set a unique name in $PARAMETER_FILE"
        exit 1
    fi

    # Validate Key Vault name format (3-24 chars, alphanumeric and hyphens)
    if [[ ! "$kv_name" =~ ^[a-zA-Z0-9-]{3,24}$ ]]; then
        log_error "Invalid Key Vault name format: $kv_name (must be 3-24 characters, alphanumeric and hyphens)"
        exit 1
    fi

    log_success "Parameters validated successfully"
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
    echo "  - Resource Group: rg-ai-core"
    echo "  - Virtual WAN: vwan-ai-hub"
    echo "  - Virtual Hub: hub-ai-eastus2"
    echo "  - VPN Gateway: vpngw-ai-hub (site-to-site with BGP for Global Secure Access)"
    echo "  - Key Vault: $(jq -r '.parameters.keyVaultName.value' "$PARAMETER_FILE")"
    echo ""
    log_warning "Estimated deployment time: 25-30 minutes"
    echo ""

    read -p "Do you want to proceed with deployment? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

deploy() {
    log_info "Starting deployment..."
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

show_outputs() {
    log_info "Retrieving deployment outputs..."
    echo ""

    # Get outputs
    local outputs=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs -o json)

    echo "Deployment Outputs:"
    echo "==================="
    echo "$outputs" | jq -r '
        "Resource Group: \(.resourceGroupName.value)",
        "Virtual WAN: \(.vwanName.value)",
        "Virtual Hub: \(.vhubName.value)",
        "  - Address Prefix: \(.vhubAddressPrefix.value)",
        "  - Routing State: \(.vhubRoutingState.value)",
        "VPN Gateway: \(.vpnGatewayName.value)",
        "  - Scale Units: \(.vpnGatewayScaleUnit.value)",
        "  - BGP ASN: \(.vpnGatewayBgpSettings.value.asn)",
        "  - BGP Peering Address: \(.vpnGatewayBgpSettings.value.bgpPeeringAddress)",
        "Key Vault: \(.keyVaultName.value)",
        "  - URI: \(.keyVaultUri.value)"
    '

    echo ""
    log_info "For Global Secure Access configuration, you will need:"
    echo "  - VPN Gateway BGP Peering Address: $(echo "$outputs" | jq -r '.vpnGatewayBgpSettings.value.bgpPeeringAddress')"
    echo "  - VPN Gateway BGP ASN: $(echo "$outputs" | jq -r '.vpnGatewayBgpSettings.value.asn')"
    echo ""
    log_info "See docs/core-infrastructure/global-secure-access.md for integration steps"
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

# Main execution
log_info "Core Azure vWAN Infrastructure Deployment"
log_info "=========================================="
echo ""

check_prerequisites
validate_parameters

if [ "$SKIP_WHATIF" = false ]; then
    run_whatif
fi

confirm_deployment
deploy
show_outputs

echo ""
log_success "Next steps:"
echo "  1. Run validation script: ./scripts/validate-core.sh"
echo "  2. Configure Global Secure Access: See docs/core-infrastructure/global-secure-access.md"
echo "  3. Deploy spoke labs: Connect to Virtual Hub using vhubId output"
echo ""
log_success "Deployment complete!"
