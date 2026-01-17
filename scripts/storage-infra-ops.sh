#!/bin/bash
# ============================================================================
# Script: storage-infra-ops.sh
# Purpose: Data operations for Private Storage Account (container/blob management)
# Feature: 009-private-storage
# Requires: VPN connection, RBAC role assigned
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BICEP_DIR="${REPO_ROOT}/bicep/storage-infra"

# Defaults
PARAMETER_FILE="${BICEP_DIR}/main.parameters.json"

# ============================================================================
# Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Data operations for Private Storage Account.
Requires VPN connection and RBAC role assigned.

Commands:
    create-container <name>           Create a new container
    delete-container <name>           Delete a container
    list-containers                   List all containers
    upload <container> <file> [blob]  Upload file to container
    download <container> <blob> <file> Download blob to file
    list-blobs <container>            List blobs in container
    delete-blob <container> <blob>    Delete a blob
    test                              Run connectivity test

Options:
    -p, --parameters FILE    Parameter file path (default: main.parameters.json)
    -h, --help               Show this help message

Examples:
    $(basename "$0") create-container mydata
    $(basename "$0") upload mydata ./localfile.txt remote.txt
    $(basename "$0") list-blobs mydata
    $(basename "$0") download mydata remote.txt ./downloaded.txt

EOF
}

get_storage_name() {
    local suffix=$(jq -r '.parameters.storageNameSuffix.value' "$PARAMETER_FILE")
    echo "stailab${suffix}"
}

check_prerequisites() {
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found"
        exit 1
    fi
    
    # Check logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first."
        exit 1
    fi
    
    # Check parameter file
    if [[ ! -f "$PARAMETER_FILE" ]]; then
        log_error "Parameter file not found: $PARAMETER_FILE"
        exit 1
    fi
}

cmd_create_container() {
    local container_name="$1"
    local storage_name=$(get_storage_name)
    
    log_info "Creating container '$container_name' in $storage_name..."
    
    az storage container create \
        --name "$container_name" \
        --account-name "$storage_name" \
        --auth-mode login \
        --output none
    
    log_success "Container created: $container_name"
}

cmd_delete_container() {
    local container_name="$1"
    local storage_name=$(get_storage_name)
    
    log_warn "Deleting container '$container_name' from $storage_name..."
    
    az storage container delete \
        --name "$container_name" \
        --account-name "$storage_name" \
        --auth-mode login
    
    log_success "Container deleted: $container_name"
}

cmd_list_containers() {
    local storage_name=$(get_storage_name)
    
    log_info "Listing containers in $storage_name..."
    
    az storage container list \
        --account-name "$storage_name" \
        --auth-mode login \
        --output table
}

cmd_upload() {
    local container_name="$1"
    local local_file="$2"
    local blob_name="${3:-$(basename "$local_file")}"
    local storage_name=$(get_storage_name)
    
    if [[ ! -f "$local_file" ]]; then
        log_error "File not found: $local_file"
        exit 1
    fi
    
    log_info "Uploading '$local_file' to $storage_name/$container_name/$blob_name..."
    
    az storage blob upload \
        --container-name "$container_name" \
        --name "$blob_name" \
        --file "$local_file" \
        --account-name "$storage_name" \
        --auth-mode login \
        --overwrite \
        --output none
    
    log_success "Uploaded: $blob_name"
}

cmd_download() {
    local container_name="$1"
    local blob_name="$2"
    local local_file="$3"
    local storage_name=$(get_storage_name)
    
    log_info "Downloading $storage_name/$container_name/$blob_name to '$local_file'..."
    
    az storage blob download \
        --container-name "$container_name" \
        --name "$blob_name" \
        --file "$local_file" \
        --account-name "$storage_name" \
        --auth-mode login \
        --output none
    
    log_success "Downloaded: $local_file"
}

cmd_list_blobs() {
    local container_name="$1"
    local storage_name=$(get_storage_name)
    
    log_info "Listing blobs in $storage_name/$container_name..."
    
    az storage blob list \
        --container-name "$container_name" \
        --account-name "$storage_name" \
        --auth-mode login \
        --output table
}

cmd_delete_blob() {
    local container_name="$1"
    local blob_name="$2"
    local storage_name=$(get_storage_name)
    
    log_warn "Deleting blob '$blob_name' from $container_name..."
    
    az storage blob delete \
        --container-name "$container_name" \
        --name "$blob_name" \
        --account-name "$storage_name" \
        --auth-mode login
    
    log_success "Blob deleted: $blob_name"
}

cmd_test() {
    local storage_name=$(get_storage_name)
    
    echo ""
    echo "=========================================="
    echo "  Storage Connectivity Test"
    echo "=========================================="
    echo ""
    
    log_info "Storage account: $storage_name"
    log_info "Testing connectivity..."
    
    # Test listing containers (requires read permission)
    if az storage container list \
        --account-name "$storage_name" \
        --auth-mode login \
        --output none 2>/dev/null; then
        log_success "Connectivity OK - can list containers"
    else
        log_error "Connectivity FAILED - cannot list containers"
        log_error "Ensure VPN is connected and RBAC role is assigned"
        exit 1
    fi
    
    # Get container count
    local count=$(az storage container list \
        --account-name "$storage_name" \
        --auth-mode login \
        --query 'length(@)' \
        -o tsv)
    
    log_info "Found $count container(s)"
    
    echo ""
    log_success "Connectivity test passed!"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

# Parse global options first
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--parameters)
            PARAMETER_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Check we have a command
if [[ $# -lt 1 ]]; then
    show_usage
    exit 1
fi

COMMAND="$1"
shift

check_prerequisites

case "$COMMAND" in
    create-container)
        if [[ $# -lt 1 ]]; then
            log_error "Usage: $(basename "$0") create-container <name>"
            exit 1
        fi
        cmd_create_container "$1"
        ;;
    delete-container)
        if [[ $# -lt 1 ]]; then
            log_error "Usage: $(basename "$0") delete-container <name>"
            exit 1
        fi
        cmd_delete_container "$1"
        ;;
    list-containers)
        cmd_list_containers
        ;;
    upload)
        if [[ $# -lt 2 ]]; then
            log_error "Usage: $(basename "$0") upload <container> <file> [blob-name]"
            exit 1
        fi
        cmd_upload "$1" "$2" "${3:-}"
        ;;
    download)
        if [[ $# -lt 3 ]]; then
            log_error "Usage: $(basename "$0") download <container> <blob> <file>"
            exit 1
        fi
        cmd_download "$1" "$2" "$3"
        ;;
    list-blobs)
        if [[ $# -lt 1 ]]; then
            log_error "Usage: $(basename "$0") list-blobs <container>"
            exit 1
        fi
        cmd_list_blobs "$1"
        ;;
    delete-blob)
        if [[ $# -lt 2 ]]; then
            log_error "Usage: $(basename "$0") delete-blob <container> <blob>"
            exit 1
        fi
        cmd_delete_blob "$1" "$2"
        ;;
    test)
        cmd_test
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac
