#!/bin/bash
#
# Deploy MCP API to Azure API Management
#
# This script deploys the mcp-api Bicep module which creates:
# - MCP API with POST / operation
# - JWT validation policy at API level (Entra ID)
# - MCP passthrough policy at operation level (SSE streaming)
#

set -e

# Configuration
APIM_NAME="apim-ai-lab-0115"
APIM_RG="rg-ai-apim"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="$SCRIPT_DIR/../bicep/mcp-api"
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

echo "=== Deploy MCP API to APIM ==="
echo "APIM: $APIM_NAME"
echo "Resource Group: $APIM_RG"
echo "Bicep Directory: $BICEP_DIR"
echo ""

# Validate bicep files exist
for f in "$BICEP_DIR/main.bicep" "$BICEP_DIR/policies/jwt-validation.xml" "$BICEP_DIR/policies/mcp-passthrough.xml"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: $f not found"
        exit 1
    fi
done

echo "[1/3] Validating Bicep template..."
az bicep build --file "$BICEP_DIR/main.bicep" --stdout > /dev/null
echo "  Validation passed"

echo ""
echo "[2/3] Running what-if deployment..."
az deployment group what-if \
    --resource-group "$APIM_RG" \
    --template-file "$BICEP_DIR/main.bicep" \
    --parameters apimName="$APIM_NAME"

echo ""
if [ "$AUTO_APPROVE" = false ]; then
    read -p "Continue with deployment? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled"
        exit 0
    fi
fi

echo ""
echo "[3/3] Deploying MCP API..."
az deployment group create \
    --resource-group "$APIM_RG" \
    --template-file "$BICEP_DIR/main.bicep" \
    --parameters apimName="$APIM_NAME" \
    --name "mcp-api-$(date +%Y%m%d-%H%M%S)" \
    --output table

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "API Endpoint:"
echo "  POST https://$APIM_NAME.azure-api.net/mcp/"
echo ""
echo "Test with:"
echo "  TOKEN=\$(az account get-access-token --resource 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 --query accessToken -o tsv)"
echo "  curl -X POST -H \"Authorization: Bearer \$TOKEN\" -H \"Content-Type: application/json\" \\"
echo "    -d '{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"id\":1,\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1.0\"}}}' \\"
echo "    https://$APIM_NAME.azure-api.net/mcp/"
