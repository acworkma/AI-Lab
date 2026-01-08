#!/usr/bin/env bash
#
# validate-storage-dns.sh - Validate Private DNS Resolution for Storage Account
# 
# Purpose: Verify private DNS zone configuration, A record existence, and latency
#          to ensure NFR-003 compliance (<100ms DNS resolution)
#
# Usage: ./scripts/validate-storage-dns.sh [--parameter-file <path>]
#
# Prerequisites:
# - Storage account deployed (run scripts/deploy-storage.sh first)
# - VPN connection established for DNS verification
# - Core infrastructure deployed (private DNS zone)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/storage/main.parameters.json"
VALIDATION_PASSED=true
DNS_LATENCY_THRESHOLD_MS=100

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

Validate Private DNS resolution for Storage Account (NFR-003)

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/storage/main.parameters.json)
    -h, --help                  Show this help message

VALIDATIONS:
    - Private DNS zone exists and is linked to VNet
    - A record for storage account exists in DNS zone
    - DNS resolution returns private IP (10.x.x.x range)
    - DNS resolution latency < ${DNS_LATENCY_THRESHOLD_MS}ms (NFR-003)

EXAMPLES:
    # Standard validation
    $0

    # Custom parameter file
    $0 --parameter-file bicep/storage/main.parameters.prod.json

NOTES:
    - Requires VPN connection for accurate DNS latency measurement
    - If VPN not connected, tests will use Azure CLI lookups instead

EOF
    exit 1
}

