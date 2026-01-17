#!/bin/bash
# ============================================================================
# Script: validate-storage-infra-dns.sh
# Purpose: Validate DNS resolution for Private Storage Account
# Feature: 009-private-storage
# Requires: VPN connection to resolve private endpoints
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
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Validate DNS resolution for Private Storage Account.
Requires VPN connection to resolve private endpoints.

Options:
    -p, --parameters FILE    Parameter file path (default: main.parameters.json)
    -h, --help               Show this help message

Checks performed:
    - Blob endpoint DNS resolution
    - Private IP verification (10.x.x.x range)
    - Azure Private DNS zone record verification
    - Connectivity test via HTTPS

Prerequisites:
    - VPN connected to Azure Virtual WAN
    - Storage account deployed

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

check_vpn_connectivity() {
    log_info "Checking VPN connectivity..."
    
    # Check for VPN-like interfaces
    if ip addr show 2>/dev/null | grep -qE 'utun|ppp|tun|wg|vpn'; then
        log_success "VPN interface detected"
        return 0
    fi
    
    # Alternative: check if we can reach the private network
    # 10.1.0.0/16 is the expected VNet range
    if ping -c 1 -W 2 10.1.0.1 &>/dev/null 2>&1; then
        log_success "Private network reachable"
        return 0
    fi
    
    log_warn "VPN connection not detected (may affect DNS resolution)"
    log_warn "Connect to VPN and retry for accurate private DNS testing"
    # Continue anyway - we can still check Azure DNS records
    return 0
}

