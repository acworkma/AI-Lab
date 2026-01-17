#!/bin/bash
# ============================================================================
# Script: validate-storage-infra.sh
# Purpose: Validate deployed Private Storage Account infrastructure
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
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# ============================================================================
# Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Validate deployed Private Storage Account infrastructure.

Options:
    -p, --parameters FILE    Parameter file path (default: main.parameters.json)
    -h, --help               Show this help message

Checks performed:
    - Storage account exists and is accessible
    - RBAC-only authentication (shared keys disabled)
    - Public network access disabled
    - TLS 1.2 enforced
    - HTTPS required
    - Private endpoint configured
    - DNS zone group linked
    - Blob service configuration

EOF
}

get_storage_name() {
    local suffix=$(jq -r '.parameters.storageNameSuffix.value' "$PARAMETER_FILE")
    echo "stailab${suffix}"
}

get_resource_group() {
    echo "rg-ai-storage"
}

get_core_resource_group() {
    jq -r '.parameters.coreResourceGroupName.value' "$PARAMETER_FILE"
}

check_storage_exists() {
    log_info "Checking storage account exists..."
    
    local storage_name=$(get_storage_name)
    local rg_name=$(get_resource_group)
    
    if az storage account show --name "$storage_name" --resource-group "$rg_name" &> /dev/null; then
        log_success "Storage account exists: $storage_name"
        return 0
    else
        log_error "Storage account not found: $storage_name in $rg_name"
        return 1
    fi
}

check_security_settings() {
    log_info "Checking security settings..."
    
    local storage_name=$(get_storage_name)
    local rg_name=$(get_resource_group)
    
    local account=$(az storage account show --name "$storage_name" --resource-group "$rg_name" -o json)
    
    # Check shared key access
    local shared_key=$(echo "$account" | jq -r '.allowSharedKeyAccess')
    if [[ "$shared_key" == "false" ]]; then
        log_success "Shared key access: Disabled"
    else
        log_error "Shared key access: Enabled (should be disabled for RBAC-only)"
    fi
    
    # Check public network access
    local public_access=$(echo "$account" | jq -r '.publicNetworkAccess')
    if [[ "$public_access" == "Disabled" ]]; then
        log_success "Public network access: Disabled"
    else
        log_error "Public network access: $public_access (should be Disabled)"
    fi
    
    # Check TLS version
    local tls_version=$(echo "$account" | jq -r '.minimumTlsVersion')
    if [[ "$tls_version" == "TLS1_2" ]]; then
        log_success "Minimum TLS version: TLS1_2"
    else
        log_error "Minimum TLS version: $tls_version (should be TLS1_2)"
    fi
    
    # Check HTTPS required (deprecated property - defaults to true in newer API versions)
    local https_only=$(echo "$account" | jq -r '.supportsHttpsTrafficOnly // "true"')
    if [[ "$https_only" == "true" ]] || [[ "$https_only" == "null" ]]; then
        log_success "HTTPS traffic only: Enabled (default)"
    else
        log_error "HTTPS traffic only: Disabled (should be enabled)"
    fi
    
    # Check infrastructure encryption
    local infra_encryption=$(echo "$account" | jq -r '.encryption.requireInfrastructureEncryption')
    if [[ "$infra_encryption" == "true" ]]; then
        log_success "Infrastructure encryption: Enabled"
    else
        log_warn "Infrastructure encryption: $infra_encryption (recommended: true)"
    fi
}

