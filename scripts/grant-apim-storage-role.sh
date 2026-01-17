#!/bin/bash
#
# Grant APIM Managed Identity access to Storage Account
# This script assigns the Storage Blob Data Contributor role to APIM's system-assigned managed identity
#

set -e

# Configuration
APIM_NAME="apim-ai-lab-0115"
APIM_RG="rg-ai-apim"
STORAGE_ACCOUNT="stailab001"
STORAGE_RG="rg-ai-storage"
ROLE="Storage Blob Data Contributor"

echo "=== Grant APIM Storage Role ==="
echo "APIM: $APIM_NAME"
echo "Storage: $STORAGE_ACCOUNT"
echo "Role: $ROLE"
echo ""

# Get APIM managed identity principal ID
echo "[1/3] Getting APIM managed identity principal ID..."
APIM_PRINCIPAL_ID=$(az apim show \
    --name "$APIM_NAME" \
    --resource-group "$APIM_RG" \
    --query "identity.principalId" \
    --output tsv)

if [ -z "$APIM_PRINCIPAL_ID" ]; then
    echo "ERROR: Could not retrieve APIM managed identity principal ID"
    echo "Ensure APIM has a system-assigned managed identity enabled"
    exit 1
fi

echo "  Principal ID: $APIM_PRINCIPAL_ID"

# Get storage account resource ID
echo "[2/3] Getting storage account resource ID..."
STORAGE_ID=$(az storage account show \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$STORAGE_RG" \
    --query "id" \
    --output tsv)

if [ -z "$STORAGE_ID" ]; then
    echo "ERROR: Could not retrieve storage account resource ID"
    exit 1
fi

echo "  Storage ID: $STORAGE_ID"

# Check if role assignment already exists
echo "[3/3] Checking/creating role assignment..."
EXISTING=$(az role assignment list \
    --assignee "$APIM_PRINCIPAL_ID" \
    --role "$ROLE" \
    --scope "$STORAGE_ID" \
    --query "[0].id" \
    --output tsv 2>/dev/null || true)

if [ -n "$EXISTING" ]; then
    echo "  Role assignment already exists"
    echo "  Assignment ID: $EXISTING"
else
    echo "  Creating new role assignment..."
    az role assignment create \
        --assignee "$APIM_PRINCIPAL_ID" \
        --role "$ROLE" \
        --scope "$STORAGE_ID" \
        --output table
    echo "  Role assignment created successfully"
fi

echo ""
echo "=== Complete ==="
echo "APIM '$APIM_NAME' can now access storage account '$STORAGE_ACCOUNT' with role '$ROLE'"
