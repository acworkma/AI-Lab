#!/usr/bin/env bash
#
# validate-aoai-private.sh - Validate Private Azure OpenAI deployment
#
# Usage: ./scripts/validate-aoai-private.sh [--ops]
#
# Checks:
# - Resource group exists
# - OpenAI account exists and has public access disabled
# - Model deployment exists
# - Private endpoint is connected
# - DNS resolves to private IP
# - (--ops) Inference test via private endpoint
#

set -euo pipefail

RESOURCE_GROUP="rg-ai-aoai"
ACCOUNT_NAME="oai-ailab-private"
DEPLOYMENT_NAME="gpt-4.1"
RUN_OPS=false
VALIDATION_PASSED=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; VALIDATION_PASSED=false; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

while [[ $# -gt 0 ]]; do
    case $1 in
        --ops) RUN_OPS=true; shift ;;
        -h|--help) echo "Usage: $0 [--ops]"; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo ""
echo "=============================================="
echo "  Private Azure OpenAI Validation"
echo "=============================================="
echo ""

# Check resource group
log_info "Checking resource group..."
if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
    log_pass "Resource group $RESOURCE_GROUP exists"
else
    log_fail "Resource group $RESOURCE_GROUP not found"
fi

# Check account
log_info "Checking OpenAI account..."
if az cognitiveservices account show --name "$ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
    log_pass "Account $ACCOUNT_NAME exists"

    # Check public access
    PUBLIC_ACCESS=$(az cognitiveservices account show --name "$ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" \
        --query "properties.publicNetworkAccess" -o tsv 2>/dev/null)
    if [ "$PUBLIC_ACCESS" = "Disabled" ]; then
        log_pass "Public network access is disabled"
    else
        log_fail "Public network access is: $PUBLIC_ACCESS (expected: Disabled)"
    fi

    # Check kind
    KIND=$(az cognitiveservices account show --name "$ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" \
        --query "kind" -o tsv 2>/dev/null)
    if [ "$KIND" = "OpenAI" ]; then
        log_pass "Account kind is OpenAI (legacy)"
    else
        log_warn "Account kind is $KIND (expected: OpenAI)"
    fi
else
    log_fail "Account $ACCOUNT_NAME not found"
fi

# Check model deployment
log_info "Checking model deployment..."
if az cognitiveservices account deployment show --name "$ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" \
    --deployment-name "$DEPLOYMENT_NAME" --output none 2>/dev/null; then
    log_pass "Model deployment $DEPLOYMENT_NAME exists"
else
    log_fail "Model deployment $DEPLOYMENT_NAME not found"
fi

# Check private endpoint
log_info "Checking private endpoint..."
PE_COUNT=$(az network private-endpoint list --resource-group "$RESOURCE_GROUP" \
    --query "length([?contains(name, '$ACCOUNT_NAME')])" -o tsv 2>/dev/null)
if [ "$PE_COUNT" -gt 0 ]; then
    log_pass "Private endpoint found"
    PE_STATUS=$(az network private-endpoint list --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, '$ACCOUNT_NAME')].privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status" -o tsv 2>/dev/null)
    if [ "$PE_STATUS" = "Approved" ]; then
        log_pass "Private endpoint connection approved"
    else
        log_warn "Private endpoint status: $PE_STATUS"
    fi
else
    log_fail "No private endpoint found"
fi

# Check DNS resolution
log_info "Checking DNS resolution..."
RESOLVED_IP=$(dig +short "${ACCOUNT_NAME}.openai.azure.com" | tail -1 2>/dev/null || true)
if [[ "$RESOLVED_IP" == 10.* ]]; then
    log_pass "DNS resolves to private IP: $RESOLVED_IP"
elif [ -n "$RESOLVED_IP" ]; then
    log_warn "DNS resolves to: $RESOLVED_IP (expected 10.x.x.x private IP)"
else
    log_warn "Could not resolve DNS (dig not available or resolution failed)"
fi

# Operational test
if [ "$RUN_OPS" = true ]; then
    echo ""
    log_info "Running inference test..."
    TOKEN=$(az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv)
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        "https://${ACCOUNT_NAME}.openai.azure.com/openai/deployments/${DEPLOYMENT_NAME}/chat/completions?api-version=2024-10-21" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"user","content":"Say hello"}],"max_tokens":10}')
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    if [ "$HTTP_CODE" = "200" ]; then
        log_pass "Inference test succeeded (HTTP 200)"
    else
        log_fail "Inference test failed (HTTP $HTTP_CODE)"
        echo "$BODY" | head -5
    fi
fi

# Summary
echo ""
echo "=============================================="
if [ "$VALIDATION_PASSED" = true ]; then
    log_pass "All validation checks passed"
else
    log_fail "Some validation checks failed"
    exit 1
fi
