#!/usr/bin/env bash
#
# scan-secrets.sh - Scan repository for common secret patterns
# 
# Purpose: Security validation to ensure no secrets are committed to source control
#   Constitutional requirement: Principle 4 - NO SECRETS IN SOURCE CONTROL
#
# Usage: ./scripts/scan-secrets.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
SECRETS_FOUND=0
FILES_SCANNED=0

# Common secret patterns (regex)
declare -a PATTERNS=(
    # Azure credentials
    "DefaultEndpointsProtocol=https;AccountName="
    "AccountKey=[A-Za-z0-9+/=]{88}"
    "SharedAccessSignature=sv=[0-9]{4}"
    
    # API Keys
    "api[_-]?key[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9]{32,}['\"]"
    "apikey[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9]{32,}['\"]"
    
    # Passwords
    "password[[:space:]]*[:=][[:space:]]*['\"][^'\"]{8,}['\"]"
    "passwd[[:space:]]*[:=][[:space:]]*['\"][^'\"]{8,}['\"]"
    "pwd[[:space:]]*[:=][[:space:]]*['\"][^'\"]{8,}['\"]"
    
    # Connection Strings
    "Server=[^;]+;Database=[^;]+;User Id=[^;]+;Password="
    "mongodb://[^:]+:[^@]+@"
    "postgres://[^:]+:[^@]+@"
    
    # Private Keys
    "BEGIN RSA PRIVATE KEY"
    "BEGIN OPENSSH PRIVATE KEY"
    "BEGIN PRIVATE KEY"
    
    # AWS (if mixed cloud)
    "AKIA[0-9A-Z]{16}"
    
    # Generic secrets
    "secret[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9+/=]{20,}['\"]"
    "token[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9._-]{20,}['\"]"
)

# Files to exclude from scanning
EXCLUDE_PATTERNS=(
    ".git/"
    "node_modules/"
    "*.bicep.json"
    ".vscode/"
    "scripts/scan-secrets.sh"  # Don't flag patterns in this script itself
)

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
}

log_fail() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
}

should_exclude() {
    local file=$1
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$file" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

scan_file() {
    local file=$1
    ((FILES_SCANNED++))
    
    for pattern in "${PATTERNS[@]}"; do
        if grep -qiE "$pattern" "$file" 2>/dev/null; then
            log_fail "Potential secret found in: $file"
            echo "       Pattern: $pattern"
            grep -niE "$pattern" "$file" | head -n 3 | sed 's/^/       /'
            echo ""
            ((SECRETS_FOUND++))
            return 1
        fi
    done
}

# Main execution
log_info "Scanning repository for hardcoded secrets..."
log_info "=========================================="
echo ""

# Find all files (excluding patterns)
while IFS= read -r -d '' file; do
    if should_exclude "$file"; then
        continue
    fi
    
    # Only scan text files
    if file "$file" | grep -q "text"; then
        scan_file "$file"
    fi
done < <(find . -type f -print0)

echo ""
echo "========================================"
echo "Secret Scan Summary"
echo "========================================"
echo "Files Scanned: $FILES_SCANNED"
echo -e "${RED}Potential Secrets Found: $SECRETS_FOUND${NC}"
echo ""

if [ $SECRETS_FOUND -eq 0 ]; then
    log_success "No secrets detected in repository!"
    echo ""
    log_info "Constitutional compliance: ✓ PASSED"
    log_info "  Principle 4: Security and Secrets Management"
    log_info "  Requirement: NO SECRETS IN SOURCE CONTROL"
    echo ""
    exit 0
else
    log_fail "Potential secrets detected - REVIEW REQUIRED"
    echo ""
    log_warning "Action Items:"
    echo "  1. Review flagged files above"
    echo "  2. Remove hardcoded secrets"
    echo "  3. Store secrets in Azure Key Vault"
    echo "  4. Use Key Vault references in parameter files"
    echo "  5. Add sensitive files to .gitignore"
    echo ""
    log_info "See: docs/core-infrastructure/README.md - Configuration section"
    exit 1
fi
