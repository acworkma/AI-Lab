#!/usr/bin/env bash
#
# storage-ops.sh - Storage data operations (create, upload, list, download)
# 
# Purpose: Demonstrate and perform common blob storage operations using
#          Azure AD authentication (--auth-mode login) over VPN connection
#
# Usage: ./scripts/storage-ops.sh <command> [options]
#
# Prerequisites:
# - Storage account deployed
# - VPN connection established
# - User has "Storage Blob Data Contributor" role (run grant-storage-roles.sh)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/storage/main.parameters.json"
CONTAINER_NAME=""
BLOB_NAME=""
LOCAL_FILE=""
STORAGE_NAME=""

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
Usage: $0 <COMMAND> [OPTIONS]

Perform storage operations using Azure AD authentication

COMMANDS:
    create-container   Create a new blob container
    upload             Upload a file to a container
    list               List blobs in a container
    download           Download a blob to local file
    delete-blob        Delete a blob
    list-containers    List all containers

GLOBAL OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/storage/main.parameters.json)
    -h, --help                  Show this help message

COMMAND OPTIONS:
    create-container:
        -c, --container NAME    Container name (required)

    upload:
        -c, --container NAME    Container name (required)
        -f, --file PATH         Local file path (required)
        -b, --blob NAME         Blob name (defaults to file name)

    list:
        -c, --container NAME    Container name (required)

    download:
        -c, --container NAME    Container name (required)
        -b, --blob NAME         Blob name (required)
        -f, --file PATH         Local file path (required)

    delete-blob:
        -c, --container NAME    Container name (required)
        -b, --blob NAME         Blob name (required)

EXAMPLES:
    # Create a container
    $0 create-container --container data

    # Upload a file
    $0 upload --container data --file ./myfile.txt

    # List blobs
    $0 list --container data

    # Download a blob
    $0 download --container data --blob myfile.txt --file ./downloaded.txt

    # List all containers
    $0 list-containers

NOTES:
    - All operations use --auth-mode login (Azure AD authentication)
    - Requires VPN connection for private endpoint access
    - Run ./scripts/grant-storage-roles.sh first to get data access

EOF
    exit 1
}

load_storage_name() {
    if [[ ! -f "$PARAMETER_FILE" ]]; then
        log_error "Parameter file not found: $PARAMETER_FILE"
        exit 1
    fi
    
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    if [[ -z "$STORAGE_NAME" || "$STORAGE_NAME" == "null" ]]; then
        log_error "storageAccountName not set in parameter file"
        exit 1
    fi
    
    log_info "Storage Account: $STORAGE_NAME"
}

check_vpn_connection() {
    log_info "Checking VPN/network connectivity..."
    
    # Try to resolve storage FQDN
    local FQDN="${STORAGE_NAME}.blob.core.windows.net"
    local RESOLVED
    RESOLVED=$(dig "$FQDN" +short 2>/dev/null | head -1 || echo "")
    
    if [[ -z "$RESOLVED" ]]; then
        log_warning "DNS resolution failed - VPN may not be connected"
    elif [[ "$RESOLVED" == 10.* ]]; then
        log_success "DNS resolves to private IP: $RESOLVED"
    else
        log_warning "DNS resolves to public IP: $RESOLVED"
        log_info "Operations may fail - storage has public access disabled"
    fi
}

cmd_create_container() {
    if [[ -z "$CONTAINER_NAME" ]]; then
        log_error "Container name required: -c, --container NAME"
        exit 1
    fi
    
    log_info "Creating container: $CONTAINER_NAME"
    
    az storage container create \
        --account-name "$STORAGE_NAME" \
        --name "$CONTAINER_NAME" \
        --auth-mode login
    
    log_success "Container created: $CONTAINER_NAME"
}

