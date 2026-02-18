#!/usr/bin/env bash
#
# validate-aks-dns.sh - Validate AKS API Server DNS Resolution
#
# Purpose: Verify private DNS resolution for AKS API server endpoint
#
# Usage: ./scripts/validate-aks-dns.sh [--cluster <name>]
#
# Prerequisites:
# - VPN connection established
# - AKS cluster deployed
#

set -euo pipefail

# Default values
RESOURCE_GROUP="rg-ai-aks"
CLUSTER_NAME="aks-ai-lab"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo ""
echo "=========================================="
echo "  AKS DNS Validation"
echo "=========================================="
echo ""

# Check VPN connection
log_info "Checking VPN connection..."
if ip route 2>/dev/null | grep -qE "172\\.16\\.|10\\.0\\." ; then
    log_success "VPN routes detected"
else
    log_error "No VPN routes detected - DNS resolution will likely fail"
    log_info "Connect to VPN first and retry"
    exit 1
fi

# Get cluster FQDN
log_info "Getting AKS API server FQDN..."
FQDN=$(az aks show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --query "privateFqdn" \
    -o tsv 2>/dev/null)

if [ -z "$FQDN" ]; then
    log_error "Could not get API server FQDN. Is the cluster deployed?"
    exit 1
fi

log_info "API Server FQDN: $FQDN"

# DNS Resolution test
log_info "Testing DNS resolution..."

start_time=$(date +%s%N)
if resolved_ip=$(nslookup "$FQDN" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1); then
    end_time=$(date +%s%N)
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    if [ -n "$resolved_ip" ]; then
        log_success "DNS resolution successful"
        log_info "  FQDN: $FQDN"
        log_info "  IP: $resolved_ip"
        log_info "  Resolution time: ${duration_ms}ms"
        
        # Check if private IP
        if [[ "$resolved_ip" =~ ^10\. ]] || [[ "$resolved_ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] || [[ "$resolved_ip" =~ ^192\.168\. ]]; then
            log_success "Resolved to private IP address"
        else
            log_warning "IP does not appear to be private: $resolved_ip"
        fi
        
        # Performance check
        if [ "$duration_ms" -lt 100 ]; then
            log_success "Resolution time under 100ms target"
        else
            log_warning "Resolution time exceeds 100ms target"
        fi
    else
        log_error "DNS resolved but no IP address found"
        exit 1
    fi
else
    log_error "DNS resolution failed for: $FQDN"
    log_info "Possible causes:"
    log_info "  - VPN not connected"
    log_info "  - Private DNS zone not linked to VNet"
    log_info "  - DNS resolver not configured"
    exit 1
fi

# Try dig if available for more details
if command -v dig &> /dev/null; then
    echo ""
    log_info "Detailed DNS query (dig):"
    dig +short "$FQDN" 2>/dev/null || true
fi

echo ""
log_success "AKS DNS validation complete!"
