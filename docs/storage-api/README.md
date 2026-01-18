# Storage API Guide

OAuth-protected API for Azure Blob Storage operations via Azure API Management.

## Overview

The Storage API provides a secure REST interface for uploading, listing, downloading, and deleting files in Azure Blob Storage. All operations require OAuth 2.0 authentication via Microsoft Entra ID.

### Architecture

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Client    │──────│  Azure APIM     │──────│  Blob Storage   │
│  (OAuth)    │ JWT  │  (Managed ID)   │ MI   │  (stailab0117)  │
└─────────────┘      └─────────────────┘      └─────────────────┘
```

1. Client authenticates with Entra ID and gets JWT token
2. Client calls APIM with Bearer token
3. APIM validates JWT and uses Managed Identity to call Storage
4. Storage response is transformed and returned to client

## Endpoints

Base URL: `https://apim-ai-lab-0115.azure-api.net/storage`

| Operation | Method | Endpoint | Description |
|-----------|--------|----------|-------------|
| Upload | PUT | `/files/{filename}` | Upload a file |
| List | GET | `/files` | List all files |
| Download | GET | `/files/{filename}` | Download a file |
| Delete | DELETE | `/files/{filename}` | Delete a file |

## Authentication

All requests require a valid OAuth 2.0 bearer token from Microsoft Entra ID.

### Getting a Token

```bash
# Azure CLI (for development/testing)
TOKEN=$(az account get-access-token \
    --resource 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 \
    --query accessToken -o tsv)

# Use the token
curl -H "Authorization: Bearer $TOKEN" \
    https://apim-ai-lab-0115.azure-api.net/storage/files
```

### Token Requirements

| Claim | Required Value |
|-------|----------------|
| `aud` | `6cb63aba-6d0d-4f06-957e-c584fdeb23d7` or `api://6cb63aba-6d0d-4f06-957e-c584fdeb23d7` |
| `iss` | `https://login.microsoftonline.com/38c1a7b0-f16b-45fd-a528-87d8720e868e/v2.0` |
| `exp` | Must not be expired |

## API Operations

### 1. Upload File

Upload a file to blob storage.

```bash
curl -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: text/plain" \
    -d "Hello, World!" \
    https://apim-ai-lab-0115.azure-api.net/storage/files/hello.txt
```

**Response (201 Created)**:
```json
{
    "name": "hello.txt",
    "contentType": "text/plain",
    "contentLength": 13,
    "etag": "\"0x8DCF1234567890\""
}
```

### 2. List Files

Get a list of all files in the container.

```bash
curl -H "Authorization: Bearer $TOKEN" \
    https://apim-ai-lab-0115.azure-api.net/storage/files
```

**Response (200 OK)**:
```json
{
    "files": [
        {
            "name": "hello.txt",
            "contentLength": 13,
            "lastModified": "Wed, 15 Jan 2026 12:00:00 GMT",
            "contentType": "text/plain"
        },
        {
            "name": "data.json",
            "contentLength": 256,
            "lastModified": "Wed, 15 Jan 2026 12:30:00 GMT",
            "contentType": "application/json"
        }
    ],
    "count": 2
}
```

### 3. Download File

Download a specific file.

```bash
curl -H "Authorization: Bearer $TOKEN" \
    https://apim-ai-lab-0115.azure-api.net/storage/files/hello.txt
```

**Response (200 OK)**:
```
Hello, World!
```

The response includes appropriate `Content-Type` and `Content-Length` headers.

### 4. Delete File

Delete a file from storage.

```bash
curl -X DELETE \
    -H "Authorization: Bearer $TOKEN" \
    https://apim-ai-lab-0115.azure-api.net/storage/files/hello.txt
```

**Response (204 No Content)**: Empty body

## Error Responses

All error responses follow this format:

```json
{
    "error": {
        "code": "ErrorCode",
        "message": "Human-readable error message"
    }
}
```

### Common Errors

| Status | Code | Description |
|--------|------|-------------|
| 401 | Unauthorized | Missing or invalid JWT token |
| 404 | NotFound | File does not exist |
| 500 | InternalError | Unexpected server error |

## Testing

Use the provided test script to verify all operations:

```bash
./scripts/test-storage-api.sh
```

This script:
1. Gets an OAuth token
2. Uploads a test file
3. Lists files to verify upload
4. Downloads and verifies content
5. Deletes the test file
6. Confirms deletion

## Deployment

### Prerequisites

1. APIM Standard v2 deployed (apim-ai-lab-0115)
2. Storage account with container (stailab0117/data)
3. App Registration for OAuth (6cb63aba-6d0d-4f06-957e-c584fdeb23d7)
4. APIM Managed Identity has Storage Blob Data Contributor role

### Deploy/Update the API

```bash
./scripts/deploy-storage-api.sh
```

### Grant RBAC (if needed)

```bash
./scripts/grant-apim-storage-role.sh
```

## Configuration

### Environment Details

| Resource | Name | Resource Group |
|----------|------|----------------|
| APIM | apim-ai-lab-0115 | rg-ai-apim |
| Storage | stailab0117 | rg-ai-storage |
| Container | data | - |
| App Registration | apim-ai-lab-0115-devportal | - |
| Tenant | 38c1a7b0-f16b-45fd-a528-87d8720e868e | - |

### File Paths

- API Definition: `bicep/storage-api/main.bicep`
- JWT Policy: `bicep/storage-api/policies/jwt-validation.xml`
- Operations Policy: `bicep/storage-api/policies/storage-operations.xml`
- Deployment Script: `scripts/deploy-storage-api.sh`
- Test Script: `scripts/test-storage-api.sh`

## Troubleshooting

### "JWT not present"

Ensure you include the `Authorization: Bearer <token>` header.

### "Access token is missing or invalid"

- Token may be expired (default 1 hour lifetime)
- Wrong audience - token must be for app ID `6cb63aba-6d0d-4f06-957e-c584fdeb23d7`
- Re-authenticate: `az login --tenant 38c1a7b0-f16b-45fd-a528-87d8720e868e`

### 403 Forbidden from Storage

- APIM Managed Identity may not have Storage Blob Data Contributor role
- Run `./scripts/grant-apim-storage-role.sh`

### Container not found

- Verify container "data" exists in storage account stailab0117
- Check storage account firewall settings allow APIM access

## Related Documentation

- [OAuth/Entra ID Setup](oauth-setup.md) - Configure app registrations and JWT validation
- [API Import Guide](import-api.md) - Import OpenAPI specs, Function Apps, and manual APIs
- [APIM Infrastructure](README.md) - Deploy the underlying API Management instance
