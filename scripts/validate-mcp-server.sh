#!/usr/bin/env bash
#
# validate-mcp-server.sh - Validate MCP Server Container App Deployment
#
# Purpose: Check that the MCP server container app is correctly deployed,
#          running, and accessible within the private network.
#
# Usage: ./scripts/validate-mcp-server.sh [OPTIONS]
#
# Prerequisites:
# - MCP server deployed (run scripts/deploy-mcp-server.sh first)
# - VPN connection established (for DNS validation)
#

set -euo pipefail

# Default values
APP_NAME="mcp-server"
ACA_RG="rg-ai-aca"
ACR_RG="rg-ai-acr"
ACA_ENV_NAME="cae-ai-lab"

# Counters
PASS=0
FAIL=0
WARN=0

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

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASS=$((PASS + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAIL=$((FAIL + 1))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARN=$((WARN + 1))
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate MCP server container app deployment

OPTIONS:
    -n, --name NAME          Container app name (default: mcp-server)
    -g, --resource-group RG  Resource group (default: rg-ai-aca)
    -h, --help               Show this help message

CHECKS:
    1. Container app exists
    2. Container app is running
    3. Ingress configured (internal, correct port)
    4. System-assigned managed identity
    5. AcrPull role assigned
    6. DNS resolves to private IP (requires VPN)
    7. Latest revision is active

EOF
    exit 1
}

# ============================================================================
# VALIDATION CHECKS
# ============================================================================

check_app_exists() {
    log_info "Checking container app exists..."

    if az containerapp show --name "$APP_NAME" --resource-group "$ACA_RG" &> /dev/null; then
        log_pass "Container app '$APP_NAME' exists in '$ACA_RG'"
        return 0
    else
        log_fail "Container app '$APP_NAME' not found in '$ACA_RG'"
        return 1
    fi
}

check_app_running() {
    log_info "Checking container app status..."

    local RUNNING_STATUS
    RUNNING_STATUS=$(az containerapp show \
        --name "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --query "properties.runningStatus" -o tsv 2>/dev/null)

    local PROVISIONING_STATE
    PROVISIONING_STATE=$(az containerapp show \
        --name "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --query "properties.provisioningState" -o tsv 2>/dev/null)

    if [[ "$PROVISIONING_STATE" == "Succeeded" ]]; then
        log_pass "Provisioning state: Succeeded"
    else
        log_fail "Provisioning state: ${PROVISIONING_STATE:-Unknown}"
    fi

    if [[ -n "$RUNNING_STATUS" && "$RUNNING_STATUS" != "null" ]]; then
        log_info "Running status: $RUNNING_STATUS"
    fi
}

check_ingress() {
    log_info "Checking ingress configuration..."

    local INGRESS_JSON
    INGRESS_JSON=$(az containerapp show \
        --name "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --query "properties.configuration.ingress" -o json 2>/dev/null)

    if [[ -z "$INGRESS_JSON" || "$INGRESS_JSON" == "null" ]]; then
        log_fail "No ingress configured"
        return 1
    fi

    # Check external flag
    local EXTERNAL
    EXTERNAL=$(echo "$INGRESS_JSON" | jq -r '.external')
    if [[ "$EXTERNAL" == "false" ]]; then
        log_pass "Ingress is internal-only"
    else
        log_fail "Ingress is external (expected internal)"
    fi

    # Check target port
    local PORT
    PORT=$(echo "$INGRESS_JSON" | jq -r '.targetPort')
    if [[ "$PORT" == "3333" ]]; then
        log_pass "Target port: 3333"
    else
        log_fail "Target port: $PORT (expected 3333)"
    fi

    # Check FQDN
    local FQDN
    FQDN=$(echo "$INGRESS_JSON" | jq -r '.fqdn')
    if [[ -n "$FQDN" && "$FQDN" != "null" ]]; then
        log_pass "FQDN assigned: $FQDN"
    else
        log_fail "No FQDN assigned"
    fi
}

check_identity() {
    log_info "Checking managed identity..."

    local IDENTITY_TYPE
    IDENTITY_TYPE=$(az containerapp show \
        --name "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --query "identity.type" -o tsv 2>/dev/null)

    if [[ "$IDENTITY_TYPE" == *"SystemAssigned"* ]]; then
        log_pass "System-assigned managed identity enabled"
    else
        log_fail "No system-assigned managed identity (type: ${IDENTITY_TYPE:-None})"
    fi
}

check_acr_role() {
    log_info "Checking AcrPull role assignment..."

    local PRINCIPAL_ID
    PRINCIPAL_ID=$(az containerapp show \
        --name "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --query "identity.principalId" -o tsv 2>/dev/null)

    if [[ -z "$PRINCIPAL_ID" || "$PRINCIPAL_ID" == "null" ]]; then
        log_fail "No principal ID found for identity"
        return 1
    fi

    # Find ACR
    local ACR_ID
    ACR_ID=$(az acr list --resource-group "$ACR_RG" --query "[0].id" -o tsv 2>/dev/null)

    if [[ -z "$ACR_ID" ]]; then
        log_warn "ACR not found in '$ACR_RG' — cannot verify role assignment"
        return 0
    fi

    local ROLE_COUNT
    ROLE_COUNT=$(az role assignment list \
        --assignee "$PRINCIPAL_ID" \
        --role "AcrPull" \
        --scope "$ACR_ID" \
        --query "length(@)" -o tsv 2>/dev/null)

    if [[ "$ROLE_COUNT" -gt 0 ]]; then
        log_pass "AcrPull role assigned on ACR"
    else
        log_fail "AcrPull role NOT assigned on ACR"
    fi
}

check_dns_resolution() {
    log_info "Checking DNS resolution (requires VPN)..."

    local FQDN
    FQDN=$(az containerapp show \
        --name "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null)

    if [[ -z "$FQDN" || "$FQDN" == "null" ]]; then
        log_warn "No FQDN available — skipping DNS check"
        return 0
    fi

    if ! command -v nslookup &> /dev/null; then
        log_warn "nslookup not available — skipping DNS check"
        return 0
    fi

    local RESOLVED_IP
    RESOLVED_IP=$(nslookup "$FQDN" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | head -1 | awk '{print $2}')

    if [[ -z "$RESOLVED_IP" ]]; then
        log_warn "DNS resolution failed for $FQDN (VPN may not be connected)"
        return 0
    fi

    if [[ "$RESOLVED_IP" == 10.* ]]; then
        log_pass "DNS resolves to private IP: $RESOLVED_IP"
    else
        log_fail "DNS resolved to non-private IP: $RESOLVED_IP"
    fi
}

check_latest_revision() {
    log_info "Checking latest revision..."

    local REVISION
    REVISION=$(az containerapp show \
        --name "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --query "properties.latestRevisionName" -o tsv 2>/dev/null)

    if [[ -n "$REVISION" && "$REVISION" != "null" ]]; then
        log_pass "Latest revision: $REVISION"
    else
        log_fail "No revision found"
    fi

    # Check revision status
    local REVISION_STATUS
    REVISION_STATUS=$(az containerapp revision show \
        --name "$REVISION" \
        --app "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --query "properties.runningState" -o tsv 2>/dev/null || echo "Unknown")

    if [[ "$REVISION_STATUS" == "Running" ]]; then
        log_pass "Revision running state: Running"
    else
        log_warn "Revision running state: ${REVISION_STATUS}"
    fi
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            APP_NAME="$2"
            shift 2
            ;;
        -g|--resource-group)
            ACA_RG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_fail "Unknown option: $1"
            usage
            ;;
    esac
done

# ============================================================================
# MAIN
# ============================================================================

echo ""
echo "============================================"
echo "MCP Server Validation"
echo "============================================"
echo ""
echo "  App Name:       $APP_NAME"
echo "  Resource Group: $ACA_RG"
echo ""

# Check Azure login
if ! az account show &> /dev/null; then
    log_fail "Not logged into Azure. Run 'az login' first."
    exit 1
fi

# Run all checks
check_app_exists || { echo ""; echo "Cannot continue — app not found."; exit 1; }

echo ""
check_app_running
echo ""
check_ingress
echo ""
check_identity
echo ""
check_acr_role
echo ""
check_dns_resolution
echo ""
check_latest_revision

# Summary
echo ""
echo "============================================"
echo "Validation Summary"
echo "============================================"
echo ""
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo -e "  ${YELLOW}WARN${NC}: $WARN"
echo ""

if [[ $FAIL -gt 0 ]]; then
    log_fail "Validation completed with $FAIL failure(s)"
    exit 1
else
    log_pass "All checks passed"
    exit 0
fi
