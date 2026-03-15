#!/bin/bash
#
# Deploy Native MCP Server to Azure API Management
#
# This script creates a native MCP server in APIM using the REST API (2025-03-01-preview).
# The native MCP server understands MCP protocol natively — handles transport,
# session management, and tool discovery — unlike a regular API that just proxies HTTP.
#
# Creates:
# - APIM Backend pointing to the ACA MCP server
# - Native MCP-type API (type: "mcp") referencing the backend
# - JWT validation policy (Entra ID, same as regular MCP API)
#
# Prerequisites:
# - Azure CLI logged in with Contributor access
# - MCP server deployed to ACA (scripts/deploy-mcp-server.sh)
# - APIM instance deployed (scripts/deploy-apim.sh)
#

set -e

# Configuration
APIM_NAME="apim-ai-lab-0115"
APIM_RG="rg-ai-apim"
API_VERSION="2025-03-01-preview"
BACKEND_NAME="mcp-server-backend"
API_NAME="mcp-server-native"
API_PATH="mcp-native"
API_DISPLAY_NAME="MCP Server (Native)"
BACKEND_URL="https://mcp-server.delightfulocean-ec53e247.eastus2.azurecontainerapps.io"

# JWT policy values
TENANT_ID="38c1a7b0-f16b-45fd-a528-87d8720e868e"
CLIENT_APP_ID="b159da1b-bbe5-461e-922a-ef22194461c3"
AUDIENCE_ID="6cb63aba-6d0d-4f06-957e-c584fdeb23d7"

AUTO_APPROVE=false

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--auto-approve]"
            exit 1
            ;;
    esac
done

echo "=== Deploy Native MCP Server to APIM ==="
echo "APIM:          $APIM_NAME"
echo "Resource Group: $APIM_RG"
echo "Backend URL:    $BACKEND_URL"
echo "API Path:       /$API_PATH"
echo "API Version:    $API_VERSION"
echo ""

SUB_ID=$(az account show --query id -o tsv)
BASE_URL="https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${APIM_RG}/providers/Microsoft.ApiManagement/service/${APIM_NAME}"

# ─── Step 1: Create/update Backend ───
echo "[1/3] Creating APIM backend: $BACKEND_NAME..."
az rest --method PUT \
    --url "${BASE_URL}/backends/${BACKEND_NAME}?api-version=${API_VERSION}" \
    --body "{\"properties\":{\"url\":\"${BACKEND_URL}\",\"protocol\":\"http\",\"description\":\"ACA-hosted MCP server backend\"}}" \
    -o json | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'  URL: {d[\"properties\"][\"url\"]}')"

echo ""

# ─── Step 2: Create/update native MCP API ───
echo "[2/3] Creating native MCP API: $API_NAME..."

if [ "$AUTO_APPROVE" = false ]; then
    # Check if API already exists
    EXISTING=$(az rest --method GET \
        --url "${BASE_URL}/apis/${API_NAME}?api-version=${API_VERSION}" \
        2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || echo "")

    if [ -n "$EXISTING" ]; then
        echo "  API '$API_NAME' already exists. It will be updated."
    fi

    read -p "Continue? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled"
        exit 0
    fi
fi

az rest --method PUT \
    --url "${BASE_URL}/apis/${API_NAME}?api-version=${API_VERSION}" \
    --body "{\"properties\":{\"displayName\":\"${API_DISPLAY_NAME}\",\"path\":\"${API_PATH}\",\"protocols\":[\"https\"],\"type\":\"mcp\",\"subscriptionRequired\":false,\"backendId\":\"${BACKEND_NAME}\",\"mcpProperties\":{\"transportType\":\"streamableHttp\"}}}" \
    -o json | python3 -c "
import json, sys
d = json.load(sys.stdin)
p = d['properties']
print(f'  Name:      {d[\"name\"]}')
print(f'  Type:      {p[\"type\"]}')
print(f'  Path:      {p[\"path\"]}')
print(f'  BackendId: {p[\"backendId\"]}')
"

echo ""

# ─── Step 3: Apply JWT validation policy ───
echo "[3/3] Applying JWT validation policy..."

POLICY_XML="<policies><inbound><base /><validate-azure-ad-token tenant-id=\\\"${TENANT_ID}\\\" header-name=\\\"Authorization\\\" failed-validation-httpcode=\\\"401\\\" failed-validation-error-message=\\\"Unauthorized. Access token is missing or invalid.\\\"><client-application-ids><application-id>${CLIENT_APP_ID}</application-id></client-application-ids><audiences><audience>${AUDIENCE_ID}</audience><audience>api://${AUDIENCE_ID}</audience></audiences></validate-azure-ad-token></inbound><backend><forward-request timeout=\\\"120\\\" buffer-response=\\\"false\\\" /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>"

POLICY_BODY="{\"properties\":{\"format\":\"xml\",\"value\":\"${POLICY_XML}\"}}"

az rest --method PUT \
    --url "${BASE_URL}/apis/${API_NAME}/policies/policy?api-version=${API_VERSION}" \
    --body "$POLICY_BODY" \
    -o none 2>/dev/null

echo "  JWT validation policy applied"
echo "  Tenant:     $TENANT_ID"
echo "  Client App: $CLIENT_APP_ID"
echo "  Audience:   $AUDIENCE_ID"
echo ""

# ─── Summary ───
echo "============================================"
echo "Deployment Complete"
echo "============================================"
echo ""
echo "  Native MCP Server Endpoint:"
echo "    POST https://${APIM_NAME}.azure-api.net/${API_PATH}/mcp"
echo ""
echo "  Regular MCP API Endpoint (still active):"
echo "    POST https://${APIM_NAME}.azure-api.net/mcp/"
echo ""
echo "  Test with:"
echo "    ./scripts/test-mcp-native.sh"
echo ""
