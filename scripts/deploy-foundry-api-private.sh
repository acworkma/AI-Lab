#!/usr/bin/env bash
#
# deploy-foundry-api-private.sh - Deploy Foundry LLM API to Private APIM
#
# Purpose: Deploy the OpenAI-compatible API definition + policies to
#          the private APIM instance, connecting to the Foundry backend.
#
# Usage: ./scripts/deploy-foundry-api-private.sh [--what-if]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMPLATE_FILE="${REPO_ROOT}/bicep/foundry-api-private/main.bicep"
RESOURCE_GROUP="rg-ai-apim-private"
DEPLOYMENT_NAME="deploy-foundry-api-private-$(date +%Y%m%d-%H%M%S)"
WHATIF_ONLY=false

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--what-if) WHATIF_ONLY=true; shift ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

echo ""
echo "=============================================="
echo "  Foundry LLM API → Private APIM Deployment"
echo "=============================================="
echo ""

# Prerequisites
log_info "Checking prerequisites..."

if ! az account show &> /dev/null; then
    log_error "Not logged in to Azure"
    exit 1
fi

if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    log_error "Resource group $RESOURCE_GROUP not found"
    exit 1
fi

log_success "Prerequisites OK"

# What-if
if [ "$WHATIF_ONLY" = true ]; then
    log_info "Running what-if analysis..."
    az deployment group what-if \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE"
    exit 0
fi

# Deploy
log_info "Deploying Foundry LLM API..."
az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --output table

echo ""
log_success "Foundry LLM API deployed to private APIM!"
echo ""
log_info "Test with:"
echo "  ./scripts/test-foundry-api.sh"
echo ""
