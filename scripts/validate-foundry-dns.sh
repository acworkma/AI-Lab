#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

if ! command -v nslookup >/dev/null 2>&1; then
  log_error "nslookup not found"
  exit 1
fi

if [ $# -eq 0 ]; then
  log_warning "No FQDNs provided. Supply resource FQDNs to validate private resolution."
  echo "Example: $0 myacct.services.ai.azure.com mysearch.search.windows.net"
  exit 0
fi

VALIDATION_FAILED=false

for fqdn in "$@"; do
  log_info "Resolving $fqdn"
  if nslookup "$fqdn" >/tmp/foundry-nslookup.txt 2>&1; then
    ip=$(awk '/^Address: /{print $2}' /tmp/foundry-nslookup.txt | tail -n1)
    if [[ "$ip" =~ ^10\.|^172\.(1[6-9]|2[0-9]|3[01])\.|^192\.168\. ]]; then
      log_success "$fqdn resolved to private IP: $ip"
    else
      log_error "$fqdn resolved to non-private IP: $ip"
      VALIDATION_FAILED=true
    fi
  else
    log_error "Failed to resolve $fqdn"
    cat /tmp/foundry-nslookup.txt
    VALIDATION_FAILED=true
  fi
done

rm -f /tmp/foundry-nslookup.txt

if [ "$VALIDATION_FAILED" = true ]; then
  log_error "DNS validation failed"
  exit 1
fi

log_success "DNS validation completed"
