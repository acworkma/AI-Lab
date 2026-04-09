#!/bin/bash
#
# Deploy MCP API to Private Azure API Management
#
# This script deploys the mcp-api-private Bicep module which creates:
# - MCP API with POST / operation on the private APIM instance
# - JWT validation policy at API level (Entra ID)
# - MCP passthrough policy at operation level (SSE streaming)
#

set -e

# Configuration
APIM_NAME="apim-ai-lab-private"
APIM_RG="rg-ai-apim-private"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="$SCRIPT_DIR/../bicep/mcp-api-private"
AUTO_APPROVE=false

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --apim-name)
            APIM_NAME="$2"
            shift 2
            ;;
        --resource-group)
            APIM_RG="$2"
            shift 2
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--apim-name <name>] [--resource-group <rg>] [--auto-approve]"
            exit 1
            ;;
    esac
done

echo "=== Deploy MCP API to Private APIM ==="
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

# Check APIM exists
if ! az apim show --name "$APIM_NAME" --resource-group "$APIM_RG" &> /dev/null; then
    echo "ERROR: APIM instance $APIM_NAME not found in $APIM_RG"
    echo "Run deploy-apim-private.sh first."
    exit 1
fi

# Check JWT policy has been updated from placeholder
if grep -q "REPLACE_WITH" "$BICEP_DIR/policies/jwt-validation.xml"; then
    echo ""
    echo "WARNING: jwt-validation.xml still contains placeholder values."
    echo "Update the following in $BICEP_DIR/policies/jwt-validation.xml:"
    echo "  - REPLACE_WITH_TENANT_ID"
    echo "  - REPLACE_WITH_CLIENT_APP_ID"
    echo "  - REPLACE_WITH_APP_ID"
    echo ""
    if [ "$AUTO_APPROVE" = false ]; then
        read -p "Continue anyway (policy will fail at runtime)? (y/n) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled. Update jwt-validation.xml first."
            exit 0
        fi
    fi
fi

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
echo "[3/3] Deploying MCP API to private APIM..."
az deployment group create \
    --resource-group "$APIM_RG" \
    --template-file "$BICEP_DIR/main.bicep" \
    --parameters apimName="$APIM_NAME" \
    --name "mcp-api-private-$(date +%Y%m%d-%H%M%S)" \
    --output table

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "API Endpoint (private — only accessible via VNet):"
echo "  POST https://$APIM_NAME.azure-api.net/mcp/"
echo ""
echo "Next steps:"
echo "  1. Create custom connector in Copilot Studio pointing to the APIM FQDN"
echo "  2. Test via VPN: curl from VPN-connected client to the private endpoint"
echo "  3. Validate: ./scripts/validate-apim-private.sh"
