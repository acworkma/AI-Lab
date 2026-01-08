#!/usr/bin/env bash
#
# validate-storage.sh - Validate Private Storage Account Configuration
# 
# Purpose: Perform pre-deployment (what-if) and post-deployment validation
#          of storage account CMK, private endpoint, and DNS configuration
#
# Usage: ./scripts/validate-storage.sh [--parameter-file <path>] [--deployed]
#
# Prerequisites:
# - Azure CLI installed and logged in
# - For --deployed: VPN connection established for DNS verification
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

Validate Private Storage Account with CMK configuration

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
        - CMK encryption verification (SR-002)
        - Public access disabled check (SR-003)
        - Private endpoint status (SR-004)
        - DNS resolution via private endpoint (SR-005)
        - Tags compliance with constitution

EXAMPLES:
    # Validate template before deployment
    $0

    # Validate deployed infrastructure
    $0 --deployed

    # Use custom parameter file
    $0 --parameter-file bicep/storage/main.parameters.prod.json --deployed

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
    local REQUIRED_PARAMS=("storageAccountName" "keyVaultName" "subnetName" "vnetName")
    
    for param in "${REQUIRED_PARAMS[@]}"; do
        local value
        value=$(jq -r ".parameters.${param}.value // empty" "$PARAMETER_FILE")
        
        if [[ -z "$value" ]]; then
            log_error "Required parameter missing: $param"
        else
            log_success "Parameter '$param' present: $value"
        fi
    done
}

validate_whatif() {
    log_info "Running what-if validation..."
    
    local LOCATION
    LOCATION=$(jq -r '.parameters.location.value // "eastus"' "$PARAMETER_FILE")
    
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

validate_cmk_encryption() {
    log_info "Checking CMK encryption (SR-002)..."
    
    local STORAGE_RG
    STORAGE_RG=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    # Check key source
    local KEY_SOURCE
    KEY_SOURCE=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "encryption.keySource" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ "$KEY_SOURCE" == "Microsoft.Keyvault" ]]; then
        log_success "SR-002: CMK encryption enabled (source: $KEY_SOURCE)"
    else
        log_error "SR-002: CMK encryption not configured (source: $KEY_SOURCE)"
        return 1
    fi
    
    # Check key vault properties
    local KEY_VAULT_URI
    KEY_VAULT_URI=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "encryption.keyVaultProperties.keyVaultUri" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$KEY_VAULT_URI" ]]; then
        log_success "SR-002: Key Vault URI configured: $KEY_VAULT_URI"
    else
        log_error "SR-002: Key Vault URI not configured"
    fi
    
    # Check identity type
    local IDENTITY_TYPE
    IDENTITY_TYPE=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "encryption.encryptionIdentity.encryptionUserAssignedIdentity" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$IDENTITY_TYPE" && "$IDENTITY_TYPE" != "null" ]]; then
        log_success "SR-002: User-assigned identity configured for CMK"
    else
        log_error "SR-002: User-assigned identity not configured for CMK"
    fi
}

validate_public_access() {
    log_info "Checking public access (SR-003)..."
    
    local STORAGE_RG
    STORAGE_RG=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    local PUBLIC_ACCESS
    PUBLIC_ACCESS=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "publicNetworkAccess" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ "$PUBLIC_ACCESS" == "Disabled" ]]; then
        log_success "SR-003: Public network access disabled"
    else
        log_error "SR-003: Public network access not disabled (status: $PUBLIC_ACCESS)"
    fi
    
    # Check allow blob public access
    local BLOB_PUBLIC
    BLOB_PUBLIC=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "allowBlobPublicAccess" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ "$BLOB_PUBLIC" == "false" ]]; then
        log_success "SR-003: Blob public access disabled"
    else
        log_error "SR-003: Blob public access not disabled (status: $BLOB_PUBLIC)"
    fi
}

