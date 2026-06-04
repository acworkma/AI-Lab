#!/usr/bin/env bash
#
# cleanup-aoai-private.sh - Clean up Private Azure OpenAI deployment
#
# Purpose: Remove the Azure OpenAI resource group and private endpoint
#
# Usage: ./scripts/cleanup-aoai-private.sh [--auto-approve]
#

set -euo pipefail

RESOURCE_GROUP="rg-ai-aoai"
AUTO_APPROVE=false

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

Clean up Private Azure OpenAI (Legacy) deployment

OPTIONS:
    --auto-approve  Skip confirmation prompts
    -h, --help      Show this help message

NOTES:
    - Deletes the entire resource group (account, deployment, private endpoint)
    - Does NOT remove the DNS zone (shared in rg-ai-core)
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve) AUTO_APPROVE=true; shift ;;
        -h|--help) usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

echo ""
echo "=============================================="
echo "  Private Azure OpenAI Cleanup"
echo "=============================================="
echo ""

log_info "Resources to remove:"
echo "  - Resource group: $RESOURCE_GROUP"
echo "    (includes: OpenAI account, model deployment, private endpoint)"
echo ""
log_warning "The privatelink.openai.azure.com DNS zone in rg-ai-core will NOT be removed"
echo ""

if [ "$AUTO_APPROVE" = false ]; then
    read -p "Are you sure you want to proceed? (yes/no): " response
    case "$response" in
        [Yy][Ee][Ss]) ;;
        *) log_info "Cleanup cancelled."; exit 0 ;;
    esac
fi

if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    log_info "Deleting resource group $RESOURCE_GROUP..."
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    log_success "Resource group deletion initiated (runs in background)"
else
    log_info "Resource group $RESOURCE_GROUP does not exist, skipping"
fi

echo ""
log_success "Cleanup complete!"
