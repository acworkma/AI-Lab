#!/usr/bin/env bash
#
# grant-storage-roles.sh - Grant RBAC roles for Storage Account data operations
# 
# Purpose: Assign Storage Blob Data Contributor or Reader role to users/groups
#          for accessing blob data via Azure CLI or SDK
#
# Usage: ./scripts/grant-storage-roles.sh --user <email> [--role <role>]
#
# Prerequisites:
# - Storage account deployed
# - User running this script has "User Access Administrator" role
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/storage/main.parameters.json"
USER_EMAIL=""
SERVICE_PRINCIPAL_ID=""
GROUP_ID=""
ROLE_NAME="Storage Blob Data Contributor"

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

Grant RBAC roles for Storage Account data operations

OPTIONS:
    -u, --user EMAIL            User email/UPN to grant access
    -s, --service-principal ID  Service principal object ID to grant access
    -g, --group ID              Group object ID to grant access
    -r, --role ROLE             Role to assign (default: "Storage Blob Data Contributor")
    -p, --parameter-file PATH   Path to parameter file (default: bicep/storage/main.parameters.json)
    -h, --help                  Show this help message

AVAILABLE ROLES:
    "Storage Blob Data Contributor"  - Read, write, delete blobs (default)
    "Storage Blob Data Reader"       - Read-only access to blobs
    "Storage Blob Data Owner"        - Full access including RBAC management

EXAMPLES:
    # Grant contributor access to a user
    $0 --user john@contoso.com

    # Grant read-only access
    $0 --user jane@contoso.com --role "Storage Blob Data Reader"

    # Grant access to a service principal
    $0 --service-principal 12345678-1234-1234-1234-123456789012

    # Grant access to a group
    $0 --group abcd1234-efgh-5678-ijkl-901234567890

EOF
    exit 1
}

get_storage_scope() {
    local STORAGE_RG
    STORAGE_RG=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    # Get subscription ID
    local SUB_ID
    SUB_ID=$(az account show --query id -o tsv)
    
    echo "/subscriptions/${SUB_ID}/resourceGroups/${STORAGE_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_NAME}"
}

check_existing_assignment() {
    local ASSIGNEE_ID="$1"
    local SCOPE="$2"
    
    local EXISTING
    EXISTING=$(az role assignment list \
        --assignee "$ASSIGNEE_ID" \
        --scope "$SCOPE" \
        --role "$ROLE_NAME" \
        --query "[].id" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$EXISTING" ]]; then
        return 0  # Assignment exists
    else
        return 1  # No assignment
    fi
}

grant_role_to_user() {
    local USER="$1"
    
    log_info "Resolving user: $USER"
    
    # Get user object ID
    local USER_ID
    USER_ID=$(az ad user show --id "$USER" --query id -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$USER_ID" ]]; then
        log_error "User not found in Azure AD: $USER"
        exit 1
    fi
    
    log_info "User object ID: $USER_ID"
    
    local SCOPE
    SCOPE=$(get_storage_scope)
    
    # Check if already assigned
    if check_existing_assignment "$USER_ID" "$SCOPE"; then
        log_warning "User already has '$ROLE_NAME' role on storage account"
        return 0
    fi
    
    log_info "Assigning role '$ROLE_NAME' to user..."
    
    az role assignment create \
        --assignee-object-id "$USER_ID" \
        --assignee-principal-type "User" \
        --role "$ROLE_NAME" \
        --scope "$SCOPE"
    
    log_success "Role assigned to user: $USER"
}

grant_role_to_sp() {
    local SP_ID="$1"
    
    log_info "Service principal object ID: $SP_ID"
    
    local SCOPE
    SCOPE=$(get_storage_scope)
    
    # Check if already assigned
    if check_existing_assignment "$SP_ID" "$SCOPE"; then
        log_warning "Service principal already has '$ROLE_NAME' role on storage account"
        return 0
    fi
    
    log_info "Assigning role '$ROLE_NAME' to service principal..."
    
    az role assignment create \
        --assignee-object-id "$SP_ID" \
        --assignee-principal-type "ServicePrincipal" \
        --role "$ROLE_NAME" \
        --scope "$SCOPE"
    
    log_success "Role assigned to service principal: $SP_ID"
}

grant_role_to_group() {
    local GROUP_ID="$1"
    
    log_info "Group object ID: $GROUP_ID"
    
    local SCOPE
    SCOPE=$(get_storage_scope)
    
    # Check if already assigned
    if check_existing_assignment "$GROUP_ID" "$SCOPE"; then
        log_warning "Group already has '$ROLE_NAME' role on storage account"
        return 0
    fi
    
    log_info "Assigning role '$ROLE_NAME' to group..."
    
    az role assignment create \
        --assignee-object-id "$GROUP_ID" \
        --assignee-principal-type "Group" \
        --role "$ROLE_NAME" \
        --scope "$SCOPE"
    
    log_success "Role assigned to group: $GROUP_ID"
}

list_current_assignments() {
    log_info "Current role assignments on storage account:"
    
    local SCOPE
    SCOPE=$(get_storage_scope)
    
    az role assignment list \
        --scope "$SCOPE" \
        --query "[].{Principal:principalName, Role:roleDefinitionName, Type:principalType}" \
        --output table
}

# ============================================================================
# MAIN
# ============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)
            USER_EMAIL="$2"
            shift 2
            ;;
        -s|--service-principal)
            SERVICE_PRINCIPAL_ID="$2"
            shift 2
            ;;
        -g|--group)
            GROUP_ID="$2"
            shift 2
            ;;
        -r|--role)
            ROLE_NAME="$2"
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
echo " Grant Storage RBAC Roles"
echo "=============================================="
echo ""

# Check at least one assignee specified
if [[ -z "$USER_EMAIL" && -z "$SERVICE_PRINCIPAL_ID" && -z "$GROUP_ID" ]]; then
    log_error "No assignee specified. Use --user, --service-principal, or --group"
    usage
fi

# Validate parameter file
if [[ ! -f "$PARAMETER_FILE" ]]; then
    log_error "Parameter file not found: $PARAMETER_FILE"
    exit 1
fi

# Extract storage account info
STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
STORAGE_RG=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")

log_info "Storage Account: $STORAGE_NAME"
log_info "Resource Group: $STORAGE_RG"
log_info "Role: $ROLE_NAME"
echo ""

# Verify storage account exists
if ! az storage account show --name "$STORAGE_NAME" --resource-group "$STORAGE_RG" &>/dev/null; then
    log_error "Storage account not found: $STORAGE_NAME in $STORAGE_RG"
    log_info "Deploy storage first: ./scripts/deploy-storage.sh"
    exit 1
fi

# Grant roles
if [[ -n "$USER_EMAIL" ]]; then
    grant_role_to_user "$USER_EMAIL"
fi

if [[ -n "$SERVICE_PRINCIPAL_ID" ]]; then
    grant_role_to_sp "$SERVICE_PRINCIPAL_ID"
fi

if [[ -n "$GROUP_ID" ]]; then
    grant_role_to_group "$GROUP_ID"
fi

echo ""
list_current_assignments

echo ""
log_success "Role assignment complete!"
log_info "User can now access blobs using: az storage blob list --account-name $STORAGE_NAME --auth-mode login"
