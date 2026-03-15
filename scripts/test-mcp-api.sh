#!/bin/bash
#
# End-to-End Test Script for MCP API through APIM
#
# Tests:
# 1. Unauthenticated request → 401
# 2. Authenticated MCP initialize → success
# 3. Authenticated MCP tools/list → returns tools
# 4. Authenticated MCP tools/call → invokes tool
#
# Prerequisites:
# - Azure CLI logged in with access to the APIM app registration
# - MCP API deployed to APIM (scripts/deploy-mcp-api.sh)
# - MCP server running in ACA
#

set -e

# Configuration
APIM_GATEWAY="https://apim-ai-lab-0115.azure-api.net"
API_PATH="mcp"
APP_ID="6cb63aba-6d0d-4f06-957e-c584fdeb23d7"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ENDPOINT="$APIM_GATEWAY/$API_PATH/"
PASSED=0
FAILED=0

echo "=== MCP API End-to-End Test ==="
echo ""
echo "Gateway:  $APIM_GATEWAY"
echo "API Path: /$API_PATH"
echo "Endpoint: $ENDPOINT"
echo ""

# Helper: send MCP request and capture response + status code
mcp_request() {
    local token="$1"
    local body="$2"
    local auth_header=""
    if [ -n "$token" ]; then
        auth_header="-H \"Authorization: Bearer $token\""
    fi
    eval curl -s -w '"\\n%{http_code}"' \
        -X POST \
        $auth_header \
        -H '"Content-Type: application/json"' \
        -H '"Accept: application/json, text/event-stream"' \
        -d "'$body'" \
        "'$ENDPOINT'"
}

# ─── Test 1: Unauthenticated request → 401 ───
echo -e "${YELLOW}[1/4] Testing unauthenticated request...${NC}"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' \
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

# ─── Get OAuth token ───
echo -e "${YELLOW}Acquiring OAuth token...${NC}"
TOKEN=$(az account get-access-token --resource "$APP_ID" --query accessToken -o tsv 2>/dev/null) || {
    echo -e "${RED}ERROR: Failed to get access token${NC}"
    echo ""
    echo "You may need to login with consent:"
    echo "  az login --tenant 38c1a7b0-f16b-45fd-a528-87d8720e868e --scope ${APP_ID}/.default"
    exit 1
}
echo -e "${GREEN}  Token acquired (${#TOKEN} chars)${NC}"
echo ""

# ─── Test 2: MCP initialize ───
echo -e "${YELLOW}[2/4] Testing MCP initialize...${NC}"
INIT_BODY='{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"apim-test","version":"1.0"}}}'

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "$INIT_BODY" \
    "$ENDPOINT")

BODY=$(echo "$RESPONSE" | head -n -1)
CODE=$(echo "$RESPONSE" | tail -n 1)

if [ "$CODE" == "200" ]; then
    # Check for MCP initialize response - could be JSON or SSE
    if echo "$BODY" | grep -q '"serverInfo"'; then
        echo -e "${GREEN}  ✓ MCP initialize succeeded (200)${NC}"
        SERVER_NAME=$(echo "$BODY" | grep -o '"name":"[^"]*"' | head -1)
        echo "  Server: $SERVER_NAME"
        PASSED=$((PASSED + 1))
    elif echo "$BODY" | grep -q 'event:'; then
        # SSE response - extract data line
        DATA_LINE=$(echo "$BODY" | grep '^data:' | head -1 | sed 's/^data://')
        if echo "$DATA_LINE" | grep -q '"serverInfo"'; then
            echo -e "${GREEN}  ✓ MCP initialize succeeded via SSE (200)${NC}"
            SERVER_NAME=$(echo "$DATA_LINE" | grep -o '"name":"[^"]*"' | head -1)
            echo "  Server: $SERVER_NAME"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}  ✗ SSE response missing serverInfo${NC}"
            echo "  Data: $DATA_LINE"
            FAILED=$((FAILED + 1))
        fi
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

# Extract session URL from response headers for subsequent requests
# MCP streamable HTTP may return a session endpoint
SESSION_HEADER=$(curl -s -D - -o /dev/null \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "$INIT_BODY" \
    "$ENDPOINT" | grep -i '^mcp-session-id:' | tr -d '\r' || true)

SESSION_ID=""
if [ -n "$SESSION_HEADER" ]; then
    SESSION_ID=$(echo "$SESSION_HEADER" | sed 's/[Mm]cp-[Ss]ession-[Ii]d: *//')
    echo "  Session ID: $SESSION_ID"
fi

# Build session header for subsequent requests
SESSION_ARGS=""
if [ -n "$SESSION_ID" ]; then
    SESSION_ARGS="-H \"Mcp-Session-Id: $SESSION_ID\""
fi

# Send initialized notification (required by MCP protocol)
eval curl -s -o /dev/null \
    -X POST \
    -H '"Authorization: Bearer $TOKEN"' \
    -H '"Content-Type: application/json"' \
    $SESSION_ARGS \
    -d "'{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}'" \
    "'$ENDPOINT'" 2>/dev/null || true

# ─── Test 3: List tools ───
echo -e "${YELLOW}[3/4] Testing MCP tools/list...${NC}"
TOOLS_BODY='{"jsonrpc":"2.0","method":"tools/list","id":2,"params":{}}'

RESPONSE=$(eval curl -s -w '"\\n%{http_code}"' \
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

RESPONSE=$(eval curl -s -w '"\\n%{http_code}"' \
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
        # Extract the time value
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
echo "Endpoint: POST $ENDPOINT"
echo ""

exit "$FAILED"
