#!/usr/bin/env bash
#
# validate-keyvault-dns.sh - Validate Key Vault Private DNS Resolution
# 
# Purpose: Verify DNS resolution for Key Vault private endpoint from VPN-connected client
#          Confirms privatelink.vaultcore.azure.net A record resolves to private IP
#
# Usage: ./scripts/validate-keyvault-dns.sh [--vault-name <name>]
#
# Prerequisites:
# - VPN connection established to vWAN hub
# - Key Vault deployed with private endpoint
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/keyvault/main.parameters.json"
VAULT_NAME=""

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
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate Key Vault private DNS resolution from VPN-connected client

OPTIONS:
    -n, --vault-name NAME       Key Vault name (auto-detected if not provided)
    -p, --parameter-file PATH   Path to parameter file for auto-detection
    -h, --help                  Show this help message

PREREQUISITES:
    - VPN connection established to vWAN hub
    - Key Vault deployed with private endpoint
    - DNS resolver configured in core infrastructure

WHAT THIS VALIDATES:
    - NFR-003: DNS resolution completes within 100ms
    - FR-008: Private endpoint resolves to private IP (10.1.0.x)
    - SC-002: Vault FQDN resolves to private IP, not public

EXAMPLES:
    # Auto-detect vault name from deployed resources
    $0

    # Specify vault name explicitly
    $0 --vault-name kv-ai-lab-0117

EOF
    exit 1
}

get_vault_name() {
    if [[ -n "$VAULT_NAME" ]]; then
        return
    fi
    
    # Try to get from deployment output
    if [[ -f /tmp/keyvault-name.txt ]]; then
        VAULT_NAME=$(cat /tmp/keyvault-name.txt)
        return
    fi
    
    # Try to get from resource group
    local RG_NAME
    RG_NAME=$(jq -r '.parameters.resourceGroupName.value // "rg-ai-keyvault"' "$PARAMETER_FILE" 2>/dev/null || echo "rg-ai-keyvault")
    
    VAULT_NAME=$(az keyvault list --resource-group "$RG_NAME" --query "[0].name" -o tsv 2>/dev/null || true)
    
    if [[ -z "$VAULT_NAME" ]]; then
        log_error "Could not detect Key Vault name. Use --vault-name option."
        exit 1
    fi
}

validate_dns_resolution() {
    log_info "Validating DNS resolution for: ${VAULT_NAME}.vault.azure.net"
    
    local FQDN="${VAULT_NAME}.vault.azure.net"
    local START_TIME
    local END_TIME
    local DURATION_MS
    
    # Measure DNS resolution time (NFR-003: <100ms target)
    START_TIME=$(date +%s%N)
    
    # Resolve DNS
    local RESOLVED_IP
    RESOLVED_IP=$(dig +short "$FQDN" 2>/dev/null | tail -1 || true)
    
    END_TIME=$(date +%s%N)
    DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
    
    if [[ -z "$RESOLVED_IP" ]]; then
        log_error "DNS resolution failed for: $FQDN"
        log_info "Ensure you are connected to VPN and DNS resolver is working"
        return 1
    fi
    
    echo ""
    echo "DNS Resolution Results:"
    echo "----------------------------------------"
    echo "  FQDN:          $FQDN"
    echo "  Resolved IP:   $RESOLVED_IP"
    echo "  Resolution:    ${DURATION_MS}ms"
    echo "----------------------------------------"
    
    # Check if IP is in private range (10.1.0.x for snet-private-endpoints)
    if [[ "$RESOLVED_IP" =~ ^10\. ]]; then
        log_success "DNS resolves to private IP: $RESOLVED_IP"
    else
        log_error "DNS resolves to public IP: $RESOLVED_IP"
        log_info "Expected private IP in 10.1.0.x range"
        log_info "Check private DNS zone link and VPN DNS settings"
        return 1
    fi
    
    # Check resolution time (NFR-003)
    if [[ $DURATION_MS -lt 100 ]]; then
        log_success "DNS resolution within target (NFR-003: <100ms, actual: ${DURATION_MS}ms)"
    else
        log_warning "DNS resolution exceeded target (NFR-003: <100ms, actual: ${DURATION_MS}ms)"
    fi
}

validate_private_endpoint_connectivity() {
    log_info "Testing private endpoint connectivity..."
    
    local FQDN="${VAULT_NAME}.vault.azure.net"
    
    # Test HTTPS connectivity (port 443)
    if timeout 5 bash -c "echo >/dev/tcp/${FQDN}/443" 2>/dev/null; then
        log_success "TCP connection to port 443 successful"
    else
        log_warning "TCP connection test failed (may require VPN connection)"
    fi
    
    # Test with curl (expect 401 Unauthorized, which means connection works)
    local HTTP_CODE
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://${FQDN}/secrets?api-version=7.4" 2>/dev/null || echo "000")
    
    if [[ "$HTTP_CODE" == "401" ]] || [[ "$HTTP_CODE" == "403" ]]; then
        log_success "HTTPS connectivity verified (received expected auth response: $HTTP_CODE)"
    elif [[ "$HTTP_CODE" == "000" ]]; then
        log_warning "HTTPS connectivity test failed (connection refused or timeout)"
        log_info "Ensure VPN is connected and DNS is resolving correctly"
    else
        log_info "HTTPS response code: $HTTP_CODE"
    fi
}

validate_public_access_blocked() {
    log_info "Verifying public access is blocked..."
    
    # Try to resolve using public DNS (8.8.8.8)
    local PUBLIC_IP
    PUBLIC_IP=$(dig +short "${VAULT_NAME}.vault.azure.net" @8.8.8.8 2>/dev/null | tail -1 || true)
    
    if [[ -n "$PUBLIC_IP" ]] && [[ ! "$PUBLIC_IP" =~ ^10\. ]]; then
        log_info "Public DNS resolves to: $PUBLIC_IP"
        
        # Try to connect via public IP (should fail if public access is disabled)
        local HTTP_CODE
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://${VAULT_NAME}.vault.azure.net/secrets?api-version=7.4" --resolve "${VAULT_NAME}.vault.azure.net:443:${PUBLIC_IP}" 2>/dev/null || echo "000")
        
        if [[ "$HTTP_CODE" == "000" ]] || [[ "$HTTP_CODE" == "403" ]]; then
            log_success "Public access is blocked (SC-001)"
        else
            log_warning "Public access may not be fully blocked (response: $HTTP_CODE)"
        fi
    else
        log_success "Public DNS resolution not returning public IP"
    fi
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--vault-name)
            VAULT_NAME="$2"
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

# ============================================================================
# MAIN
# ============================================================================

echo ""
echo "============================================"
echo "Key Vault Private DNS Validation"
echo "============================================"
echo ""

# Get vault name
get_vault_name
log_info "Key Vault: $VAULT_NAME"
echo ""

# Run validations
validate_dns_resolution
echo ""
validate_private_endpoint_connectivity
echo ""
validate_public_access_blocked

echo ""
echo "============================================"
log_success "DNS validation complete!"
echo "============================================"
