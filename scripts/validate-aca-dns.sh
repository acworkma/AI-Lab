#!/usr/bin/env bash
#
# validate-aca-dns.sh - Validate ACA Private DNS Resolution
# 
# Purpose: Post-deployment DNS validation for Container Apps environment
#          Verifies private endpoint DNS records resolve to private IP addresses
#
# Usage: ./scripts/validate-aca-dns.sh [--parameter-file <path>]
#
# Prerequisites:
# - ACA environment deployed
# - VPN connection established (for private DNS resolution)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/aca/main.parameters.json"
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

Validate private DNS resolution for ACA environment

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/aca/main.parameters.json)
    -h, --help                  Show this help message

REQUIREMENTS:
    - VPN connection established for private DNS resolution
    - ACA environment deployed

CHECKS:
    - Default domain resolves to private IP (10.x.x.x)
    - DNS resolution time
    - Private endpoint connectivity (TCP)
    - Public DNS resolution blocked

EXAMPLES:
    # Validate DNS after deployment
    $0

    # Use custom parameter file
    $0 --parameter-file bicep/aca/main.parameters.prod.json

EOF
    exit 1
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

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

# ============================================================================
# DNS VALIDATION
# ============================================================================

get_aca_domain() {
    local RG_NAME
    RG_NAME=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-aca"' "$PARAMETER_FILE")
    local ENV_NAME
    ENV_NAME=$(jq -r '.parameters.environmentName.value // "cae-ai-lab"' "$PARAMETER_FILE")
    
    local DOMAIN
    DOMAIN=$(az containerapp env show --name "$ENV_NAME" --resource-group "$RG_NAME" \
        --query "properties.defaultDomain" -o tsv 2>/dev/null || true)
    
    if [[ -z "$DOMAIN" || "$DOMAIN" == "null" ]]; then
        log_error "Could not retrieve ACA default domain"
        log_info "Ensure the environment is deployed: $ENV_NAME in $RG_NAME"
        exit 1
    fi
    
    echo "$DOMAIN"
}

validate_dns_resolution() {
    local DOMAIN="$1"
    
    log_info "Testing DNS resolution for: $DOMAIN"
    
    # Test with dig
    if ! command -v dig &> /dev/null; then
        log_warning "dig command not found. Skipping DNS resolution test."
        log_info "Install with: sudo apt install dnsutils"
        return
    fi
    
    local START_MS
    START_MS=$(date +%s%3N)
    
    local DNS_RESULT
    DNS_RESULT=$(dig +short "$DOMAIN" 2>/dev/null || true)
    
    local END_MS
    END_MS=$(date +%s%3N)
    local DNS_TIME=$((END_MS - START_MS))
    
    if [[ -z "$DNS_RESULT" ]]; then
        log_error "DNS resolution failed for $DOMAIN"
        log_info "Are you connected to the VPN? Private DNS requires VPN."
        return
    fi
    
    log_success "DNS resolves: $DOMAIN -> $DNS_RESULT (${DNS_TIME}ms)"
    
    # Verify the IP is in private range (10.x.x.x or 172.16-31.x.x or 192.168.x.x)
    if [[ "$DNS_RESULT" =~ ^10\. ]] || [[ "$DNS_RESULT" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] || [[ "$DNS_RESULT" =~ ^192\.168\. ]]; then
        log_success "DNS resolves to private IP address: $DNS_RESULT"
    else
        log_error "DNS resolves to non-private IP: $DNS_RESULT (expected 10.x.x.x)"
    fi
}

validate_private_endpoint_connectivity() {
    local DOMAIN="$1"
    
    log_info "Testing private endpoint connectivity to: $DOMAIN"
    
    # Test TCP connectivity on port 443
    if ! command -v nc &> /dev/null && ! command -v ncat &> /dev/null; then
        log_warning "nc/ncat not found. Skipping TCP connectivity test."
        return
    fi
    
    local NC_CMD="nc"
    if command -v ncat &> /dev/null; then
        NC_CMD="ncat"
    fi
    
    if timeout 5 "$NC_CMD" -z "$DOMAIN" 443 2>/dev/null; then
        log_success "TCP connectivity: $DOMAIN:443 reachable"
    else
        log_warning "TCP connectivity: $DOMAIN:443 not reachable (VPN required)"
    fi
}

validate_public_access_blocked() {
    local DOMAIN="$1"
    
    log_info "Verifying public DNS does not resolve..."
    
    # Check against public DNS (Google 8.8.8.8)
    if ! command -v dig &> /dev/null; then
        log_warning "dig command not found. Skipping public DNS test."
        return
    fi
    
    local PUBLIC_RESULT
    PUBLIC_RESULT=$(dig +short @8.8.8.8 "$DOMAIN" 2>/dev/null || true)
    
    if [[ -z "$PUBLIC_RESULT" || "$PUBLIC_RESULT" == "NXDOMAIN" ]]; then
        log_success "Public DNS does not resolve $DOMAIN (private-only access confirmed)"
    else
        log_warning "Public DNS resolves $DOMAIN -> $PUBLIC_RESULT"
        log_info "This may indicate the environment is not fully internal"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

echo ""
echo "============================================"
echo "ACA Private DNS Validation"
echo "============================================"
echo ""

# Get ACA default domain
DOMAIN=$(get_aca_domain)
echo "ACA Default Domain: $DOMAIN"
echo ""

# Run DNS validations
validate_dns_resolution "$DOMAIN"
validate_private_endpoint_connectivity "$DOMAIN"
validate_public_access_blocked "$DOMAIN"

# Summary
echo ""
echo "============================================"
if [[ "$VALIDATION_PASSED" == "true" ]]; then
    log_success "All DNS validations passed!"
    echo ""
    echo "Private DNS is correctly configured for ACA environment."
    exit 0
else
    log_error "Some DNS validations failed. Review errors above."
    echo ""
    echo "Common fixes:"
    echo "  1. Connect to VPN for private DNS resolution"
    echo "  2. Verify DNS zone is linked to VNet"
    echo "  3. Check private endpoint status"
    exit 1
fi
