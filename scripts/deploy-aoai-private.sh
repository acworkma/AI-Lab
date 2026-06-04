#!/usr/bin/env bash
#
# deploy-aoai-private.sh - Deploy Private Azure OpenAI (Legacy)
# 
# Purpose: Deploy Azure OpenAI account (kind=OpenAI) with private endpoint,
#          gpt-4.1 model deployment, and DNS zone integration.
#
# Usage: ./scripts/deploy-aoai-private.sh [--skip-whatif] [--auto-approve] [--what-if]
#
# Prerequisites:
# - Core infrastructure deployed (rg-ai-core, vnet-ai-shared)
# - Azure CLI logged in
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PARAMETER_FILE="${REPO_ROOT}/bicep/aoai-private/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/aoai-private/main.bicep"
DEPLOYMENT_NAME="deploy-aoai-private-$(date +%Y%m%d-%H%M%S)"
SKIP_WHATIF=false
AUTO_APPROVE=false
WHATIF_ONLY=false
LOCATION="eastus2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Private Azure OpenAI (Legacy) infrastructure

OPTIONS:
    --parameter-file <path>  Override parameter file path
    --skip-whatif            Skip the what-if preview
    --auto-approve           Skip confirmation prompts
    --what-if                Only run what-if (no deployment)
    -h, --help               Show this help message
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --parameter-file) PARAMETER_FILE="$2"; shift 2 ;;
        --skip-whatif) SKIP_WHATIF=true; shift ;;
        --auto-approve) AUTO_APPROVE=true; shift ;;
        --what-if) WHATIF_ONLY=true; shift ;;
        -h|--help) usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

echo ""
echo "=============================================="
echo "  Private Azure OpenAI (Legacy) Deployment"
echo "=============================================="
echo ""

log_info "Template:   $TEMPLATE_FILE"
log_info "Parameters: $PARAMETER_FILE"
log_info "Location:   $LOCATION"
log_info "Deployment: $DEPLOYMENT_NAME"
echo ""

# Validate template
log_info "Validating template..."
if ! az deployment sub validate \
    --location "$LOCATION" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@${PARAMETER_FILE}" \
    --output none 2>&1; then
    log_error "Template validation failed"
    exit 1
fi
log_success "Template validation passed"

# What-if
if [ "$SKIP_WHATIF" = false ]; then
    echo ""
    log_info "Running what-if analysis..."
    az deployment sub what-if \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@${PARAMETER_FILE}" \
        --result-format FullResourcePayloads
    echo ""
fi

if [ "$WHATIF_ONLY" = true ]; then
    log_info "What-if only mode — exiting without deploying"
    exit 0
fi

# Confirm
if [ "$AUTO_APPROVE" = false ]; then
    read -p "Proceed with deployment? (yes/no): " response
    case "$response" in
        [Yy][Ee][Ss]) ;;
        *) log_info "Deployment cancelled."; exit 0 ;;
    esac
fi

# Deploy
echo ""
log_info "Starting deployment..."
az deployment sub create \
    --location "$LOCATION" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@${PARAMETER_FILE}" \
    --name "$DEPLOYMENT_NAME" \
    --output table

echo ""
log_success "Deployment complete!"
log_info "Run ./scripts/validate-aoai-private.sh to verify"
