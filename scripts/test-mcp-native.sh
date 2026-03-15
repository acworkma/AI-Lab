#!/bin/bash
#
# End-to-End Test Script for Native MCP Server through APIM
#
# Tests:
# 1. Unauthenticated request → 401
# 2. Authenticated MCP initialize → success
# 3. Authenticated MCP tools/list → returns tools
# 4. Authenticated MCP tools/call → invokes tool
#
# Prerequisites:
# - Azure CLI logged in
# - Native MCP server deployed to APIM (scripts/deploy-mcp-native.sh)
# - MCP server running in ACA
#
# Authentication:
# - Uses client credentials flow with the Entra Agent Identity
# - The agent identity (b159da1b) is the authorized client in the JWT policy
#

set -e

# Configuration
APIM_GATEWAY="https://apim-ai-lab-0115.azure-api.net"
API_PATH="mcp-native/mcp"
TENANT_ID="38c1a7b0-f16b-45fd-a528-87d8720e868e"
CLIENT_ID="b159da1b-bbe5-461e-922a-ef22194461c3"
AUDIENCE_ID="6cb63aba-6d0d-4f06-957e-c584fdeb23d7"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ENDPOINT="$APIM_GATEWAY/$API_PATH"
PASSED=0
FAILED=0

echo "=== Native MCP Server End-to-End Test ==="
echo ""
echo "Gateway:  $APIM_GATEWAY"
echo "Endpoint: $ENDPOINT"
echo ""

# ─── Test 1: Unauthenticated request → 401 ───
echo -e "${YELLOW}[1/4] Testing unauthenticated request...${NC}"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' \
    "$ENDPOINT")

BODY=$(echo "$RESPONSE" | head -n -1)
CODE=$(echo "$RESPONSE" | tail -n 1)

if [ "$CODE" == "401" ]; then
    echo -e "${GREEN}  ✓ Unauthenticated request rejected (401)${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}  ✗ Expected 401, got HTTP $CODE${NC}"
    echo "  Response: $BODY"
    FAILED=$((FAILED + 1))
fi
echo ""

# ─── Get OAuth token via client credentials ───
echo -e "${YELLOW}Acquiring OAuth token (client credentials)...${NC}"

# Prompt for client secret if not provided via environment
if [ -z "$MCP_CLIENT_SECRET" ]; then
    read -sp "Enter client secret for agent identity ($CLIENT_ID): " MCP_CLIENT_SECRET
    echo ""
fi

TOKEN_RESPONSE=$(curl -s -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${MCP_CLIENT_SECRET}" \
    -d "scope=${AUDIENCE_ID}/.default" \
    -d "grant_type=client_credentials")

TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo -e "${RED}ERROR: Failed to get access token${NC}"
    ERROR_DESC=$(echo "$TOKEN_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('error_description','Unknown error'))" 2>/dev/null)
    echo "  Error: $ERROR_DESC"
    exit 1
fi
echo -e "${GREEN}  Token acquired (${#TOKEN} chars)${NC}"
echo ""

# ─── Test 2: MCP initialize ───
echo -e "${YELLOW}[2/4] Testing MCP initialize...${NC}"
INIT_BODY='{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"native-test","version":"1.0"}}}'

RESPONSE=$(curl -s -w "\n%{http_code}" -N --max-time 15 \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -D /tmp/mcp-native-init-headers.txt \
    -d "$INIT_BODY" \
    "$ENDPOINT")

BODY=$(echo "$RESPONSE" | head -n -1)
CODE=$(echo "$RESPONSE" | tail -n 1)

# Extract JSON from SSE if needed
if echo "$BODY" | grep -q '^data:'; then
    BODY=$(echo "$BODY" | grep '^data:' | head -1 | sed 's/^data://')
fi

if [ "$CODE" == "200" ]; then
    if echo "$BODY" | grep -q '"serverInfo"'; then
        echo -e "${GREEN}  ✓ MCP initialize succeeded (200)${NC}"
        SERVER_NAME=$(echo "$BODY" | grep -o '"name":"[^"]*"' | head -1)
        echo "  Server: $SERVER_NAME"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}  ✗ Response missing serverInfo${NC}"
        echo "  Response: $BODY"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}  ✗ MCP initialize failed (HTTP $CODE)${NC}"
    echo "  Response: $BODY"
    FAILED=$((FAILED + 1))
fi
echo ""

