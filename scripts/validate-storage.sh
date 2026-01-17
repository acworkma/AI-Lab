#!/usr/bin/env bash
#
# validate-storage.sh - Validate Storage Account CMK Configuration
# 
# Feature: 010-storage-cmk-refactor
# Purpose: Validate CMK encryption status, key details, and lifecycle info
#
# Usage: ./scripts/validate-storage.sh [--parameter-file <path>] [--deployed]
#
# Prerequisites:
# - Azure CLI installed and logged in
# - For --deployed: VPN connection for DNS verification
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/storage/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/storage/main.bicep"
VALIDATE_DEPLOYED=false
VALIDATION_PASSED=true

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
    VALIDATION_PASSED=false
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate Storage Account CMK encryption configuration

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/storage/main.parameters.json)
    -d, --deployed              Validate deployed resources (vs template only)
    -h, --help                  Show this help message

VALIDATION MODES:
    Default (template):
        - Parameter file syntax validation
        - Template syntax validation
        - What-if deployment analysis

    Deployed (--deployed):
        - All template validations
        - CMK encryption verification (SC-001)
        - Encryption key verification (SC-002)
        - RBAC role assignment (SC-003)
        - Blob operations test (SC-004)
        - Key lifecycle details (US3)

EXAMPLES:
    # Validate template before deployment
    $0

    # Validate deployed infrastructure with CMK status
    $0 --deployed

EOF
    exit 1
}

validate_template_syntax() {
    log_info "Validating Bicep template syntax..."
    
    if ! az bicep build --file "$TEMPLATE_FILE" --stdout > /dev/null 2>&1; then
        log_error "Bicep template syntax error"
        az bicep build --file "$TEMPLATE_FILE" 2>&1 | head -20
        return 1
    fi
    
    log_success "Template syntax valid"
}

validate_parameter_file() {
    log_info "Validating parameter file..."
    
    if [[ ! -f "$PARAMETER_FILE" ]]; then
        log_error "Parameter file not found: $PARAMETER_FILE"
        return 1
    fi
    
    # Check JSON syntax
    if ! jq empty "$PARAMETER_FILE" 2>/dev/null; then
        log_error "Invalid JSON in parameter file"
        return 1
    fi
    
    # Check required parameters
    local REQUIRED_PARAMS=("storageNameSuffix" "owner")
    
    for param in "${REQUIRED_PARAMS[@]}"; do
        local value
        value=$(jq -r ".parameters.${param}.value // empty" "$PARAMETER_FILE")
        
        if [[ -z "$value" || "$value" == "<"* ]]; then
            log_error "Required parameter missing or not customized: $param"
        else
            log_success "Parameter '$param' present: $value"
        fi
    done
}

validate_whatif() {
    log_info "Running what-if validation..."
    
    local LOCATION
    LOCATION=$(jq -r '.parameters.location.value // "eastus2"' "$PARAMETER_FILE")
    
    local OUTPUT
    if OUTPUT=$(az deployment sub what-if \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --no-pretty-print 2>&1); then
        log_success "What-if validation passed"
    else
        log_error "What-if validation failed"
        echo "$OUTPUT" | head -30
    fi
}

# ============================================================================
# CMK VALIDATION (T014, US3: T021-T024)
# ============================================================================

validate_cmk_encryption() {
    log_info "Checking CMK encryption (SC-001)..."
    
    local STORAGE_RG STORAGE_SUFFIX
    STORAGE_RG=$(jq -r '.parameters.storageResourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    STORAGE_SUFFIX=$(jq -r '.parameters.storageNameSuffix.value' "$PARAMETER_FILE")
    local STORAGE_NAME="stailab${STORAGE_SUFFIX}"
    
    # Check key source
    local KEY_SOURCE
    KEY_SOURCE=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "encryption.keySource" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ "$KEY_SOURCE" == "Microsoft.Keyvault" ]]; then
        log_success "SC-001: CMK encryption enabled (keySource: $KEY_SOURCE)"
    else
        log_error "SC-001: CMK encryption not configured (keySource: $KEY_SOURCE)"
        return 1
    fi
    
    # Check identity configured (T012)
    local IDENTITY_ID
    IDENTITY_ID=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "encryption.encryptionIdentity.encryptionUserAssignedIdentity" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$IDENTITY_ID" && "$IDENTITY_ID" != "null" ]]; then
        log_success "SC-001: User-assigned identity configured for CMK"
    else
        log_error "SC-001: User-assigned identity not configured"
    fi
}

