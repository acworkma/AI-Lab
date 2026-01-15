# Quickstart: APIM Storage OAuth Demo

**Feature**: 007-apim-storage-oauth | **Date**: 2025-01-15

This guide helps you get started with the OAuth-protected Storage API in under 10 minutes.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Access to the Azure subscription with deployed resources:
  - APIM: `apim-ai-lab-0115` in `rg-ai-apim`
  - Storage: `stailab001` in `rg-ai-storage`
- Storage API deployed to APIM (see deployment instructions)

## Quick Test (5 minutes)

### Step 1: Get an Access Token

```bash
# Set the app registration ID (audience)
APP_ID="6cb63aba-6d0d-4f06-957e-c584fdeb23d7"

# Get a token for the API
TOKEN=$(az account get-access-token --resource $APP_ID --query accessToken -o tsv)

# Verify token was obtained
echo "Token length: ${#TOKEN}"
```

### Step 2: List Files

```bash
# Set the API base URL
API_URL="https://apim-ai-lab-0115.azure-api.net/storage"

# List files in the container
curl -s -X GET "$API_URL/files" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json" | jq .
```

Expected output:
```json
{
  "files": [],
  "count": 0
}
```

### Step 3: Upload a File

```bash
# Create a test file
echo "Hello, Storage API!" > /tmp/test.txt

# Upload the file
curl -s -X PUT "$API_URL/files/test.txt" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: text/plain" \
  --data-binary @/tmp/test.txt | jq .
```

Expected output:
```json
{
  "name": "test.txt",
  "contentType": "text/plain",
  "contentLength": 20,
  "etag": "0x8DC..."
}
```

### Step 4: Download the File

```bash
# Download the file
curl -s -X GET "$API_URL/files/test.txt" \
  -H "Authorization: Bearer $TOKEN"
```

Expected output:
```
Hello, Storage API!
```

### Step 5: Delete the File

```bash
# Delete the file
curl -s -X DELETE "$API_URL/files/test.txt" \
  -H "Authorization: Bearer $TOKEN" \
  -w "HTTP Status: %{http_code}\n"
```

Expected output:
```
HTTP Status: 204
```

### Step 6: Verify Deletion

```bash
# Try to download deleted file
curl -s -X GET "$API_URL/files/test.txt" \
  -H "Authorization: Bearer $TOKEN" \
  -w "\nHTTP Status: %{http_code}\n"
```

Expected output:
```json
{"error":{"code":"NotFound","message":"The specified file does not exist"}}
HTTP Status: 404
```

---

## Complete Test Script

Save this as `test-storage-api.sh`:

```bash
#!/bin/bash
set -e

# Configuration
APP_ID="6cb63aba-6d0d-4f06-957e-c584fdeb23d7"
API_URL="https://apim-ai-lab-0115.azure-api.net/storage"

echo "=== Storage API Quickstart Test ==="

# Step 1: Get token
echo -e "\n[1/6] Getting access token..."
TOKEN=$(az account get-access-token --resource $APP_ID --query accessToken -o tsv)
echo "Token obtained (${#TOKEN} chars)"

# Step 2: List files
echo -e "\n[2/6] Listing files..."
curl -s -X GET "$API_URL/files" \
  -H "Authorization: Bearer $TOKEN" | jq .

# Step 3: Upload file
echo -e "\n[3/6] Uploading test.txt..."
echo "Hello from quickstart test!" > /tmp/quickstart-test.txt
curl -s -X PUT "$API_URL/files/quickstart-test.txt" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: text/plain" \
  --data-binary @/tmp/quickstart-test.txt | jq .

# Step 4: Download file
echo -e "\n[4/6] Downloading test.txt..."
curl -s -X GET "$API_URL/files/quickstart-test.txt" \
  -H "Authorization: Bearer $TOKEN"
echo ""

# Step 5: Delete file
echo -e "\n[5/6] Deleting test.txt..."
HTTP_CODE=$(curl -s -X DELETE "$API_URL/files/quickstart-test.txt" \
  -H "Authorization: Bearer $TOKEN" \
  -w "%{http_code}" -o /dev/null)
echo "Delete returned HTTP $HTTP_CODE"

# Step 6: Verify deletion
echo -e "\n[6/6] Verifying deletion..."
HTTP_CODE=$(curl -s -X GET "$API_URL/files/quickstart-test.txt" \
  -H "Authorization: Bearer $TOKEN" \
  -w "%{http_code}" -o /dev/null)
echo "Get after delete returned HTTP $HTTP_CODE"

echo -e "\n=== Quickstart Test Complete ==="
```

Run it:
```bash
chmod +x test-storage-api.sh
./test-storage-api.sh
```

---

## Troubleshooting

### Error: 401 Unauthorized

1. **Token expired**: Tokens are valid for ~1 hour. Get a new one:
   ```bash
   TOKEN=$(az account get-access-token --resource $APP_ID --query accessToken -o tsv)
   ```

2. **Wrong audience**: Ensure APP_ID matches the app registration

3. **Not logged in**: Run `az login` first

### Error: 403 Forbidden

- APIM managed identity doesn't have Storage Blob Data Contributor role
- Contact admin to run: `scripts/grant-apim-storage-role.sh`

### Error: 404 on API endpoint

- Storage API not deployed to APIM
- Check API exists: `az apim api list --resource-group rg-ai-apim --service-name apim-ai-lab-0115`

### Error: Connection refused

- APIM might be starting up (Standard v2 can take a few minutes)
- Check APIM status in Azure Portal

---

## Next Steps

- **Automated Testing**: See `scripts/test-storage-api.sh` for full test suite
- **API Documentation**: Import `contracts/storage-api.yaml` into your API client
- **Integration**: Use the API from your applications with MSAL for token acquisition