resolve_dns() {
    local hostname="$1"
    local ip=""
    
    # Try multiple resolution methods
    if command -v nslookup &> /dev/null; then
        ip=$(nslookup "$hostname" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | head -1 | awk '{print $2}')
    fi
    
    if [[ -z "$ip" ]] && command -v dig &> /dev/null; then
        ip=$(dig +short "$hostname" 2>/dev/null | head -1)
    fi
    
    if [[ -z "$ip" ]] && command -v host &> /dev/null; then
        ip=$(host "$hostname" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
    fi
    
    if [[ -z "$ip" ]]; then
        ip=$(getent hosts "$hostname" 2>/dev/null | awk '{print $1}' | head -1)
    fi
    
    echo "$ip"
}

check_blob_dns() {
    log_info "Checking blob endpoint DNS resolution..."
    
    local storage_name=$(get_storage_name)
    local blob_fqdn="${storage_name}.blob.core.windows.net"
    
    log_info "Resolving: $blob_fqdn"
    
    local resolved_ip=$(resolve_dns "$blob_fqdn")
    
    if [[ -z "$resolved_ip" ]]; then
        log_error "Failed to resolve $blob_fqdn"
        return 1
    fi
    
    log_info "Resolved to: $resolved_ip"
    
    # Check if it's a private IP (10.x.x.x or 172.16-31.x.x or 192.168.x.x)
    if [[ "$resolved_ip" =~ ^10\. ]] || \
       [[ "$resolved_ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
       [[ "$resolved_ip" =~ ^192\.168\. ]]; then
        log_success "DNS resolves to private IP: $resolved_ip"
        return 0
    else
        log_warn "DNS resolves to public IP: $resolved_ip"
        log_warn "Private DNS may not be working (ensure VPN is connected)"
        return 1
    fi
}

check_azure_dns_record() {
    log_info "Checking Azure Private DNS zone record..."
    
    local storage_name=$(get_storage_name)
    local core_rg=$(get_core_resource_group)
    
    # Check for A record in private DNS zone
    local dns_record=$(az network private-dns record-set a list \
        --resource-group "$core_rg" \
        --zone-name "privatelink.blob.core.windows.net" \
        --query "[?name=='$storage_name']" \
        -o json 2>/dev/null || echo '[]')
    
    local record_count=$(echo "$dns_record" | jq 'length')
    
    if [[ "$record_count" -gt 0 ]]; then
        local record_ip=$(echo "$dns_record" | jq -r '.[0].aRecords[0].ipv4Address')
        log_success "Private DNS A record exists: $storage_name -> $record_ip"
        return 0
    else
        log_error "No A record found for $storage_name in privatelink.blob.core.windows.net"
        return 1
    fi
}

check_private_endpoint_ip() {
    log_info "Checking private endpoint IP assignment..."
    
    local storage_name=$(get_storage_name)
    local rg_name=$(get_resource_group)
    local pe_name="${storage_name}-pe"
    
    # Get private IP via network interface
    local nic_id=$(az network private-endpoint show \
        --name "$pe_name" \
        --resource-group "$rg_name" \
        --query 'networkInterfaces[0].id' \
        -o tsv 2>/dev/null)
    
    local private_ip=""
    if [[ -n "$nic_id" ]]; then
        private_ip=$(az network nic show --ids "$nic_id" --query 'ipConfigurations[0].privateIPAddress' -o tsv 2>/dev/null)
    fi
    
    if [[ -n "$private_ip" && "$private_ip" != "null" ]]; then
        log_success "Private endpoint IP: $private_ip"
        
        # Verify it matches DNS resolution
        local blob_fqdn="${storage_name}.blob.core.windows.net"
        local resolved_ip=$(resolve_dns "$blob_fqdn")
        
        if [[ "$resolved_ip" == "$private_ip" ]]; then
            log_success "DNS resolution matches private endpoint IP"
        else
            log_warn "DNS mismatch: resolved=$resolved_ip, expected=$private_ip"
        fi
        return 0
    else
        log_error "No private IP assigned to endpoint"
        return 1
    fi
}

check_https_connectivity() {
    log_info "Checking HTTPS connectivity..."
    
    local storage_name=$(get_storage_name)
    local blob_endpoint="https://${storage_name}.blob.core.windows.net"
    
    # Use curl to check connectivity (will get 403 or auth error, but confirms TLS works)
    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$blob_endpoint/" 2>/dev/null || echo "000")
    
    if [[ "$http_code" == "000" ]]; then
        log_error "Cannot connect to $blob_endpoint (timeout or network error)"
        log_warn "Ensure VPN is connected for private endpoint access"
        return 1
    elif [[ "$http_code" == "403" || "$http_code" == "400" || "$http_code" == "409" ]]; then
        # 403/400/409 means we reached the endpoint but auth was required - that's expected
        log_success "HTTPS connectivity verified (HTTP $http_code - auth required as expected)"
        return 0
    else
        log_info "HTTPS response code: $http_code"
        log_success "HTTPS connectivity working"
        return 0
    fi
}

check_privatelink_cname() {
    log_info "Checking privatelink CNAME chain..."
    
    local storage_name=$(get_storage_name)
    local blob_fqdn="${storage_name}.blob.core.windows.net"
    local privatelink_fqdn="${storage_name}.privatelink.blob.core.windows.net"
    
    if command -v nslookup &> /dev/null; then
        # Check if blob FQDN has CNAME to privatelink
        local cname_result=$(nslookup "$blob_fqdn" 2>/dev/null | grep -i "canonical name" || true)
        
        if [[ -n "$cname_result" ]] && [[ "$cname_result" == *"privatelink"* ]]; then
            log_success "CNAME chain includes privatelink"
        else
            log_info "CNAME chain may be configured differently"
        fi
    else
        log_info "nslookup not available, skipping CNAME check"
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
echo "  Storage DNS Resolution Validation"
echo "=========================================="
echo ""

# Check parameter file exists
if [[ ! -f "$PARAMETER_FILE" ]]; then
    log_error "Parameter file not found: $PARAMETER_FILE"
    exit 1
fi

# Display target
STORAGE_NAME=$(get_storage_name)
log_info "Target storage account: $STORAGE_NAME"
echo ""

# Run checks
check_vpn_connectivity
echo ""

check_azure_dns_record
echo ""

check_private_endpoint_ip
echo ""

check_blob_dns
echo ""

check_privatelink_cname
echo ""

check_https_connectivity

# Summary
echo ""
echo "=========================================="
echo "         DNS Validation Complete"
echo "=========================================="
echo ""
echo "Storage Account: $STORAGE_NAME"
echo "Blob Endpoint:   https://${STORAGE_NAME}.blob.core.windows.net"
echo ""

log_success "DNS validation complete!"
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/grant-storage-infra-roles.sh to assign RBAC"
echo "  2. Test blob operations with ./scripts/storage-ops.sh"
echo ""
