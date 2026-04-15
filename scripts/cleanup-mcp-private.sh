#!/usr/bin/env bash
#
# cleanup-mcp-private.sh - Clean up Private MCP Server Solution
# 
# Purpose: Remove MCP API definition from private APIM. Does NOT remove
#          the APIM instance itself (that's cleanup-apim-private.sh).
#
# Usage: ./scripts/cleanup-mcp-private.sh [--auto-approve]
#

set -euo pipefail

# Default values
APIM_RG="${APIM_RG:-rg-ai-apim-private}"
APIM_NAME="${APIM_NAME:-apim-ai-lab-private}"
AUTO_APPROVE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--auto-approve]"
            echo ""
            echo "Remove MCP API definition from private APIM."
            echo "Does NOT remove the APIM instance (use cleanup-apim-private.sh for that)."
            echo ""
            echo "OPTIONS:"
            echo "    --auto-approve    Skip confirmation"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo "=============================================="
echo "  Private MCP Server Solution Cleanup"
echo "=============================================="
echo ""

log_info "Resources to remove:"
echo "  - MCP API definition (mcp-api) from $APIM_NAME"
echo ""
log_warning "This does NOT remove:"
echo "  - Private APIM instance (use cleanup-apim-private.sh)"
echo "  - Power Platform enterprise policy (use PowerShell)"
echo "  - Custom connector in Copilot Studio (remove manually)"
echo ""

if [ "$AUTO_APPROVE" = false ]; then
    read -p "Are you sure you want to proceed? (yes/no): " response
    case "$response" in
        [Yy][Ee][Ss])
            ;;
        *)
            log_info "Cleanup cancelled."
            exit 0
            ;;
    esac
fi

# Delete MCP API from APIM
MCP_API=$(az apim api show --api-id "mcp-api" --service-name "$APIM_NAME" --resource-group "$APIM_RG" --query "name" -o tsv 2>/dev/null || echo "")

if [ -n "$MCP_API" ]; then
    log_info "Deleting MCP API from $APIM_NAME..."
    az apim api delete --api-id "mcp-api" --service-name "$APIM_NAME" --resource-group "$APIM_RG" --yes
    log_success "MCP API deleted from private APIM"
else
    log_info "MCP API not found in $APIM_NAME, skipping"
fi

echo ""
log_success "Cleanup complete!"
echo ""
log_info "To remove Power Platform enterprise policy, run in PowerShell:"
echo "  Remove-SubnetInjection -EnvironmentId <PP_ENVIRONMENT_ID>"
echo ""
log_info "To remove the APIM infrastructure:"
echo "  ./scripts/cleanup-apim-private.sh"
