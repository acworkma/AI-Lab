#!/bin/bash
# ============================================================================
# Script: grant-storage-infra-roles.sh
# Purpose: Grant RBAC roles for Private Storage Account access
# Feature: 009-private-storage
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
PRINCIPAL_ID=""
ROLE="Storage Blob Data Contributor"

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
Usage: $(basename "$0") [OPTIONS]

Grant RBAC roles for Private Storage Account access.

Options:
    -p, --parameters FILE    Parameter file path (default: main.parameters.json)
    -u, --user EMAIL         User email or UPN to grant access
    -s, --service-principal  Service principal object ID
    -g, --group              Group object ID
    -r, --role ROLE          Role to assign (default: "Storage Blob Data Contributor")
    --current-user           Grant access to currently logged-in user
    -h, --help               Show this help message

Available roles:
    Storage Blob Data Reader       - Read blob data
    Storage Blob Data Contributor  - Read/write blob data (default)
    Storage Blob Data Owner        - Full access including RBAC

Examples:
    $(basename "$0") --current-user
    $(basename "$0") --user user@example.com
    $(basename "$0") --service-principal 00000000-0000-0000-0000-000000000000
    $(basename "$0") --user user@example.com --role "Storage Blob Data Reader"

EOF
}

get_storage_name() {
    local suffix=$(jq -r '.parameters.storageNameSuffix.value' "$PARAMETER_FILE")
    echo "stailab${suffix}"
}

get_resource_group() {
    echo "rg-ai-storage"
}

get_current_user_id() {
    az ad signed-in-user show --query 'id' -o tsv 2>/dev/null
}

get_user_id() {
    local email="$1"
    az ad user show --id "$email" --query 'id' -o tsv 2>/dev/null
}

get_storage_resource_id() {
    local storage_name=$(get_storage_name)
    local rg_name=$(get_resource_group)
    
    az storage account show \
        --name "$storage_name" \
        --resource-group "$rg_name" \
        --query 'id' \
        -o tsv
}

check_existing_assignment() {
    local resource_id="$1"
    local principal_id="$2"
    local role="$3"
    
    local existing=$(az role assignment list \
        --scope "$resource_id" \
        --assignee "$principal_id" \
        --role "$role" \
        --query 'length(@)' \
        -o tsv 2>/dev/null || echo "0")
    
    [[ "$existing" -gt 0 ]]
}

grant_role() {
    local resource_id="$1"
    local principal_id="$2"
    local role="$3"
    
    log_info "Granting '$role' to principal $principal_id..."
    
    # Check if already assigned
    if check_existing_assignment "$resource_id" "$principal_id" "$role"; then
        log_warn "Role already assigned, skipping"
        return 0
    fi
    
    az role assignment create \
        --role "$role" \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type "User" \
        --scope "$resource_id" \
        --output none
    
    log_success "Role '$role' granted successfully"
}

grant_sp_role() {
    local resource_id="$1"
    local principal_id="$2"
    local role="$3"
    
    log_info "Granting '$role' to service principal $principal_id..."
    
    # Check if already assigned
    if check_existing_assignment "$resource_id" "$principal_id" "$role"; then
        log_warn "Role already assigned, skipping"
        return 0
    fi
    
    az role assignment create \
        --role "$role" \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type "ServicePrincipal" \
        --scope "$resource_id" \
        --output none
    
    log_success "Role '$role' granted successfully"
}

grant_group_role() {
    local resource_id="$1"
    local principal_id="$2"
    local role="$3"
    
    log_info "Granting '$role' to group $principal_id..."
    
    # Check if already assigned
    if check_existing_assignment "$resource_id" "$principal_id" "$role"; then
        log_warn "Role already assigned, skipping"
        return 0
    fi
    
    az role assignment create \
        --role "$role" \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type "Group" \
        --scope "$resource_id" \
        --output none
    
    log_success "Role '$role' granted successfully"
}

list_current_assignments() {
    local resource_id="$1"
    
    log_info "Current role assignments on storage account:"
    echo ""
    
    az role assignment list \
        --scope "$resource_id" \
        --query "[?contains(roleDefinitionName, 'Storage')].{Principal:principalName, Role:roleDefinitionName, PrincipalType:principalType}" \
        -o table 2>/dev/null || echo "  (none found)"
}

# ============================================================================
# Main
# ============================================================================

PRINCIPAL_TYPE=""
USE_CURRENT_USER=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--parameters)
            PARAMETER_FILE="$2"
            shift 2
            ;;
        -u|--user)
            PRINCIPAL_ID=$(get_user_id "$2")
            PRINCIPAL_TYPE="user"
            if [[ -z "$PRINCIPAL_ID" ]]; then
                log_error "User not found: $2"
                exit 1
            fi
            shift 2
            ;;
        -s|--service-principal)
            PRINCIPAL_ID="$2"
            PRINCIPAL_TYPE="sp"
            shift 2
            ;;
        -g|--group)
            PRINCIPAL_ID="$2"
            PRINCIPAL_TYPE="group"
            shift 2
            ;;
        -r|--role)
            ROLE="$2"
            shift 2
            ;;
        --current-user)
            USE_CURRENT_USER=true
            PRINCIPAL_TYPE="user"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

echo ""
echo "=========================================="
echo "  Storage Account RBAC Assignment"
echo "=========================================="
echo ""

# Check parameter file exists
if [[ ! -f "$PARAMETER_FILE" ]]; then
    log_error "Parameter file not found: $PARAMETER_FILE"
    exit 1
fi

# Get current user if requested
if [[ "$USE_CURRENT_USER" == "true" ]]; then
    PRINCIPAL_ID=$(get_current_user_id)
    if [[ -z "$PRINCIPAL_ID" ]]; then
        log_error "Could not determine current user ID"
        exit 1
    fi
    log_info "Current user ID: $PRINCIPAL_ID"
fi

# Validate we have a principal
if [[ -z "$PRINCIPAL_ID" ]]; then
    log_error "No principal specified. Use --user, --service-principal, --group, or --current-user"
    show_usage
    exit 1
fi

# Get storage account resource ID
STORAGE_NAME=$(get_storage_name)
RG_NAME=$(get_resource_group)

log_info "Storage account: $STORAGE_NAME"
log_info "Resource group: $RG_NAME"

# Check storage account exists
if ! az storage account show --name "$STORAGE_NAME" --resource-group "$RG_NAME" &> /dev/null; then
    log_error "Storage account not found: $STORAGE_NAME"
    log_error "Deploy first with ./scripts/deploy-storage-infra.sh"
    exit 1
fi

RESOURCE_ID=$(get_storage_resource_id)
log_info "Resource ID: $RESOURCE_ID"
echo ""

# Grant the role
case "$PRINCIPAL_TYPE" in
    user)
        grant_role "$RESOURCE_ID" "$PRINCIPAL_ID" "$ROLE"
        ;;
    sp)
        grant_sp_role "$RESOURCE_ID" "$PRINCIPAL_ID" "$ROLE"
        ;;
    group)
        grant_group_role "$RESOURCE_ID" "$PRINCIPAL_ID" "$ROLE"
        ;;
esac

echo ""
list_current_assignments "$RESOURCE_ID"

echo ""
log_success "RBAC assignment complete!"
echo ""
echo "Note: RBAC changes may take up to 5 minutes to propagate."
echo ""
echo "Test access with:"
echo "  az storage container list --account-name $STORAGE_NAME --auth-mode login"
echo ""