cmd_upload() {
    if [[ -z "$CONTAINER_NAME" ]]; then
        log_error "Container name required: -c, --container NAME"
        exit 1
    fi
    
    if [[ -z "$LOCAL_FILE" ]]; then
        log_error "Local file required: -f, --file PATH"
        exit 1
    fi
    
    if [[ ! -f "$LOCAL_FILE" ]]; then
        log_error "File not found: $LOCAL_FILE"
        exit 1
    fi
    
    # Default blob name to file name
    if [[ -z "$BLOB_NAME" ]]; then
        BLOB_NAME=$(basename "$LOCAL_FILE")
    fi
    
    log_info "Uploading: $LOCAL_FILE → $CONTAINER_NAME/$BLOB_NAME"
    
    az storage blob upload \
        --account-name "$STORAGE_NAME" \
        --container-name "$CONTAINER_NAME" \
        --name "$BLOB_NAME" \
        --file "$LOCAL_FILE" \
        --auth-mode login \
        --overwrite
    
    log_success "Uploaded: $BLOB_NAME"
}

cmd_list() {
    if [[ -z "$CONTAINER_NAME" ]]; then
        log_error "Container name required: -c, --container NAME"
        exit 1
    fi
    
    log_info "Listing blobs in: $CONTAINER_NAME"
    
    az storage blob list \
        --account-name "$STORAGE_NAME" \
        --container-name "$CONTAINER_NAME" \
        --auth-mode login \
        --output table \
        --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}"
}

cmd_download() {
    if [[ -z "$CONTAINER_NAME" ]]; then
        log_error "Container name required: -c, --container NAME"
        exit 1
    fi
    
    if [[ -z "$BLOB_NAME" ]]; then
        log_error "Blob name required: -b, --blob NAME"
        exit 1
    fi
    
    if [[ -z "$LOCAL_FILE" ]]; then
        log_error "Local file path required: -f, --file PATH"
        exit 1
    fi
    
    log_info "Downloading: $CONTAINER_NAME/$BLOB_NAME → $LOCAL_FILE"
    
    az storage blob download \
        --account-name "$STORAGE_NAME" \
        --container-name "$CONTAINER_NAME" \
        --name "$BLOB_NAME" \
        --file "$LOCAL_FILE" \
        --auth-mode login
    
    log_success "Downloaded: $LOCAL_FILE"
}

cmd_delete_blob() {
    if [[ -z "$CONTAINER_NAME" ]]; then
        log_error "Container name required: -c, --container NAME"
        exit 1
    fi
    
    if [[ -z "$BLOB_NAME" ]]; then
        log_error "Blob name required: -b, --blob NAME"
        exit 1
    fi
    
    log_info "Deleting blob: $CONTAINER_NAME/$BLOB_NAME"
    
    az storage blob delete \
        --account-name "$STORAGE_NAME" \
        --container-name "$CONTAINER_NAME" \
        --name "$BLOB_NAME" \
        --auth-mode login
    
    log_success "Deleted: $BLOB_NAME"
}

cmd_list_containers() {
    log_info "Listing containers in: $STORAGE_NAME"
    
    az storage container list \
        --account-name "$STORAGE_NAME" \
        --auth-mode login \
        --output table \
        --query "[].{Name:name, Modified:properties.lastModified}"
}

# ============================================================================
# MAIN
# ============================================================================

# Need at least a command
if [[ $# -lt 1 ]]; then
    usage
fi

COMMAND="$1"
shift

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--container)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -f|--file)
            LOCAL_FILE="$2"
            shift 2
            ;;
        -b|--blob)
            BLOB_NAME="$2"
            shift 2
            ;;
        -p|--parameter-file)
            PARAMETER_FILE="$2"
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
echo " Storage Operations"
echo "=============================================="
echo ""

load_storage_name
check_vpn_connection
echo ""

# Execute command
case "$COMMAND" in
    create-container)
        cmd_create_container
        ;;
    upload)
        cmd_upload
        ;;
    list)
        cmd_list
        ;;
    download)
        cmd_download
        ;;
    delete-blob)
        cmd_delete_blob
        ;;
    list-containers)
        cmd_list_containers
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac

echo ""
log_success "Operation complete!"
