#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PARAMETER_FILE="${REPO_ROOT}/bicep/foundry/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/foundry/main.bicep"
DEPLOYMENT_NAME="deploy-ai-foundry-$(date +%Y%m%d-%H%M%S)"
SKIP_WHATIF=false
AUTO_APPROVE=false
LOCATION="eastus2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

Deploy Private Foundry networking baseline and prerequisites

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/foundry/main.parameters.json)
    -s, --skip-whatif           Skip what-if analysis
    -a, --auto-approve          Skip confirmation prompt
    -h, --help                  Show this help message

EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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

check_prerequisites() {
    log_info "Checking prerequisites..."

    command -v az >/dev/null 2>&1 || { log_error "Azure CLI not found"; exit 1; }
    command -v jq >/dev/null 2>&1 || { log_error "jq not found"; exit 1; }

    az account show >/dev/null 2>&1 || { log_error "Not logged in to Azure. Run: az login"; exit 1; }

    [ -f "$TEMPLATE_FILE" ] || { log_error "Template file not found: $TEMPLATE_FILE"; exit 1; }
    [ -f "$PARAMETER_FILE" ] || { log_error "Parameter file not found: $PARAMETER_FILE"; exit 1; }

    local providers=(
      "Microsoft.KeyVault"
      "Microsoft.CognitiveServices"
      "Microsoft.Storage"
      "Microsoft.MachineLearningServices"
      "Microsoft.Search"
      "Microsoft.Network"
      "Microsoft.App"
      "Microsoft.ContainerService"
    )

    for provider in "${providers[@]}"; do
        local state
        state=$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || echo "Unknown")
        if [ "$state" != "Registered" ]; then
            log_warning "$provider is not Registered (state=$state). Registering..."
            az provider register --namespace "$provider" --wait >/dev/null
        fi
        log_success "$provider registered"
    done
}

run_whatif() {
    if [ "$SKIP_WHATIF" = true ]; then
        log_warning "Skipping what-if analysis"
        return 0
    fi

    log_info "Running what-if analysis..."
    az deployment sub what-if \
      --name "$DEPLOYMENT_NAME-whatif" \
      --location "$LOCATION" \
      --template-file "$TEMPLATE_FILE" \
      --parameters "@$PARAMETER_FILE"
}

confirm_deployment() {
    if [ "$AUTO_APPROVE" = true ]; then
        log_warning "Auto-approve enabled"
        return 0
    fi

    read -p "Proceed with Foundry deployment? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
}

deploy() {
    log_info "Deploying Private Foundry baseline..."

    az deployment sub create \
      --name "$DEPLOYMENT_NAME" \
      --location "$LOCATION" \
      --template-file "$TEMPLATE_FILE" \
      --parameters "@$PARAMETER_FILE" \
      --output none

    log_success "Deployment complete"
}

post_steps() {
    local rg_name
    rg_name=$(jq -r '.parameters.foundryResourceGroupName.value' "$PARAMETER_FILE")

    echo ""
    log_info "Next steps"
    echo "  1. Run validation: ./scripts/validate-foundry.sh"
    echo "  2. Run DNS validation from VPN-connected host: ./scripts/validate-foundry-dns.sh"
    echo "  3. Continue with Foundry account/project + private endpoints implementation"
    echo "  4. Resource group prepared: ${rg_name}"
}

main() {
    check_prerequisites
    run_whatif
    confirm_deployment
    deploy
    post_steps
}

main
