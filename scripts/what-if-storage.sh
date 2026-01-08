#!/usr/bin/env bash
#
# what-if-storage.sh - What-If deployment analysis and idempotency check
# 
# Purpose: Preview deployment changes and verify idempotent redeploys
#          produce no changes
#
# Usage: ./scripts/what-if-storage.sh [--idempotent]
#
# Prerequisites:
# - Parameter file configured
# - For --idempotent: Storage already deployed
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/storage/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/storage/main.bicep"
CHECK_IDEMPOTENT=false

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
    echo -e "${GREEN}[✓ PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

What-If analysis and idempotency verification for storage deployment

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file
    -i, --idempotent            Check for idempotent redeploy (no changes expected)
    -h, --help                  Show this help message

MODES:
    Default (what-if only):
        - Run what-if deployment analysis
        - Display planned changes
        - Summarize resource modifications

    Idempotent check (--idempotent):
        - Verify storage is already deployed
        - Run what-if and assert NO modifications
        - Fail if changes would be made

EXAMPLES:
    # Preview deployment changes
    $0

    # Verify idempotent redeploy produces no changes
    $0 --idempotent

EOF
    exit 1
}

run_whatif() {
    log_info "Running what-if analysis..."
    
    local LOCATION
    LOCATION=$(jq -r '.parameters.location.value // "eastus"' "$PARAMETER_FILE")
    
    az deployment sub what-if \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --no-pretty-print \
        --only-show-errors 2>&1 || true
}

count_changes() {
    local WHATIF_OUTPUT="$1"
    
    local CREATE_COUNT
    CREATE_COUNT=$(echo "$WHATIF_OUTPUT" | grep -c "Create" || echo "0")
    
    local MODIFY_COUNT
    MODIFY_COUNT=$(echo "$WHATIF_OUTPUT" | grep -c "Modify" || echo "0")
    
    local DELETE_COUNT
    DELETE_COUNT=$(echo "$WHATIF_OUTPUT" | grep -c "Delete" || echo "0")
    
    echo "$CREATE_COUNT $MODIFY_COUNT $DELETE_COUNT"
}

check_idempotency() {
    log_info "Checking idempotency (expecting no changes)..."
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    local STORAGE_RG
    STORAGE_RG=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    
    # First verify storage is deployed
    if ! az storage account show --name "$STORAGE_NAME" --resource-group "$STORAGE_RG" &>/dev/null; then
        log_error "Storage account not deployed: $STORAGE_NAME"
        log_info "Cannot check idempotency on non-existent resources"
        exit 1
    fi
    
    log_success "Storage account exists: $STORAGE_NAME"
    
    # Run what-if
    local LOCATION
    LOCATION=$(jq -r '.parameters.location.value // "eastus"' "$PARAMETER_FILE")
    
    local WHATIF_OUTPUT
    WHATIF_OUTPUT=$(az deployment sub what-if \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --no-pretty-print 2>&1 || echo "ERROR")
    
    if [[ "$WHATIF_OUTPUT" == *"ERROR"* ]]; then
        log_error "What-if analysis failed"
        echo "$WHATIF_OUTPUT"
        exit 1
    fi
    
    # Check for modifications
    if echo "$WHATIF_OUTPUT" | grep -q "NoChange"; then
        log_success "Idempotent: No changes would be made"
        return 0
    fi
    
    # Count changes
    local CHANGES
    CHANGES=$(count_changes "$WHATIF_OUTPUT")
    local CREATE_COUNT MODIFY_COUNT DELETE_COUNT
    read -r CREATE_COUNT MODIFY_COUNT DELETE_COUNT <<< "$CHANGES"
    
    if [[ $CREATE_COUNT -eq 0 && $MODIFY_COUNT -eq 0 && $DELETE_COUNT -eq 0 ]]; then
        log_success "Idempotent: No changes would be made"
        return 0
    else
        log_error "Idempotency FAILED: Changes detected"
        echo ""
        echo "Changes Summary:"
        echo "  Create: $CREATE_COUNT"
        echo "  Modify: $MODIFY_COUNT"
        echo "  Delete: $DELETE_COUNT"
        echo ""
        echo "Details:"
        echo "$WHATIF_OUTPUT" | grep -E "(Create|Modify|Delete)" | head -20
        return 1
    fi
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
        -i|--idempotent)
            CHECK_IDEMPOTENT=true
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
echo " Storage What-If Analysis"
echo "=============================================="
echo ""

# Validate files exist
if [[ ! -f "$PARAMETER_FILE" ]]; then
    log_error "Parameter file not found: $PARAMETER_FILE"
    exit 1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_error "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

if [[ "$CHECK_IDEMPOTENT" == "true" ]]; then
    check_idempotency
    EXIT_CODE=$?
else
    run_whatif
    EXIT_CODE=$?
fi

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    log_success "What-if analysis complete"
else
    log_error "What-if analysis detected issues"
fi

exit $EXIT_CODE
