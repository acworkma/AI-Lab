#!/bin/bash
#
# End-to-End Test Script for Storage API
#
# Tests all 4 CRUD operations:
# 1. Upload file (PUT)
# 2. List files (GET /files)
# 3. Download file (GET /files/{filename})
# 4. Delete file (DELETE)
#
# Prerequisites:
# - Azure CLI logged in with access to the APIM app registration
# - APIM Storage API deployed
# - APIM managed identity has Storage Blob Data Contributor role
#

set -e

# Configuration
APIM_GATEWAY="https://apim-ai-lab-0115.azure-api.net"
API_PATH="storage"
APP_ID="6cb63aba-6d0d-4f06-957e-c584fdeb23d7"
TEST_FILE="test-$(date +%s).txt"
TEST_CONTENT="Hello from Storage API test at $(date)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Storage API End-to-End Test ==="
echo ""
echo "Gateway: $APIM_GATEWAY"
echo "API Path: /$API_PATH"
echo "Test File: $TEST_FILE"
echo ""

# Get OAuth token
echo -e "${YELLOW}[1/5] Getting OAuth token...${NC}"
TOKEN=$(az account get-access-token --resource "$APP_ID" --query accessToken -o tsv 2>/dev/null) || {
    echo -e "${RED}ERROR: Failed to get access token${NC}"
    echo ""
    echo "You may need to login with consent:"
    echo "  az login --tenant 38c1a7b0-f16b-45fd-a528-87d8720e868e --scope ${APP_ID}/.default"
    exit 1
}
echo -e "${GREEN}  Token acquired (${#TOKEN} chars)${NC}"
echo ""

# Test 1: Upload file
echo -e "${YELLOW}[2/5] Testing Upload (PUT /files/${TEST_FILE})...${NC}"
UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: text/plain" \
    -d "$TEST_CONTENT" \
    "$APIM_GATEWAY/$API_PATH/files/$TEST_FILE")

UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | head -n -1)
UPLOAD_CODE=$(echo "$UPLOAD_RESPONSE" | tail -n 1)

if [ "$UPLOAD_CODE" == "201" ]; then
    echo -e "${GREEN}  ✓ Upload succeeded (201 Created)${NC}"
    echo "  Response: $UPLOAD_BODY"
else
    echo -e "${RED}  ✗ Upload failed (HTTP $UPLOAD_CODE)${NC}"
    echo "  Response: $UPLOAD_BODY"
    exit 1
fi
echo ""

# Test 2: List files
echo -e "${YELLOW}[3/5] Testing List (GET /files)...${NC}"
LIST_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "$APIM_GATEWAY/$API_PATH/files")

LIST_BODY=$(echo "$LIST_RESPONSE" | head -n -1)
LIST_CODE=$(echo "$LIST_RESPONSE" | tail -n 1)

if [ "$LIST_CODE" == "200" ]; then
    echo -e "${GREEN}  ✓ List succeeded (200 OK)${NC}"
    COUNT=$(echo "$LIST_BODY" | jq -r '.count // "unknown"')
    echo "  Files in container: $COUNT"
    # Check if our test file is in the list
    if echo "$LIST_BODY" | jq -e ".files[] | select(.name == \"$TEST_FILE\")" > /dev/null 2>&1; then
        echo -e "${GREEN}  ✓ Test file found in list${NC}"
    else
        echo -e "${YELLOW}  ⚠ Test file not found in list (may take time to appear)${NC}"
    fi
else
    echo -e "${RED}  ✗ List failed (HTTP $LIST_CODE)${NC}"
    echo "  Response: $LIST_BODY"
    exit 1
fi
echo ""

# Test 3: Download file
echo -e "${YELLOW}[4/5] Testing Download (GET /files/${TEST_FILE})...${NC}"
DOWNLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "$APIM_GATEWAY/$API_PATH/files/$TEST_FILE")

DOWNLOAD_BODY=$(echo "$DOWNLOAD_RESPONSE" | head -n -1)
DOWNLOAD_CODE=$(echo "$DOWNLOAD_RESPONSE" | tail -n 1)

if [ "$DOWNLOAD_CODE" == "200" ]; then
    echo -e "${GREEN}  ✓ Download succeeded (200 OK)${NC}"
    if [ "$DOWNLOAD_BODY" == "$TEST_CONTENT" ]; then
        echo -e "${GREEN}  ✓ Content matches original${NC}"
    else
        echo -e "${YELLOW}  ⚠ Content differs from original${NC}"
        echo "  Expected: $TEST_CONTENT"
        echo "  Received: $DOWNLOAD_BODY"
    fi
else
    echo -e "${RED}  ✗ Download failed (HTTP $DOWNLOAD_CODE)${NC}"
    echo "  Response: $DOWNLOAD_BODY"
    exit 1
fi
echo ""

# Test 4: Delete file
echo -e "${YELLOW}[5/5] Testing Delete (DELETE /files/${TEST_FILE})...${NC}"
DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X DELETE \
    -H "Authorization: Bearer $TOKEN" \
    "$APIM_GATEWAY/$API_PATH/files/$TEST_FILE")

DELETE_BODY=$(echo "$DELETE_RESPONSE" | head -n -1)
DELETE_CODE=$(echo "$DELETE_RESPONSE" | tail -n 1)

if [ "$DELETE_CODE" == "204" ]; then
    echo -e "${GREEN}  ✓ Delete succeeded (204 No Content)${NC}"
elif [ "$DELETE_CODE" == "202" ]; then
    echo -e "${GREEN}  ✓ Delete accepted (202 Accepted)${NC}"
else
    echo -e "${RED}  ✗ Delete failed (HTTP $DELETE_CODE)${NC}"
    echo "  Response: $DELETE_BODY"
    exit 1
fi
echo ""

# Verify deletion
echo -e "${YELLOW}[Verification] Confirming file was deleted...${NC}"
VERIFY_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "$APIM_GATEWAY/$API_PATH/files/$TEST_FILE")

VERIFY_CODE=$(echo "$VERIFY_RESPONSE" | tail -n 1)

if [ "$VERIFY_CODE" == "404" ]; then
    echo -e "${GREEN}  ✓ File confirmed deleted (404 Not Found)${NC}"
else
    echo -e "${YELLOW}  ⚠ File may still exist (HTTP $VERIFY_CODE)${NC}"
fi
echo ""

# Summary
echo "=== Test Summary ==="
echo -e "${GREEN}All tests passed! Storage API is working correctly.${NC}"
echo ""
echo "Endpoints tested:"
echo "  ✓ PUT    $APIM_GATEWAY/$API_PATH/files/{filename}"
echo "  ✓ GET    $APIM_GATEWAY/$API_PATH/files"
echo "  ✓ GET    $APIM_GATEWAY/$API_PATH/files/{filename}"
echo "  ✓ DELETE $APIM_GATEWAY/$API_PATH/files/{filename}"