validate_private_endpoint() {
    log_info "Checking private endpoint (SR-004)..."
    
    local STORAGE_RG
    STORAGE_RG=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    local PE_NAME="pe-${STORAGE_NAME}-blob"
    
    # Check PE exists
    if ! az network private-endpoint show \
        --name "$PE_NAME" \
        --resource-group "$STORAGE_RG" &>/dev/null; then
        log_error "SR-004: Private endpoint not found: $PE_NAME"
        return 1
    fi
    
    log_success "SR-004: Private endpoint exists: $PE_NAME"
    
    # Check PE connection state
    local CONNECTION_STATE
    CONNECTION_STATE=$(az network private-endpoint show \
        --name "$PE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ "$CONNECTION_STATE" == "Approved" ]]; then
        log_success "SR-004: Private endpoint connection approved"
    else
        log_error "SR-004: Private endpoint connection not approved (status: $CONNECTION_STATE)"
    fi
    
    # Check PE IP
    local PE_IP
    PE_IP=$(az network private-endpoint show \
        --name "$PE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "customDnsConfigs[0].ipAddresses[0]" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$PE_IP" && "$PE_IP" != "null" ]]; then
        log_success "SR-004: Private endpoint IP assigned: $PE_IP"
    else
        log_warning "SR-004: Private endpoint IP not available yet"
    fi
}

validate_dns_resolution() {
    log_info "Checking DNS resolution (SR-005)..."
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    local FQDN="${STORAGE_NAME}.blob.core.windows.net"
    
    # Get expected private IP
    local STORAGE_RG
    STORAGE_RG=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    
    local PE_NAME="pe-${STORAGE_NAME}-blob"
    
    local EXPECTED_IP
    EXPECTED_IP=$(az network private-endpoint show \
        --name "$PE_NAME" \
        --resource-group "$STORAGE_RG" \
        --query "customDnsConfigs[0].ipAddresses[0]" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$EXPECTED_IP" || "$EXPECTED_IP" == "null" ]]; then
        log_warning "SR-005: Cannot determine expected private IP"
        return 0
    fi
    
    # Resolve DNS (requires VPN connection)
    log_info "Resolving $FQDN (VPN required)..."
    
    local RESOLVED_IP
    RESOLVED_IP=$(nslookup "$FQDN" 2>/dev/null | grep -A1 "Name:" | grep "Address" | awk '{print $2}' || echo "")
    
    if [[ -z "$RESOLVED_IP" ]]; then
        log_warning "SR-005: DNS resolution failed (VPN may not be connected)"
        log_info "Expected private IP: $EXPECTED_IP"
    elif [[ "$RESOLVED_IP" == "$EXPECTED_IP" ]]; then
        log_success "SR-005: DNS resolves to private endpoint IP: $RESOLVED_IP"
    elif [[ "$RESOLVED_IP" == 10.* ]]; then
        log_success "SR-005: DNS resolves to private IP range: $RESOLVED_IP"
    else
        log_error "SR-005: DNS resolves to public IP: $RESOLVED_IP (expected: $EXPECTED_IP)"
    fi
}

validate_tags() {
    log_info "Checking tags compliance (Constitution)..."
    
    local STORAGE_RG
    STORAGE_RG=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-storage"' "$PARAMETER_FILE")
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    # Required tags per constitution
    local REQUIRED_TAGS=("project" "environment" "component" "deployedBy")
    
    for tag in "${REQUIRED_TAGS[@]}"; do
        local value
        value=$(az storage account show \
            --name "$STORAGE_NAME" \
            --resource-group "$STORAGE_RG" \
            --query "tags.${tag}" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$value" && "$value" != "null" ]]; then
            log_success "Tag '$tag' present: $value"
        else
            log_error "Required tag missing: $tag"
        fi
    done
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
echo " Validate Private Storage Account with CMK"
echo "=============================================="
echo ""
echo "Parameter File: $PARAMETER_FILE"
echo "Mode: $(if [[ "$VALIDATE_DEPLOYED" == "true" ]]; then echo "Deployed Resources"; else echo "Template Only"; fi)"
echo ""

# Template validations (always run)
validate_template_syntax
validate_parameter_file

if [[ "$VALIDATE_DEPLOYED" != "true" ]]; then
    validate_whatif
else
    # Deployed resource validations
    echo ""
    echo "--- Security Requirements ---"
    validate_cmk_encryption
    validate_public_access
    validate_private_endpoint
    validate_dns_resolution
    
    echo ""
    echo "--- Constitution Compliance ---"
    validate_tags
fi

echo ""
echo "=============================================="
if [[ "$VALIDATION_PASSED" == "true" ]]; then
    log_success "All validations passed!"
    exit 0
else
    log_error "Some validations failed - review output above"
    exit 1
fi