# Extract session ID for subsequent requests
SESSION_ID=$(grep -i '^mcp-session-id:' /tmp/mcp-native-init-headers.txt 2>/dev/null | tr -d '\r' | sed 's/[Mm]cp-[Ss]ession-[Ii]d: *//' || true)
if [ -n "$SESSION_ID" ]; then
    echo "  Session ID: $SESSION_ID"
fi

SESSION_ARGS=""
if [ -n "$SESSION_ID" ]; then
    SESSION_ARGS="-H \"Mcp-Session-Id: $SESSION_ID\""
fi

# Send initialized notification
eval curl -s -o /dev/null --max-time 5 \
    -X POST \
    -H '"Authorization: Bearer $TOKEN"' \
    -H '"Content-Type: application/json"' \
    $SESSION_ARGS \
    -d "'{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}'" \
    "'$ENDPOINT'" 2>/dev/null || true

# ─── Test 3: List tools ───
echo -e "${YELLOW}[3/4] Testing MCP tools/list...${NC}"
TOOLS_BODY='{"jsonrpc":"2.0","method":"tools/list","id":2,"params":{}}'

RESPONSE=$(eval curl -s -w '"\\n%{http_code}"' -N --max-time 15 \
    -X POST \
    -H '"Authorization: Bearer $TOKEN"' \
    -H '"Content-Type: application/json"' \
    -H '"Accept: application/json, text/event-stream"' \
    $SESSION_ARGS \
    -d "'$TOOLS_BODY'" \
    "'$ENDPOINT'")

BODY=$(echo "$RESPONSE" | head -n -1)
CODE=$(echo "$RESPONSE" | tail -n 1)

# Extract JSON from SSE if needed
if echo "$BODY" | grep -q '^data:'; then
    BODY=$(echo "$BODY" | grep '^data:' | head -1 | sed 's/^data://')
fi

if [ "$CODE" == "200" ]; then
    if echo "$BODY" | grep -q '"get_current_time"'; then
        TOOL_COUNT=$(echo "$BODY" | grep -o '"name"' | wc -l)
        echo -e "${GREEN}  ✓ tools/list returned $TOOL_COUNT tools (200)${NC}"
        echo "$BODY" | grep -o '"name":"[^"]*"' | while read -r line; do
            echo "    - $line"
        done
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}  ✗ tools/list missing expected tools${NC}"
        echo "  Response: $BODY"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}  ✗ tools/list failed (HTTP $CODE)${NC}"
    echo "  Response: $BODY"
    FAILED=$((FAILED + 1))
fi
echo ""

# ─── Test 4: Call tool ───
echo -e "${YELLOW}[4/4] Testing MCP tools/call (get_current_time)...${NC}"
CALL_BODY='{"jsonrpc":"2.0","method":"tools/call","id":3,"params":{"name":"get_current_time","arguments":{"timezone_name":"UTC"}}}'

RESPONSE=$(eval curl -s -w '"\\n%{http_code}"' -N --max-time 15 \
    -X POST \
    -H '"Authorization: Bearer $TOKEN"' \
    -H '"Content-Type: application/json"' \
    -H '"Accept: application/json, text/event-stream"' \
    $SESSION_ARGS \
    -d "'$CALL_BODY'" \
    "'$ENDPOINT'")

BODY=$(echo "$RESPONSE" | head -n -1)
CODE=$(echo "$RESPONSE" | tail -n 1)

# Extract JSON from SSE if needed
if echo "$BODY" | grep -q '^data:'; then
    BODY=$(echo "$BODY" | grep '^data:' | head -1 | sed 's/^data://')
fi

if [ "$CODE" == "200" ]; then
    if echo "$BODY" | grep -q '"content"'; then
        echo -e "${GREEN}  ✓ tools/call succeeded (200)${NC}"
        TIME_VAL=$(echo "$BODY" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9:+.]*' | head -1)
        if [ -n "$TIME_VAL" ]; then
            echo "  Time: $TIME_VAL"
        fi
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}  ✗ tools/call response missing content${NC}"
        echo "  Response: $BODY"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}  ✗ tools/call failed (HTTP $CODE)${NC}"
    echo "  Response: $BODY"
    FAILED=$((FAILED + 1))
fi
echo ""

# ─── Summary ───
TOTAL=$((PASSED + FAILED))
echo "=== Test Summary ==="
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}All $TOTAL tests passed!${NC}"
else
    echo -e "${RED}$FAILED of $TOTAL tests failed${NC}"
fi
echo ""