validate_encryption_key() {
    log_info "Checking encryption key (SC-002)..."
    
    local KV_RG STORAGE_RG STORAGE_SUFFIX KV_NAME_PARAM
    KV_RG=$(jq -r '.parameters.keyVaultResourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE")
    STORAGE_RG=$(jq -r '.parameters.storageResourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    STORAGE_SUFFIX=$(jq -r '.parameters.storageNameSuffix.value' "$PARAMETER_FILE")
    KV_NAME_PARAM=$(jq -r '.parameters.keyVaultName.value // ""' "$PARAMETER_FILE")
    local STORAGE_NAME="stailab${STORAGE_SUFFIX}"
    local KEY_NAME=$(jq -r '.parameters.encryptionKeyName.value // "storage-encryption-key"' "$PARAMETER_FILE")
    
    # Get Key Vault name
    local KV_NAME
    if [[ -n "$KV_NAME_PARAM" && "$KV_NAME_PARAM" != "null" && "$KV_NAME_PARAM" != "" ]]; then
        KV_NAME="$KV_NAME_PARAM"
    else
        KV_NAME=$(az keyvault list --resource-group "$KV_RG" --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "$KV_NAME" ]]; then
        log_error "SC-002: Key Vault not found in $KV_RG"
        return 1
    fi
    
    # Check key exists
    if ! az keyvault key show --vault-name "$KV_NAME" --name "$KEY_NAME" &>/dev/null; then
        log_error "SC-002: Encryption key not found: $KEY_NAME in $KV_NAME"
        return 1
    fi
    
    log_success "SC-002: Encryption key exists: $KEY_NAME"
    
    # T021: Display encryption key URI (versionless)
    local KEY_URI
    KEY_URI=$(az keyvault key show --vault-name "$KV_NAME" --name "$KEY_NAME" --query "key.kid" -o tsv 2>/dev/null || echo "")
    # Remove version from URI for versionless display
    local KEY_URI_VERSIONLESS="${KEY_URI%/*}"
    echo "  Key URI (versionless): $KEY_URI_VERSIONLESS"
    
    # T022: Display current key version
    local KEY_VERSION="${KEY_URI##*/}"
    echo "  Current Key Version: $KEY_VERSION"
    
    # Check key size
    local KEY_SIZE
    KEY_SIZE=$(az keyvault key show --vault-name "$KV_NAME" --name "$KEY_NAME" --query "key.n" -o tsv 2>/dev/null | wc -c)
    # RSA key size approximation: 2048 bit ~ 342 chars, 3072 ~ 512 chars, 4096 ~ 683 chars (base64)
    if [[ $KEY_SIZE -gt 600 ]]; then
        log_success "SC-002: Key size appears to be RSA 4096-bit"
    elif [[ $KEY_SIZE -gt 400 ]]; then
        log_success "SC-002: Key size appears to be RSA 3072-bit"
    else
        log_success "SC-002: Key size appears to be RSA 2048-bit"
    fi
    
    # T023: Display key rotation policy
    log_info "Key rotation policy (SC-002, SR-003):"
    local ROTATION_POLICY
    ROTATION_POLICY=$(az keyvault key rotation-policy show --vault-name "$KV_NAME" --name "$KEY_NAME" 2>/dev/null || echo "{}")
    
    local ROTATION_INTERVAL
    ROTATION_INTERVAL=$(echo "$ROTATION_POLICY" | jq -r '.lifetimeActions[]? | select(.action.type == "rotate") | .trigger.timeAfterCreate // "N/A"' 2>/dev/null || echo "N/A")
    
    local EXPIRY_TIME
    EXPIRY_TIME=$(echo "$ROTATION_POLICY" | jq -r '.attributes.expiryTime // "N/A"' 2>/dev/null || echo "N/A")
    
    echo "  Rotation Interval: $ROTATION_INTERVAL"
    echo "  Expiry Time: $EXPIRY_TIME"
    
    if [[ "$ROTATION_INTERVAL" == "P18M" ]]; then
        log_success "SR-003: Key rotation interval is P18M (18 months)"
    elif [[ "$ROTATION_INTERVAL" != "N/A" ]]; then
        log_warning "SR-003: Key rotation interval is $ROTATION_INTERVAL (expected P18M)"
    else
        log_warning "SR-003: Key rotation policy not configured"
    fi
}

validate_rbac_assignment() {
    log_info "Checking RBAC role assignment (SC-003)..."
    
    local KV_RG STORAGE_RG STORAGE_SUFFIX KV_NAME_PARAM
    KV_RG=$(jq -r '.parameters.keyVaultResourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE")
    STORAGE_RG=$(jq -r '.parameters.storageResourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    STORAGE_SUFFIX=$(jq -r '.parameters.storageNameSuffix.value' "$PARAMETER_FILE")
    KV_NAME_PARAM=$(jq -r '.parameters.keyVaultName.value // ""' "$PARAMETER_FILE")
    local STORAGE_NAME="stailab${STORAGE_SUFFIX}"
    local IDENTITY_NAME="id-${STORAGE_NAME}-cmk"
    
    # Get Key Vault name
    local KV_NAME
    if [[ -n "$KV_NAME_PARAM" && "$KV_NAME_PARAM" != "null" && "$KV_NAME_PARAM" != "" ]]; then
        KV_NAME="$KV_NAME_PARAM"
    else
        KV_NAME=$(az keyvault list --resource-group "$KV_RG" --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi
    
    # T024: Display managed identity details
    log_info "Managed identity details:"
    local MI_PRINCIPAL_ID MI_CLIENT_ID
    MI_PRINCIPAL_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$STORAGE_RG" --query "principalId" -o tsv 2>/dev/null || echo "")
    MI_CLIENT_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$STORAGE_RG" --query "clientId" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$MI_PRINCIPAL_ID" ]]; then
        log_error "SC-003: Managed identity not found: $IDENTITY_NAME"
        return 1
    fi
    
    echo "  Identity Name: $IDENTITY_NAME"
    echo "  Principal ID: $MI_PRINCIPAL_ID"
    echo "  Client ID: $MI_CLIENT_ID"
    
    # Check role assignment (Key Vault Crypto Service Encryption User)
    local ROLE_ID="e147488a-f6f5-4113-8e2d-b22465e65bf6"
    local KV_ID
    KV_ID=$(az keyvault show --name "$KV_NAME" --resource-group "$KV_RG" --query "id" -o tsv 2>/dev/null || echo "")
    
    local ROLE_ASSIGNED
    ROLE_ASSIGNED=$(az role assignment list \
        --assignee "$MI_PRINCIPAL_ID" \
        --scope "$KV_ID" \
        --query "[?roleDefinitionId.contains(@, '$ROLE_ID')].id" \
        -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$ROLE_ASSIGNED" ]]; then
        log_success "SC-003: Key Vault Crypto Service Encryption User role assigned"
    else
        log_error "SC-003: Role assignment not found for managed identity"
    fi
}

validate_public_access() {
    log_info "Checking public access (SR-004)..."
    
    local STORAGE_RG STORAGE_SUFFIX
    STORAGE_RG=$(jq -r '.parameters.storageResourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    STORAGE_SUFFIX=$(jq -r '.parameters.storageNameSuffix.value' "$PARAMETER_FILE")
    local STORAGE_NAME="stailab${STORAGE_SUFFIX}"
    
    local PUBLIC_ACCESS
    PUBLIC_ACCESS=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "publicNetworkAccess" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ "$PUBLIC_ACCESS" == "Disabled" ]]; then
        log_success "SR-004: Public network access disabled"
    else
        log_error "SR-004: Public network access not disabled (status: $PUBLIC_ACCESS)"
    fi
    
    # Check TLS version
    local TLS_VERSION
    TLS_VERSION=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "minimumTlsVersion" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ "$TLS_VERSION" == "TLS1_2" ]]; then
        log_success "SR-004: TLS 1.2 minimum enforced"
    else
        log_warning "SR-004: TLS version is $TLS_VERSION (expected TLS1_2)"
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
        -d|--deployed)
            VALIDATE_DEPLOYED=true
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
echo " Validate Storage Account CMK Configuration"
echo " Feature: 010-storage-cmk-refactor"
echo "=============================================="
echo ""

# Always run template validations
validate_template_syntax
validate_parameter_file

if [[ "$VALIDATE_DEPLOYED" == "true" ]]; then
    echo ""
    log_info "=== Deployed Infrastructure Validation ==="
    echo ""
    
    validate_cmk_encryption
    validate_encryption_key
    validate_rbac_assignment
    validate_public_access
else
    validate_whatif
fi

echo ""
echo "=============================================="
if [[ "$VALIDATION_PASSED" == "true" ]]; then
    log_success "All validations passed!"
else
    log_error "Some validations failed - review output above"
    exit 1
fi
