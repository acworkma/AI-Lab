#!/usr/bin/env bash
#
# validate-storage-ops.sh - Validate storage data operations
# 
# Purpose: Run end-to-end storage operations test (create, upload, list, download, delete)
#          to verify data plane access and audit logging
#
# Usage: ./scripts/validate-storage-ops.sh
#
# Prerequisites:
# - Storage account deployed
# - VPN connection established
# - User has "Storage Blob Data Contributor" role
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/storage/main.parameters.json"
TEST_CONTAINER="validation-test"
TEST_BLOB="test-file.txt"
TEST_CONTENT="Storage validation test - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
CLEANUP=true
VALIDATION_PASSED=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Temp files
TEMP_UPLOAD=""
TEMP_DOWNLOAD=""

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
    VALIDATION_PASSED=false
}

cleanup() {
    log_info "Cleaning up..."
    
    # Remove temp files
    [[ -n "$TEMP_UPLOAD" && -f "$TEMP_UPLOAD" ]] && rm -f "$TEMP_UPLOAD"
    [[ -n "$TEMP_DOWNLOAD" && -f "$TEMP_DOWNLOAD" ]] && rm -f "$TEMP_DOWNLOAD"
    
    # Optionally delete test container
    if [[ "$CLEANUP" == "true" ]]; then
        local STORAGE_NAME
        STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE" 2>/dev/null || echo "")
        
        if [[ -n "$STORAGE_NAME" ]]; then
            az storage container delete \
                --account-name "$STORAGE_NAME" \
                --name "$TEST_CONTAINER" \
                --auth-mode login 2>/dev/null || true
        fi
    fi
}

trap cleanup EXIT

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate storage data operations end-to-end

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file
    --no-cleanup                Don't delete test container after validation
    -h, --help                  Show this help message

TESTS:
    1. Create container
    2. Upload blob
    3. List blobs
    4. Download blob
    5. Verify content matches
    6. Delete blob
    7. (Cleanup) Delete container

REQUIREMENTS:
    - VPN connection established
    - User has "Storage Blob Data Contributor" role on storage account

EOF
    exit 1
}

# ============================================================================
# TESTS
# ============================================================================

test_create_container() {
    log_info "Test: Create container..."
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    if az storage container create \
        --account-name "$STORAGE_NAME" \
        --name "$TEST_CONTAINER" \
        --auth-mode login &>/dev/null; then
        log_success "Created container: $TEST_CONTAINER"
        return 0
    else
        log_error "Failed to create container"
        return 1
    fi
}

test_upload_blob() {
    log_info "Test: Upload blob..."
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    # Create temp file with test content
    TEMP_UPLOAD=$(mktemp)
    echo "$TEST_CONTENT" > "$TEMP_UPLOAD"
    
    if az storage blob upload \
        --account-name "$STORAGE_NAME" \
        --container-name "$TEST_CONTAINER" \
        --name "$TEST_BLOB" \
        --file "$TEMP_UPLOAD" \
        --auth-mode login \
        --overwrite &>/dev/null; then
        log_success "Uploaded blob: $TEST_BLOB"
        return 0
    else
        log_error "Failed to upload blob"
        return 1
    fi
}

test_list_blobs() {
    log_info "Test: List blobs..."
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    local BLOBS
    BLOBS=$(az storage blob list \
        --account-name "$STORAGE_NAME" \
        --container-name "$TEST_CONTAINER" \
        --auth-mode login \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ "$BLOBS" == *"$TEST_BLOB"* ]]; then
        log_success "Listed blobs, found: $TEST_BLOB"
        return 0
    else
        log_error "Blob not found in list: $TEST_BLOB"
        return 1
    fi
}

test_download_blob() {
    log_info "Test: Download blob..."
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    TEMP_DOWNLOAD=$(mktemp)
    
    if az storage blob download \
        --account-name "$STORAGE_NAME" \
        --container-name "$TEST_CONTAINER" \
        --name "$TEST_BLOB" \
        --file "$TEMP_DOWNLOAD" \
        --auth-mode login &>/dev/null; then
        log_success "Downloaded blob: $TEST_BLOB"
        return 0
    else
        log_error "Failed to download blob"
        return 1
    fi
}

test_verify_content() {
    log_info "Test: Verify content..."
    
    if [[ ! -f "$TEMP_DOWNLOAD" ]]; then
        log_error "Downloaded file not found"
        return 1
    fi
    
    local DOWNLOADED_CONTENT
    DOWNLOADED_CONTENT=$(cat "$TEMP_DOWNLOAD")
    
    if [[ "$DOWNLOADED_CONTENT" == "$TEST_CONTENT" ]]; then
        log_success "Content verified: matches uploaded content"
        return 0
    else
        log_error "Content mismatch"
        log_info "Expected: $TEST_CONTENT"
        log_info "Got: $DOWNLOADED_CONTENT"
        return 1
    fi
}

test_delete_blob() {
    log_info "Test: Delete blob..."
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    if az storage blob delete \
        --account-name "$STORAGE_NAME" \
        --container-name "$TEST_CONTAINER" \
        --name "$TEST_BLOB" \
        --auth-mode login &>/dev/null; then
        log_success "Deleted blob: $TEST_BLOB"
        return 0
    else
        log_error "Failed to delete blob"
        return 1
    fi
}

check_audit_log() {
    log_info "Checking audit log capability..."
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    local STORAGE_RG
    STORAGE_RG=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    
    # Check if diagnostic settings exist
    local DIAG_SETTINGS
    DIAG_SETTINGS=$(az monitor diagnostic-settings list \
        --resource "$STORAGE_NAME" \
        --resource-type "Microsoft.Storage/storageAccounts" \
        --resource-group "$STORAGE_RG" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$DIAG_SETTINGS" ]]; then
        log_success "Audit logging configured: $DIAG_SETTINGS"
        log_info "Query logs in Log Analytics with: StorageBlobLogs | where AccountName == '$STORAGE_NAME'"
    else
        log_warning "No diagnostic settings found - audit logs may not be enabled"
        log_info "Configure logAnalyticsWorkspaceId in parameters to enable logging"
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
        --no-cleanup)
            CLEANUP=false
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
echo " Validate Storage Operations"
echo "=============================================="
echo ""

# Validate parameter file
if [[ ! -f "$PARAMETER_FILE" ]]; then
    log_error "Parameter file not found: $PARAMETER_FILE"
    exit 1
fi

STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
log_info "Storage Account: $STORAGE_NAME"
log_info "Test Container: $TEST_CONTAINER"
echo ""

# Run tests
test_create_container || true
test_upload_blob || true
test_list_blobs || true
test_download_blob || true
test_verify_content || true
test_delete_blob || true

echo ""
check_audit_log

echo ""
echo "=============================================="
if [[ "$VALIDATION_PASSED" == "true" ]]; then
    log_success "All storage operation tests passed!"
    exit 0
else
    log_error "Some tests failed - review output above"
    exit 1
fi
