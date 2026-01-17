#!/usr/bin/env bash
#
# grant-keyvault-roles.sh - Assign Key Vault RBAC Roles
# 
# Purpose: Grant RBAC roles for Key Vault secret management
#          Supports assigning roles to users, groups, and service principals
#
# Usage: ./scripts/grant-keyvault-roles.sh --principal-id <id> --role <role-name>
#
# Available Roles:
#   - secrets-officer: Key Vault Secrets Officer (CRUD secrets)
#   - secrets-user: Key Vault Secrets User (read secrets)
#   - admin: Key Vault Administrator (full management)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/keyvault/main.parameters.json"
PRINCIPAL_ID=""
PRINCIPAL_TYPE="User"
ROLE_NAME=""

# Role Definition IDs
declare -A ROLE_IDS=(
    ["secrets-officer"]="b86a8fe4-44ce-4948-aee5-eccb2c155cd7"    # Key Vault Secrets Officer
    ["secrets-user"]="4633458b-17de-408a-b874-0445c86b69e6"       # Key Vault Secrets User
    ["admin"]="00482a5a-887f-4fb3-b363-3b7fe8e74483"              # Key Vault Administrator
    ["crypto-officer"]="14b46e9e-c2b7-41b4-b07b-48a6ebf60603"     # Key Vault Crypto Officer
    ["certificates-officer"]="a4417e6f-fecd-4de8-b567-7b0420556985" # Key Vault Certificates Officer
)

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
Usage: $0 --principal-id <id> --role <role-name> [OPTIONS]

Assign Key Vault RBAC roles to users, groups, or service principals

REQUIRED:
    --principal-id ID           Object ID of user, group, or service principal
    --role ROLE                 Role to assign (see available roles below)

OPTIONS:
    --principal-type TYPE       Type: User, Group, ServicePrincipal (default: User)
    --vault-name NAME           Key Vault name (auto-detected if not provided)
    -p, --parameter-file PATH   Path to parameter file for auto-detection
    -h, --help                  Show this help message

AVAILABLE ROLES:
    secrets-officer     Key Vault Secrets Officer (create, read, update, delete secrets)
    secrets-user        Key Vault Secrets User (read secrets only)
    admin               Key Vault Administrator (full management)
    crypto-officer      Key Vault Crypto Officer (key operations)
    certificates-officer Key Vault Certificates Officer (certificate operations)

EXAMPLES:
    # Grant secrets officer role to a user
    $0 --principal-id "00000000-0000-0000-0000-000000000000" --role secrets-officer

    # Grant secrets user role to a service principal
    $0 --principal-id "\$SP_OBJECT_ID" --role secrets-user --principal-type ServicePrincipal

    # Grant admin role to a group
    $0 --principal-id "\$GROUP_ID" --role admin --principal-type Group

HOW TO GET PRINCIPAL ID:
    # Current user
    az ad signed-in-user show --query id -o tsv

    # User by email
    az ad user show --id "user@domain.com" --query id -o tsv

    # Service principal by name
    az ad sp list --display-name "my-app" --query "[0].id" -o tsv

    # Group by name
    az ad group show --group "my-group" --query id -o tsv

EOF
    exit 1
}

get_vault_name() {
    local RG_NAME
    RG_NAME=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE")
    
    az keyvault list --resource-group "$RG_NAME" --query "[0].name" -o tsv 2>/dev/null || true
}

validate_role() {
    if [[ -z "${ROLE_IDS[$ROLE_NAME]+isset}" ]]; then
        log_error "Invalid role: $ROLE_NAME"
        echo ""
        echo "Available roles:"
        for role in "${!ROLE_IDS[@]}"; do
            echo "  - $role"
        done
        exit 1
    fi
}

