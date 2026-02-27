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

Deploy Private Foundry Phase 2 infrastructure (account, project, dependencies, private endpoints)

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
    log_info "Deploying Private Foundry Phase 2 stack..."

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

    local outputs
    outputs=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs -o json)
    local account_name
    account_name=$(echo "$outputs" | jq -r '.foundryAccountName.value // empty')
    local project_name
    project_name=$(echo "$outputs" | jq -r '.foundryProjectName.value // empty')
    local caphost_name
    caphost_name=$(echo "$outputs" | jq -r '.foundryProjectCapabilityHostName.value // empty')
    local account_caphost_name
    account_caphost_name=$(echo "$outputs" | jq -r '.foundryAccountCapabilityHostName.value // empty')
    local workspace_guid
    workspace_guid=$(echo "$outputs" | jq -r '.foundryProjectWorkspaceGuid.value // empty')

    echo ""
    log_info "Deployment summary"
    echo "  Resource group: ${rg_name}"
    [ -n "$account_name" ] && echo "  Foundry account: ${account_name}"
    [ -n "$project_name" ] && echo "  Foundry project: ${project_name}"
    [ -n "$account_caphost_name" ] && echo "  Account capability host: ${account_caphost_name}"
    [ -n "$caphost_name" ] && echo "  Project capability host: ${caphost_name}"
    [ -n "$workspace_guid" ] && echo "  Project workspace GUID: ${workspace_guid}"

    echo ""
    log_info "Next steps"
    echo "  1. Run baseline validation: ./scripts/validate-foundry.sh"
    echo "  2. Run operational validation: ./scripts/validate-foundry.sh --ops"
    echo "  3. Run DNS validation from VPN-connected host: ./scripts/validate-foundry-dns.sh <fqdn...>"
    echo "  4. Use cleanup flow when needed: ./scripts/cleanup-foundry.sh ..."
}

main() {
    check_prerequisites
    run_whatif
    confirm_deployment
    deploy
    post_steps
}

main
