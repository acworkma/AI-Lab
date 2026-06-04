#!/usr/bin/env bash
#
# deploy-aoai-api-private.sh - Deploy APIM API for Legacy Azure OpenAI
#
# Purpose: Deploy the /aoai API definition on private APIM that routes
#          to the legacy Azure OpenAI backend via managed identity.
#
# Usage: ./scripts/deploy-aoai-api-private.sh [--what-if]
#
# Prerequisites:
# - Private APIM deployed (apim-ai-lab-private in rg-ai-apim-private)
# - Private Azure OpenAI deployed (oai-ailab-private in rg-ai-aoai)
# - RBAC: APIM identity has Cognitive Services User on OpenAI account
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMPLATE_FILE="${REPO_ROOT}/bicep/aoai-api-private/main.bicep"
RESOURCE_GROUP="rg-ai-apim-private"
DEPLOYMENT_NAME="deploy-aoai-api-private-$(date +%Y%m%d-%H%M%S)"
WHATIF_ONLY=false

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

while [[ $# -gt 0 ]]; do
    case $1 in
        --what-if) WHATIF_ONLY=true; shift ;;
        -h|--help) echo "Usage: $0 [--what-if]"; exit 0 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

echo ""
echo "=============================================="
echo "  Deploy APIM API - Legacy Azure OpenAI (/aoai)"
echo "=============================================="
echo ""

log_info "Template:       $TEMPLATE_FILE"
log_info "Resource Group: $RESOURCE_GROUP"
log_info "Deployment:     $DEPLOYMENT_NAME"
echo ""

# Validate
log_info "Validating template..."
if ! az deployment group validate \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --output none 2>&1; then
    log_error "Validation failed"
    exit 1
fi
log_success "Validation passed"

if [ "$WHATIF_ONLY" = true ]; then
    log_info "Running what-if..."
    az deployment group what-if \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE"
    exit 0
fi

# Deploy
log_info "Deploying..."
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --name "$DEPLOYMENT_NAME" \
    --output table

echo ""
log_success "APIM API deployed at /aoai"
log_info "Test: curl https://apim-ai-lab-private.azure-api.net/aoai/deployments/gpt-4.1/chat/completions?api-version=2024-10-21"
