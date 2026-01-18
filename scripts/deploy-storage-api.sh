#!/bin/bash
#
# Deploy Storage API to Azure API Management
#
# This script deploys the storage-api.bicep module which creates:
# - Storage API with 4 operations (list, upload, download, delete)
# - JWT validation policy at API level
# - Storage operations policy at operation level
#

set -e

# Configuration
APIM_NAME="apim-ai-lab-0115"
APIM_RG="rg-ai-apim"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="$SCRIPT_DIR/../bicep/storage-api"

echo "=== Deploy Storage API to APIM ==="
echo "APIM: $APIM_NAME"
echo "Resource Group: $APIM_RG"
echo "Bicep Directory: $BICEP_DIR"
echo ""

# Validate bicep files exist
if [ ! -f "$BICEP_DIR/main.bicep" ]; then
    echo "ERROR: $BICEP_DIR/main.bicep not found"
    exit 1
fi

if [ ! -f "$BICEP_DIR/policies/jwt-validation.xml" ]; then
    echo "ERROR: $BICEP_DIR/policies/jwt-validation.xml not found"
    exit 1
fi

if [ ! -f "$BICEP_DIR/policies/storage-operations.xml" ]; then
    echo "ERROR: $BICEP_DIR/policies/storage-operations.xml not found"
    exit 1
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
read -p "Continue with deployment? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "[3/3] Deploying Storage API..."
az deployment group create \
    --resource-group "$APIM_RG" \
    --template-file "$BICEP_DIR/main.bicep" \
    --parameters apimName="$APIM_NAME" \
    --name "storage-api-$(date +%Y%m%d-%H%M%S)" \
    --output table

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "API Endpoints:"
echo "  List:     GET  https://$APIM_NAME.azure-api.net/storage/files"
echo "  Upload:   PUT  https://$APIM_NAME.azure-api.net/storage/files/{filename}"
echo "  Download: GET  https://$APIM_NAME.azure-api.net/storage/files/{filename}"
echo "  Delete:   DELETE https://$APIM_NAME.azure-api.net/storage/files/{filename}"
echo ""
echo "Test with:"
echo "  TOKEN=\$(az account get-access-token --resource 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 --query accessToken -o tsv)"
echo "  curl -H \"Authorization: Bearer \$TOKEN\" https://$APIM_NAME.azure-api.net/storage/files"
