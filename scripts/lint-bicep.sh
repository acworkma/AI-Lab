#!/usr/bin/env bash
#
# lint-bicep.sh - Lint and validate Bicep templates
# 
# Purpose: Run Bicep build/lint on storage modules for CI/CD and local validation
#
# Usage: ./scripts/lint-bicep.sh [--module storage|all]
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
MODULE="all"
LINT_PASSED=true

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
    LINT_PASSED=false
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Lint and validate Bicep templates

OPTIONS:
    -m, --module MODULE   Module to lint: storage, core, registry, or all (default: all)
    -h, --help            Show this help message

MODULES:
    storage   - bicep/modules/storage*.bicep, bicep/storage/main.bicep
    core      - bicep/main.bicep, bicep/modules/*.bicep (core)
    registry  - bicep/registry/main.bicep, bicep/modules/acr.bicep
    all       - All Bicep files in repository

EXAMPLES:
    # Lint all Bicep files
    $0

    # Lint storage module only
    $0 --module storage

EOF
    exit 1
}

lint_file() {
    local FILE="$1"
    local BASENAME
    BASENAME=$(basename "$FILE")
    
    # Check file exists
    if [[ ! -f "$FILE" ]]; then
        log_warning "File not found: $FILE"
        return 0
    fi
    
    # Run bicep build (validates syntax)
    if az bicep build --file "$FILE" --stdout > /dev/null 2>&1; then
        log_success "$BASENAME"
    else
        log_error "$BASENAME"
        echo "    Errors:"
        az bicep build --file "$FILE" 2>&1 | head -10 | sed 's/^/    /'
    fi
}

lint_storage() {
    log_info "Linting storage module..."
    
    # Main module
    lint_file "$REPO_ROOT/bicep/modules/storage.bicep"
    
    # Sub-modules
    lint_file "$REPO_ROOT/bicep/modules/storage-key.bicep"
    lint_file "$REPO_ROOT/bicep/modules/storage-rbac.bicep"
    
    # Orchestration
    lint_file "$REPO_ROOT/bicep/storage/main.bicep"
}

lint_registry() {
    log_info "Linting registry module..."
    
    lint_file "$REPO_ROOT/bicep/modules/acr.bicep"
    lint_file "$REPO_ROOT/bicep/registry/main.bicep"
}

lint_core() {
    log_info "Linting core modules..."
    
    lint_file "$REPO_ROOT/bicep/main.bicep"
    lint_file "$REPO_ROOT/bicep/modules/key-vault.bicep"
    lint_file "$REPO_ROOT/bicep/modules/resource-group.bicep"
    lint_file "$REPO_ROOT/bicep/modules/shared-services-vnet.bicep"
    lint_file "$REPO_ROOT/bicep/modules/private-dns-zones.bicep"
    lint_file "$REPO_ROOT/bicep/modules/vwan-hub.bicep"
    lint_file "$REPO_ROOT/bicep/modules/vpn-gateway.bicep"
    lint_file "$REPO_ROOT/bicep/modules/vpn-server-configuration.bicep"
}

lint_all() {
    log_info "Finding all Bicep files..."
    
    local FILES
    FILES=$(find "$REPO_ROOT/bicep" -name "*.bicep" -type f 2>/dev/null | sort)
    
    if [[ -z "$FILES" ]]; then
        log_warning "No Bicep files found"
        return
    fi
    
    local COUNT
    COUNT=$(echo "$FILES" | wc -l)
    log_info "Found $COUNT Bicep files"
    echo ""
    
    while IFS= read -r FILE; do
        lint_file "$FILE"
    done <<< "$FILES"
}

# ============================================================================
# MAIN
# ============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--module)
            MODULE="$2"
            shift 2
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
echo " Bicep Lint"
echo "=============================================="
echo ""

# Check Bicep CLI available
if ! command -v az &> /dev/null; then
    log_error "Azure CLI not installed"
    exit 1
fi

if ! az bicep version &> /dev/null; then
    log_info "Installing Bicep CLI..."
    az bicep install
fi

BICEP_VERSION=$(az bicep version 2>&1 | head -1)
log_info "Using: $BICEP_VERSION"
echo ""

# Run linting
case "$MODULE" in
    storage)
        lint_storage
        ;;
    registry)
        lint_registry
        ;;
    core)
        lint_core
        ;;
    all)
        lint_all
        ;;
    *)
        log_error "Unknown module: $MODULE"
        usage
        ;;
esac

echo ""
echo "=============================================="
if [[ "$LINT_PASSED" == "true" ]]; then
    log_success "All Bicep files pass linting"
    exit 0
else
    log_error "Some Bicep files have errors"
    exit 1
fi