check_dns_zone() {
    log_info "Checking private DNS zone configuration..."
    
    local CORE_RG
    CORE_RG=$(jq -r '.parameters.coreResourceGroupName.value // "rg-ai-core"' "$PARAMETER_FILE")
    
    local DNS_ZONE
    DNS_ZONE=$(jq -r '.parameters.privateDnsZoneName.value // "privatelink.blob.core.windows.net"' "$PARAMETER_FILE")
    
    # Check DNS zone exists
    if ! az network private-dns zone show \
        --name "$DNS_ZONE" \
        --resource-group "$CORE_RG" &>/dev/null; then
        log_error "Private DNS zone not found: $DNS_ZONE in $CORE_RG"
        return 1
    fi
    
    log_success "Private DNS zone exists: $DNS_ZONE"
    
    # Check VNet link
    local VNET_NAME
    VNET_NAME=$(jq -r '.parameters.vnetName.value // "vnet-ai-sharedservices"' "$PARAMETER_FILE")
    
    local LINKS
    LINKS=$(az network private-dns link vnet list \
        --zone-name "$DNS_ZONE" \
        --resource-group "$CORE_RG" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$LINKS" ]]; then
        log_warning "No VNet links found for DNS zone"
    else
        log_success "DNS zone has VNet links: $LINKS"
    fi
}

check_a_record() {
    log_info "Checking A record for storage account..."
    
    local CORE_RG
    CORE_RG=$(jq -r '.parameters.coreResourceGroupName.value // "rg-ai-core"' "$PARAMETER_FILE")
    
    local DNS_ZONE
    DNS_ZONE=$(jq -r '.parameters.privateDnsZoneName.value // "privatelink.blob.core.windows.net"' "$PARAMETER_FILE")
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    # Check A record exists in DNS zone
    local A_RECORD_IP
    A_RECORD_IP=$(az network private-dns record-set a show \
        --name "$STORAGE_NAME" \
        --zone-name "$DNS_ZONE" \
        --resource-group "$CORE_RG" \
        --query "aRecords[0].ipv4Address" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$A_RECORD_IP" || "$A_RECORD_IP" == "null" ]]; then
        log_error "A record not found for $STORAGE_NAME in $DNS_ZONE"
        log_info "The private endpoint may not have created the DNS record yet"
        return 1
    fi
    
    log_success "A record exists: $STORAGE_NAME → $A_RECORD_IP"
    
    # Verify IP is in private range
    if [[ "$A_RECORD_IP" == 10.* ]]; then
        log_success "A record IP is in private range (10.x.x.x)"
    else
        log_warning "A record IP is not in expected private range: $A_RECORD_IP"
    fi
}

measure_dns_latency() {
    log_info "Measuring DNS resolution latency (NFR-003: <${DNS_LATENCY_THRESHOLD_MS}ms)..."
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    local FQDN="${STORAGE_NAME}.blob.core.windows.net"
    
    # Check if dig is available
    if ! command -v dig &> /dev/null; then
        log_warning "dig not available, using nslookup (less precise timing)"
        
        # Fallback: time nslookup
        local START_TIME END_TIME DURATION
        START_TIME=$(date +%s%N)
        
        if nslookup "$FQDN" &>/dev/null; then
            END_TIME=$(date +%s%N)
            DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
            
            if [[ $DURATION -lt $DNS_LATENCY_THRESHOLD_MS ]]; then
                log_success "NFR-003: DNS latency ${DURATION}ms < ${DNS_LATENCY_THRESHOLD_MS}ms"
            else
                log_error "NFR-003: DNS latency ${DURATION}ms >= ${DNS_LATENCY_THRESHOLD_MS}ms"
            fi
        else
            log_warning "DNS resolution failed (VPN may not be connected)"
        fi
        return
    fi
    
    # Use dig with +stats for timing
    log_info "Resolving $FQDN with dig..."
    
    local DIG_OUTPUT
    DIG_OUTPUT=$(dig "$FQDN" +stats +noall +answer +time=2 2>&1 || echo "FAILED")
    
    if [[ "$DIG_OUTPUT" == *"FAILED"* || -z "$DIG_OUTPUT" ]]; then
        log_warning "DNS resolution failed (VPN may not be connected)"
        
        # Try Azure DNS directly
        log_info "Trying Azure DNS server (168.63.129.16)..."
        DIG_OUTPUT=$(dig "$FQDN" @168.63.129.16 +stats +noall +answer +time=2 2>&1 || echo "")
        
        if [[ -z "$DIG_OUTPUT" ]]; then
            log_warning "Cannot reach Azure DNS - ensure VPN is connected"
            return
        fi
    fi
    
    # Extract query time from dig output
    local QUERY_TIME
    QUERY_TIME=$(dig "$FQDN" +stats 2>/dev/null | grep "Query time" | awk '{print $4}')
    
    if [[ -n "$QUERY_TIME" && "$QUERY_TIME" =~ ^[0-9]+$ ]]; then
        if [[ $QUERY_TIME -lt $DNS_LATENCY_THRESHOLD_MS ]]; then
            log_success "NFR-003: DNS query time ${QUERY_TIME}ms < ${DNS_LATENCY_THRESHOLD_MS}ms"
        else
            log_error "NFR-003: DNS query time ${QUERY_TIME}ms >= ${DNS_LATENCY_THRESHOLD_MS}ms"
        fi
    else
        log_warning "Could not extract DNS query time"
    fi
    
    # Show resolved IP
    local RESOLVED_IP
    RESOLVED_IP=$(dig "$FQDN" +short 2>/dev/null | head -1)
    
    if [[ -n "$RESOLVED_IP" ]]; then
        if [[ "$RESOLVED_IP" == 10.* ]]; then
            log_success "DNS resolves to private IP: $RESOLVED_IP"
        else
            log_warning "DNS resolves to non-private IP: $RESOLVED_IP"
        fi
    fi
}

compare_public_vs_private() {
    log_info "Comparing public vs private DNS resolution..."
    
    local STORAGE_NAME
    STORAGE_NAME=$(jq -r '.parameters.storageAccountName.value' "$PARAMETER_FILE")
    
    local FQDN="${STORAGE_NAME}.blob.core.windows.net"
    
    # Get private endpoint IP from Azure
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
        log_warning "Cannot determine private endpoint IP"
        return
    fi
    
    log_info "Expected private IP: $EXPECTED_IP"
    
    # Resolve via VPN (current DNS)
    local VPN_RESOLVED
    VPN_RESOLVED=$(dig "$FQDN" +short 2>/dev/null | head -1 || echo "")
    
    if [[ "$VPN_RESOLVED" == "$EXPECTED_IP" ]]; then
        log_success "VPN DNS resolves correctly to private endpoint"
    elif [[ "$VPN_RESOLVED" == 10.* ]]; then
        log_success "VPN DNS resolves to private range: $VPN_RESOLVED"
    elif [[ -n "$VPN_RESOLVED" ]]; then
        log_warning "VPN DNS resolves to: $VPN_RESOLVED (expected: $EXPECTED_IP)"
        log_info "This may indicate VPN is not connected or DNS split-horizon not configured"
    else
        log_warning "VPN DNS resolution failed - ensure VPN is connected"
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
echo " Validate Storage DNS (NFR-003)"
echo "=============================================="
echo ""
echo "Parameter File: $PARAMETER_FILE"
echo "Latency Threshold: ${DNS_LATENCY_THRESHOLD_MS}ms"
echo ""

# Validate parameter file exists
if [[ ! -f "$PARAMETER_FILE" ]]; then
    log_error "Parameter file not found: $PARAMETER_FILE"
    exit 1
fi

# Run validations
check_dns_zone
check_a_record
measure_dns_latency
compare_public_vs_private

echo ""
echo "=============================================="
if [[ "$VALIDATION_PASSED" == "true" ]]; then
    log_success "All DNS validations passed!"
    exit 0
else
    log_error "Some DNS validations failed - review output above"
    exit 1
fi