check_blob_service() {
    log_info "Checking blob service configuration..."
    
    local storage_name=$(get_storage_name)
    local rg_name=$(get_resource_group)
    
    local blob_service=$(az storage account blob-service-properties show \
        --account-name "$storage_name" \
        --resource-group "$rg_name" \
        -o json 2>/dev/null || echo '{}')
    
    if [[ "$blob_service" != "{}" ]]; then
        # Check soft delete for blobs
        local blob_soft_delete=$(echo "$blob_service" | jq -r '.deleteRetentionPolicy.enabled')
        local blob_retention=$(echo "$blob_service" | jq -r '.deleteRetentionPolicy.days')
        if [[ "$blob_soft_delete" == "true" ]]; then
            log_success "Blob soft delete: Enabled (${blob_retention} days)"
        else
            log_warn "Blob soft delete: Disabled (recommended: enabled)"
        fi
        
        # Check soft delete for containers
        local container_soft_delete=$(echo "$blob_service" | jq -r '.containerDeleteRetentionPolicy.enabled')
        local container_retention=$(echo "$blob_service" | jq -r '.containerDeleteRetentionPolicy.days')
        if [[ "$container_soft_delete" == "true" ]]; then
            log_success "Container soft delete: Enabled (${container_retention} days)"
        else
            log_warn "Container soft delete: Disabled (recommended: enabled)"
        fi
        
        # Check versioning
        local versioning=$(echo "$blob_service" | jq -r '.isVersioningEnabled')
        if [[ "$versioning" == "true" ]]; then
            log_success "Blob versioning: Enabled"
        else
            log_warn "Blob versioning: Disabled (optional)"
        fi
    else
        log_warn "Unable to retrieve blob service properties"
    fi
}

check_private_endpoint() {
    log_info "Checking private endpoint configuration..."
    
    local storage_name=$(get_storage_name)
    local rg_name=$(get_resource_group)
    
    # Get private endpoint connections
    local pe_connections=$(az storage account show \
        --name "$storage_name" \
        --resource-group "$rg_name" \
        --query 'privateEndpointConnections' \
        -o json)
    
    local pe_count=$(echo "$pe_connections" | jq 'length')
    
    if [[ "$pe_count" -gt 0 ]]; then
        log_success "Private endpoint connections: $pe_count"
        
        # Check connection status
        local status=$(echo "$pe_connections" | jq -r '.[0].privateLinkServiceConnectionState.status')
        if [[ "$status" == "Approved" ]]; then
            log_success "Private endpoint status: Approved"
        else
            log_error "Private endpoint status: $status (should be Approved)"
        fi
    else
        log_error "No private endpoint connections found"
    fi
    
    # Check for the private endpoint resource
    local pe_name="${storage_name}-pe"
    if az network private-endpoint show --name "$pe_name" --resource-group "$rg_name" &> /dev/null; then
        log_success "Private endpoint exists: $pe_name"
        
        # Get private IP via network interface
        local nic_id=$(az network private-endpoint show \
            --name "$pe_name" \
            --resource-group "$rg_name" \
            --query 'networkInterfaces[0].id' \
            -o tsv)
        
        local private_ip=""
        if [[ -n "$nic_id" ]]; then
            private_ip=$(az network nic show --ids "$nic_id" --query 'ipConfigurations[0].privateIPAddress' -o tsv 2>/dev/null)
        fi
        
        if [[ -n "$private_ip" && "$private_ip" != "null" ]]; then
            log_success "Private IP assigned: $private_ip"
        else
            log_error "No private IP assigned to endpoint"
        fi
    else
        log_error "Private endpoint not found: $pe_name"
    fi
}

