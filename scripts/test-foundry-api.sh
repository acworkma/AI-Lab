#!/usr/bin/env bash
#
# test-foundry-api.sh - Test Foundry LLM API through Private APIM
#
# Usage: ./scripts/test-foundry-api.sh [--deployment <name>] [--prompt <text>]
#

set -euo pipefail

DEPLOYMENT="${DEPLOYMENT:-gpt-4.1}"
PROMPT="${PROMPT:-Say hello from the private APIM-to-Foundry pipeline}"
APIM_HOST="apim-ai-lab-private.azure-api.net"
API_VERSION="2024-10-21"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

while [[ $# -gt 0 ]]; do
    case $1 in
        --deployment) DEPLOYMENT="$2"; shift 2 ;;
        --prompt) PROMPT="$2"; shift 2 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

echo ""
echo "=============================================="
echo "  Foundry LLM API Test (Private APIM)"
echo "=============================================="
echo ""

# 1. DNS Resolution
log_info "Testing DNS resolution for $APIM_HOST..."
RESOLVED_IP=$(dig +short "$APIM_HOST" | tail -1 2>/dev/null || echo "")
if [[ "$RESOLVED_IP" =~ ^10\. ]] || [[ "$RESOLVED_IP" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] || [[ "$RESOLVED_IP" =~ ^192\.168\. ]]; then
    log_pass "DNS resolves to private IP: $RESOLVED_IP"
else
    log_fail "DNS resolved to non-private IP: $RESOLVED_IP"
    exit 1
fi

# 2. Acquire token
log_info "Acquiring Entra ID token..."
TOKEN=$(az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv 2>/dev/null)
if [ -n "$TOKEN" ]; then
    log_pass "Token acquired"
else
    log_fail "Failed to acquire token"
    exit 1
fi

# 3. Chat completions
log_info "Testing chat completions (deployment: $DEPLOYMENT)..."
ENDPOINT="https://${APIM_HOST}/openai/deployments/${DEPLOYMENT}/chat/completions?api-version=${API_VERSION}"

RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 10 \
    -X POST "$ENDPOINT" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":50}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    MODEL=$(echo "$BODY" | jq -r '.model // "unknown"')
    CONTENT=$(echo "$BODY" | jq -r '.choices[0].message.content // "empty"')
    log_pass "Chat completions OK (HTTP 200)"
    log_info "Model: $MODEL"
    log_info "Response: $CONTENT"
else
    log_fail "Chat completions failed (HTTP $HTTP_CODE)"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
fi

# 4. List models
log_info "Testing list models..."
MODELS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 \
    "https://${APIM_HOST}/openai/models?api-version=${API_VERSION}" \
    -H "Authorization: Bearer $TOKEN")

if [ "$MODELS_RESPONSE" = "200" ]; then
    log_pass "List models OK (HTTP 200)"
else
    log_fail "List models failed (HTTP $MODELS_RESPONSE)"
fi

echo ""
log_pass "All tests passed!"
echo ""
