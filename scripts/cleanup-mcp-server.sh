#!/usr/bin/env bash
#
# cleanup-mcp-server.sh - Clean Up MCP Server Container App
#
# Purpose: Delete the MCP server container app from the ACA environment.
#          Does NOT delete the ACA environment itself (shared infrastructure).
#          Optionally removes the container image from ACR.
#
# Usage: ./scripts/cleanup-mcp-server.sh [OPTIONS]
#

set -euo pipefail

# Default values
APP_NAME="mcp-server"
ACA_RG="rg-ai-aca"
ACR_RG="rg-ai-acr"
FORCE=false
CLEAN_IMAGE=false

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

Delete the MCP server container app (preserves ACA environment)

OPTIONS:
    -n, --name NAME          Container app name (default: mcp-server)
    -f, --force              Skip confirmation prompt
    --clean-image            Also delete the container image from ACR
    -h, --help               Show this help message

NOTE:
    This script only deletes the container app, NOT the ACA environment.
    The ACA environment is shared infrastructure managed by deploy-aca.sh.

EXAMPLES:
    # Interactive cleanup
    $0

    # Force cleanup (no confirmation)
    $0 --force

    # Also remove image from ACR
    $0 --clean-image

EOF
    exit 1
}

confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    echo ""
    log_warning "This will delete container app: $APP_NAME"
    log_warning "Resource group: $ACA_RG"
    if [[ "$CLEAN_IMAGE" == "true" ]]; then
        log_warning "Container image will also be deleted from ACR"
    fi
    echo ""

    read -p "Type 'DELETE' to confirm: " CONFIRM

    if [[ "$CONFIRM" != "DELETE" ]]; then
        log_info "Deletion cancelled."
        exit 0
    fi
}

delete_container_app() {
    log_info "Checking if container app exists: $APP_NAME"

    if ! az containerapp show --name "$APP_NAME" --resource-group "$ACA_RG" &> /dev/null; then
        log_info "Container app '$APP_NAME' does not exist. Nothing to delete."
        return 0
    fi

    log_info "Deleting container app: $APP_NAME ..."

    if ! az containerapp delete \
        --name "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --yes ; then
        log_error "Failed to delete container app"
        return 1
    fi

    log_success "Container app deleted: $APP_NAME"
}

delete_acr_image() {
    if [[ "$CLEAN_IMAGE" != "true" ]]; then
        return 0
    fi

    log_info "Discovering ACR in '$ACR_RG'..."
    local ACR_NAME
    ACR_NAME=$(az acr list --resource-group "$ACR_RG" --query "[0].name" -o tsv 2>/dev/null)

    if [[ -z "$ACR_NAME" ]]; then
        log_warning "No ACR found in '$ACR_RG'. Skipping image cleanup."
        return 0
    fi

    log_info "Deleting repository '$APP_NAME' from ACR '$ACR_NAME'..."

    if az acr repository delete \
        --name "$ACR_NAME" \
        --repository "$APP_NAME" \
        --yes &> /dev/null; then
        log_success "ACR repository deleted: $APP_NAME"
    else
        log_warning "Failed to delete ACR repository (may not exist)"
    fi
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            APP_NAME="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --clean-image)
            CLEAN_IMAGE=true
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

# ============================================================================
# MAIN
# ============================================================================

echo ""
echo "============================================"
echo "MCP Server Cleanup"
echo "============================================"
echo ""

# Check Azure login
if ! az account show &> /dev/null; then
    log_error "Not logged into Azure. Run 'az login' first."
    exit 1
fi

echo "  App Name:       $APP_NAME"
echo "  Resource Group: $ACA_RG"
echo "  Clean Image:    $CLEAN_IMAGE"
echo ""

# Confirm
confirm_deletion

# Delete container app
delete_container_app

# Optionally delete ACR image
delete_acr_image

echo ""
echo "============================================"
log_success "MCP server cleanup complete!"
echo ""
log_info "Note: ACA environment ($ACA_RG) was preserved."
echo ""