assign_role() {
    local VAULT_NAME="$1"
    local ROLE_DEFINITION_ID="${ROLE_IDS[$ROLE_NAME]}"
    
    log_info "Assigning role to Key Vault..."
    echo ""
    echo "Details:"
    echo "  Key Vault:       $VAULT_NAME"
    echo "  Principal ID:    $PRINCIPAL_ID"
    echo "  Principal Type:  $PRINCIPAL_TYPE"
    echo "  Role:            $ROLE_NAME"
    echo ""
    
    # Get Key Vault resource ID
    local RG_NAME
    RG_NAME=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE")
    
    local VAULT_ID
    VAULT_ID=$(az keyvault show --name "$VAULT_NAME" --resource-group "$RG_NAME" --query id -o tsv)
    
    # Check if assignment already exists
    local EXISTING
    EXISTING=$(az role assignment list \
        --assignee "$PRINCIPAL_ID" \
        --scope "$VAULT_ID" \
        --role "$ROLE_DEFINITION_ID" \
        --query "[0].id" -o tsv 2>/dev/null || true)
    
    if [[ -n "$EXISTING" ]]; then
        log_warning "Role assignment already exists"
        return 0
    fi
    
    # Create role assignment
    if ! az role assignment create \
        --assignee-object-id "$PRINCIPAL_ID" \
        --assignee-principal-type "$PRINCIPAL_TYPE" \
        --role "$ROLE_DEFINITION_ID" \
        --scope "$VAULT_ID" \
        --output none; then
        log_error "Failed to assign role"
        return 1
    fi
    
    log_success "Role assigned successfully!"
    echo ""
    log_info "The principal can now perform ${ROLE_NAME} operations on Key Vault: $VAULT_NAME"
}

list_current_assignments() {
    local VAULT_NAME="$1"
    
    log_info "Current role assignments for Key Vault: $VAULT_NAME"
    echo ""
    
    local RG_NAME
    RG_NAME=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE")
    
    local VAULT_ID
    VAULT_ID=$(az keyvault show --name "$VAULT_NAME" --resource-group "$RG_NAME" --query id -o tsv)
    
    az role assignment list \
        --scope "$VAULT_ID" \
        --query "[].{Principal:principalName, Role:roleDefinitionName, Type:principalType}" \
        -o table
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

VAULT_NAME=""
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --principal-id)
            PRINCIPAL_ID="$2"
            shift 2
            ;;
        --role)
            ROLE_NAME="$2"
            shift 2
            ;;
        --principal-type)
            PRINCIPAL_TYPE="$2"
            shift 2
            ;;
        --vault-name)
            VAULT_NAME="$2"
            shift 2
            ;;
        -p|--parameter-file)
            PARAMETER_FILE="$2"
            shift 2
            ;;
        --list)
            LIST_ONLY=true
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
echo "Key Vault RBAC Role Assignment"
echo "============================================"
echo ""

# Check Azure CLI login
if ! az account show &> /dev/null; then
    log_error "Not logged into Azure. Run 'az login' first."
    exit 1
fi

# Get vault name if not provided
if [[ -z "$VAULT_NAME" ]]; then
    VAULT_NAME=$(get_vault_name)
    if [[ -z "$VAULT_NAME" ]]; then
        log_error "Could not detect Key Vault name. Use --vault-name option."
        exit 1
    fi
fi

# List only mode
if [[ "$LIST_ONLY" == "true" ]]; then
    list_current_assignments "$VAULT_NAME"
    exit 0
fi

# Validate required arguments
if [[ -z "$PRINCIPAL_ID" ]]; then
    log_error "Missing required argument: --principal-id"
    usage
fi

if [[ -z "$ROLE_NAME" ]]; then
    log_error "Missing required argument: --role"
    usage
fi

# Validate role
validate_role

# Assign role
assign_role "$VAULT_NAME"

echo ""
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Test secret operations:"
echo "     az keyvault secret set --vault-name $VAULT_NAME --name test-secret --value 'hello'"
echo "     az keyvault secret show --vault-name $VAULT_NAME --name test-secret"
echo ""
echo "  2. List current assignments:"
echo "     $0 --list"
echo "============================================"