check_dns_zone_group() {
    log_info "Checking DNS zone group configuration..."
    
    local storage_name=$(get_storage_name)
    local rg_name=$(get_resource_group)
    local core_rg=$(get_core_resource_group)
    local pe_name="${storage_name}-pe"
    
    # Check DNS zone group exists
    local dns_zone_group=$(az network private-endpoint dns-zone-group list \
        --endpoint-name "$pe_name" \
        --resource-group "$rg_name" \
        -o json 2>/dev/null || echo '[]')
    
    local dzg_count=$(echo "$dns_zone_group" | jq 'length')
    
    if [[ "$dzg_count" -gt 0 ]]; then
        log_success "DNS zone group configured"
        
        # Verify linked to correct zone
        local linked_zone=$(echo "$dns_zone_group" | jq -r '.[0].privateDnsZoneConfigs[0].privateDnsZoneId')
        
        if [[ "$linked_zone" == *"privatelink.blob.core.windows.net"* ]]; then
            log_success "Linked to blob private DNS zone"
        else
            log_error "DNS zone group not linked to blob zone"
        fi
    else
        log_error "No DNS zone group configured"
    fi
    
    # Check the DNS zone exists in core RG
    if az network private-dns zone show \
        --resource-group "$core_rg" \
        --name "privatelink.blob.core.windows.net" &> /dev/null; then
        log_success "Private DNS zone exists in $core_rg"
    else
        log_error "Private DNS zone not found in $core_rg"
    fi
}

check_network_rules() {
    log_info "Checking network rules..."
    
    local storage_name=$(get_storage_name)
    local rg_name=$(get_resource_group)
    
    local network_rules=$(az storage account show \
        --name "$storage_name" \
        --resource-group "$rg_name" \
        --query 'networkRuleSet' \
        -o json)
    
    # Check default action
    local default_action=$(echo "$network_rules" | jq -r '.defaultAction')
    if [[ "$default_action" == "Deny" ]]; then
        log_success "Network default action: Deny"
    else
        log_error "Network default action: $default_action (should be Deny)"
    fi
    
    # Check bypass settings
    local bypass=$(echo "$network_rules" | jq -r '.bypass')
    log_info "Network bypass: $bypass"
}

check_resource_tags() {
    log_info "Checking resource tags..."
    
    local storage_name=$(get_storage_name)
    local rg_name=$(get_resource_group)
    
    local tags=$(az storage account show \
        --name "$storage_name" \
        --resource-group "$rg_name" \
        --query 'tags' \
        -o json)
    
    if [[ "$tags" != "null" && "$tags" != "{}" ]]; then
        local project_tag=$(echo "$tags" | jq -r '.Project // empty')
        local env_tag=$(echo "$tags" | jq -r '.Environment // empty')
        
        if [[ -n "$project_tag" ]]; then
            log_success "Project tag: $project_tag"
        else
            log_warn "Missing 'Project' tag"
        fi
        
        if [[ -n "$env_tag" ]]; then
            log_success "Environment tag: $env_tag"
        else
            log_warn "Missing 'Environment' tag"
        fi
    else
        log_warn "No tags configured"
    fi
}

# ============================================================================
# Main
# ============================================================================

# Parse arguments
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
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

echo ""
echo "=========================================="
echo "  Storage Infrastructure Validation"
echo "=========================================="
echo ""

# Check parameter file exists
if [[ ! -f "$PARAMETER_FILE" ]]; then
    log_error "Parameter file not found: $PARAMETER_FILE"
    exit 1
fi

# Run validation checks
if ! check_storage_exists; then
    log_error "Storage account not found. Deploy first with ./scripts/deploy-storage-infra.sh"
    exit 1
fi

echo ""
check_security_settings
echo ""
check_blob_service
echo ""
check_private_endpoint
echo ""
check_dns_zone_group
echo ""
check_network_rules
echo ""
check_resource_tags

# Summary
echo ""
echo "=========================================="
echo "         Validation Summary"
echo "=========================================="
echo "Errors:   $VALIDATION_ERRORS"
echo "Warnings: $VALIDATION_WARNINGS"
echo "=========================================="

if [[ $VALIDATION_ERRORS -gt 0 ]]; then
    log_error "Validation failed with $VALIDATION_ERRORS error(s)"
    exit 1
else
    if [[ $VALIDATION_WARNINGS -gt 0 ]]; then
        log_warn "Validation passed with $VALIDATION_WARNINGS warning(s)"
    else
        log_success "All validations passed!"
    fi
    exit 0
fi
