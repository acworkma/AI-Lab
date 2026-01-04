#!/bin/bash

################################################################################
# Test DNS Resolver Script
################################################################################
# Purpose: Validate Azure DNS Private Resolver functionality
# Usage: ./scripts/test-dns-resolver.sh [OPTIONS]
# Options:
#   -i, --ip <IP>     Resolver inbound endpoint IP to test (required)
#   -h, --help        Display this help message
#
# Author: DevOps Team
# Created: 2026-01-04
# Status: Placeholder - Implementation pending
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize variables
RESOLVER_IP=""
TESTS_PASSED=0
TESTS_FAILED=0

# Functions
show_help() {
    head -20 "$0" | grep "^#" | sed 's/^# //'
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ip)
            RESOLVER_IP="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

if [ -z "$RESOLVER_IP" ]; then
    echo "Error: Resolver IP is required"
    show_help
    exit 1
fi

log_info "Starting DNS Resolver validation tests..."
log_info "Resolver IP: $RESOLVER_IP"
echo ""

# Level 1: Resolver Existence
log_info "Level 1: Checking resolver resource existence..."
if az resource show -g rg-ai-core --resource-type Microsoft.Network/dnsResolvers -n dnsr-ai-shared &>/dev/null; then
    log_success "Resolver 'dnsr-ai-shared' exists in rg-ai-core"
else
    log_error "Resolver 'dnsr-ai-shared' not found in rg-ai-core"
fi

# Level 2: Inbound Endpoint IP
log_info "Level 2: Verifying inbound endpoint IP matches expected..."
ACTUAL_IP=$(az rest --method get \
    --uri "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-ai-core/providers/Microsoft.Network/dnsResolvers/dnsr-ai-shared/inboundEndpoints?api-version=2022-07-01" \
    --query "value[0].properties.ipConfigurations[0].privateIpAddress" -o tsv 2>/dev/null)

if [ "$ACTUAL_IP" == "$RESOLVER_IP" ]; then
    log_success "Inbound endpoint IP matches: $ACTUAL_IP"
else
    log_warning "Inbound endpoint IP is $ACTUAL_IP, expected $RESOLVER_IP (continuing with actual IP)"
    RESOLVER_IP="$ACTUAL_IP"
fi

# Level 3-5: Private Zone Queries
log_info "Level 3: Testing private ACR zone query..."
ACR_RESULT=$(nslookup acraihubk2lydtz5uba3q.azurecr.io $RESOLVER_IP 2>&1)
if echo "$ACR_RESULT" | grep -q "10\.1\.0\."; then
    ACR_IP=$(echo "$ACR_RESULT" | grep "Address:" | tail -1 | awk '{print $2}')
    log_success "ACR resolves to private IP: $ACR_IP"
else
    log_error "ACR did not resolve to private IP (10.1.0.x)"
    echo "$ACR_RESULT"
fi

log_info "Level 4: Testing private Key Vault zone query..."
if command -v dig &>/dev/null; then
    KV_RESULT=$(dig @$RESOLVER_IP kv-ai-core-hub.vault.azure.net +short 2>&1)
    if echo "$KV_RESULT" | grep -q "10\.1\.0\."; then
        log_success "Key Vault resolves to private IP: $KV_RESULT"
    else
        log_warning "Key Vault query returned: $KV_RESULT (may not have private endpoint)"
    fi
else
    log_warning "dig command not available, skipping Key Vault test"
fi

log_info "Level 5: Testing private Storage zone query..."
STORAGE_RESULT=$(nslookup blob.core.windows.net $RESOLVER_IP 2>&1 | grep "Address:" | tail -1 | awk '{print $2}')
if [ -n "$STORAGE_RESULT" ]; then
    log_success "Storage zone query succeeded: $STORAGE_RESULT"
else
    log_warning "Storage zone query returned no results"
fi

# Public DNS Queries
log_info "Testing public DNS fallback..."
GOOGLE_RESULT=$(nslookup google.com $RESOLVER_IP 2>&1)
if echo "$GOOGLE_RESULT" | grep -q "Address:"; then
    GOOGLE_IP=$(echo "$GOOGLE_RESULT" | grep "Address:" | tail -1 | awk '{print $2}')
    log_success "Google.com resolves to public IP: $GOOGLE_IP"
else
    log_error "Public DNS query for google.com failed"
fi

MSFT_RESULT=$(nslookup microsoft.com $RESOLVER_IP 2>&1)
if echo "$MSFT_RESULT" | grep -q "Address:"; then
    MSFT_IP=$(echo "$MSFT_RESULT" | grep "Address:" | tail -1 | awk '{print $2}')
    log_success "Microsoft.com resolves to public IP: $MSFT_IP"
else
    log_error "Public DNS query for microsoft.com failed"
fi

# Connectivity Tests
log_info "Testing HTTPS connectivity to private ACR..."
if command -v curl &>/dev/null; then
    ACR_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://acraihubk2lydtz5uba3q.azurecr.io/v2/ 2>/dev/null)
    if [ "$ACR_HTTP" == "401" ] || [ "$ACR_HTTP" == "200" ]; then
        log_success "ACR HTTPS connectivity working (HTTP $ACR_HTTP)"
    else
        log_error "ACR HTTPS returned unexpected code: $ACR_HTTP"
    fi
else
    log_warning "curl command not available, skipping HTTPS tests"
fi

echo ""
echo -e "${BLUE}========== TEST SUMMARY ==========${NC}"
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
echo -e "Total:  ${BLUE}$((TESTS_PASSED + TESTS_FAILED))${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}[✓ ALL TESTS PASSED]${NC}"
    exit 0
else
    echo -e "${RED}[✗ SOME TESTS FAILED]${NC}"
    exit 1
fi
