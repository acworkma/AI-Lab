# Research: APIM Storage OAuth Demo

**Feature**: 007-apim-storage-oauth | **Date**: 2025-01-15

This document captures research findings for implementing OAuth-protected blob storage operations via Azure API Management using managed identity authentication.

## Research Questions

### RQ-1: How does APIM authenticate to Azure Blob Storage using managed identity?

**Decision**: Use the `authentication-managed-identity` policy with resource `https://storage.azure.com/`

**Rationale**: 
- Azure API Management provides a built-in policy `<authentication-managed-identity>` that obtains an OAuth 2.0 token from Entra ID for the specified resource
- For Azure Storage, the resource URI is `https://storage.azure.com/` (trailing slash is important for some scenarios)
- The policy automatically sets the `Authorization: Bearer <token>` header
- Token is cached by APIM until expiration

**Policy Example**:
```xml
<authentication-managed-identity resource="https://storage.azure.com/" 
    output-token-variable-name="storage-token" 
    ignore-error="false" />
```

**Alternatives Considered**:
- **SAS Tokens**: Rejected because they require secret management and rotation
- **Storage Account Keys**: Rejected because they violate zero-trust principles and require secret storage
- **Service Principal with Client Secret**: Rejected because it requires storing secrets in Key Vault

**Source**: [Microsoft Learn - authentication-managed-identity policy](https://learn.microsoft.com/en-us/azure/api-management/authentication-managed-identity-policy)

---

### RQ-2: What RBAC role does APIM's managed identity need on the storage account?

**Decision**: Assign `Storage Blob Data Contributor` role

**Rationale**:
- `Storage Blob Data Contributor` allows read, write, and delete access to blob containers and data
- This is the minimum role that supports all CRUD operations (upload, list, download, delete)
- `Storage Blob Data Reader` would be insufficient as it doesn't allow uploads/deletes
- `Owner` or `Contributor` roles are NOT sufficient - they only grant management plane access, not data plane access

**RBAC Assignment Command**:
```bash
# Get APIM principal ID
APIM_PRINCIPAL_ID="c856d119-9ba7-48b6-a627-047c01014d82"
STORAGE_ACCOUNT_ID=$(az storage account show -n stailab001 -g rg-ai-storage --query id -o tsv)

# Assign role
az role assignment create \
    --assignee "$APIM_PRINCIPAL_ID" \
    --role "Storage Blob Data Contributor" \
    --scope "$STORAGE_ACCOUNT_ID"
```

**Alternatives Considered**:
- **Container-scoped role**: Could scope to just the `data` container for tighter access, but account-level is acceptable for demo purposes
- **Storage Blob Data Owner**: More permissive than needed, includes ability to manage ACLs

**Source**: [Microsoft Learn - Access Azure Storage with managed identities](https://learn.microsoft.com/en-us/entra/identity-platform/multi-service-web-app-access-storage)

---

### RQ-3: How should APIM policies construct Azure Storage REST API calls?

**Decision**: Use `<send-request>` policy with constructed Storage REST API URLs

**Rationale**:
- Azure Blob Storage REST API uses specific URL patterns and headers
- APIM must construct proper URLs: `https://{account}.blob.core.windows.net/{container}/{blob}`
- Required headers for Storage API:
  - `x-ms-version`: API version (use `2023-11-03` for latest stable)
  - `x-ms-blob-type`: `BlockBlob` for uploads
  - `x-ms-date`: Current UTC date in RFC 1123 format (optional with OAuth)
  - `Authorization`: Bearer token (set by managed identity policy)
  - `Content-Type`: Appropriate MIME type

**Operation URL Patterns**:
| Operation | Method | URL Pattern |
|-----------|--------|-------------|
| Upload | PUT | `https://stailab001.blob.core.windows.net/data/{blobName}` |
| Download | GET | `https://stailab001.blob.core.windows.net/data/{blobName}` |
| Delete | DELETE | `https://stailab001.blob.core.windows.net/data/{blobName}` |
| List | GET | `https://stailab001.blob.core.windows.net/data?restype=container&comp=list` |

**Required Headers for Upload**:
```xml
<set-header name="x-ms-version" exists-action="override">
    <value>2023-11-03</value>
</set-header>
<set-header name="x-ms-blob-type" exists-action="override">
    <value>BlockBlob</value>
</set-header>
```

**Alternatives Considered**:
- **Azure Blob Storage Backend**: APIM can configure storage as a named backend, but direct URL construction gives more control for the demo
- **Proxy passthrough**: Simply proxying requests would require the client to know storage URLs, breaking abstraction

**Source**: [Azure Storage REST API Reference](https://learn.microsoft.com/en-us/rest/api/storageservices/)

---

### RQ-4: How should APIM validate incoming JWT tokens from clients?

**Decision**: Use `<validate-jwt>` policy with Entra ID OIDC configuration

**Rationale**:
- APIM's `validate-jwt` policy can validate tokens issued by Entra ID
- Configuration requires:
  - `openid-config` URL: `https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration`
  - Required claims validation (audience, issuer)
- Token validation happens before managed identity authentication to storage

**Policy Pattern**:
```xml
<validate-jwt header-name="Authorization" failed-validation-httpcode="401" 
              failed-validation-error-message="Unauthorized. Access token is missing or invalid.">
    <openid-config url="https://login.microsoftonline.com/38c1a7b0-f16b-45fd-a528-87d8720e868e/v2.0/.well-known/openid-configuration" />
    <audiences>
        <audience>6cb63aba-6d0d-4f06-957e-c584fdeb23d7</audience>
    </audiences>
    <issuers>
        <issuer>https://login.microsoftonline.com/38c1a7b0-f16b-45fd-a528-87d8720e868e/v2.0</issuer>
    </issuers>
</validate-jwt>
```

**Alternatives Considered**:
- **Subscription keys only**: Would not provide user identity or leverage Entra ID
- **Basic Auth**: Insecure and doesn't integrate with Entra ID
- **API Key + JWT**: Redundant for this demo scenario

**Source**: [Microsoft Learn - validate-jwt policy](https://learn.microsoft.com/en-us/azure/api-management/validate-jwt-policy)

---

### RQ-5: How should clients obtain OAuth tokens for testing?

**Decision**: Use Azure CLI or MSAL for token acquisition

**Rationale**:
- For demo/testing, Azure CLI provides the simplest way to obtain tokens:
  ```bash
  az account get-access-token --resource 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 --query accessToken -o tsv
  ```
- The existing app registration `apim-ai-lab-0115-devportal` (client ID: `6cb63aba-6d0d-4f06-957e-c584fdeb23d7`) can be used as the audience
- For automated testing, a service principal with client credentials can be used

**Test Flow**:
1. User signs in via Azure CLI: `az login`
2. Get token for the API audience: `az account get-access-token --resource <app-id>`
3. Include token in API request: `curl -H "Authorization: Bearer $TOKEN" ...`

**Alternatives Considered**:
- **MSAL Library**: More complex but required for production apps
- **Device Code Flow**: Suitable for CLI apps without browser
- **Client Credentials Flow**: For service-to-service, no user context

---

### RQ-6: How should the API surface be structured?

**Decision**: RESTful API with `/storage` base path

**Rationale**:
- Simple, intuitive REST design matching common patterns
- Clear operation mapping to HTTP methods

**API Endpoints**:
| Endpoint | Method | Description | Storage Operation |
|----------|--------|-------------|-------------------|
| `/storage/files` | GET | List all files | List Blobs |
| `/storage/files/{filename}` | GET | Download file | Get Blob |
| `/storage/files/{filename}` | PUT | Upload file | Put Blob |
| `/storage/files/{filename}` | DELETE | Delete file | Delete Blob |

**URL Design Decisions**:
- Base path: `/storage` to clearly indicate storage operations
- Resource: `/files` as the collection endpoint
- Individual resource: `/{filename}` as path parameter
- Using PUT instead of POST for uploads because the client specifies the filename (idempotent)

---

## Technology Decisions Summary

| Decision | Choice | Key Reason |
|----------|--------|------------|
| Storage Auth | Managed Identity | Zero secrets, automatic token refresh |
| Client Auth | JWT (Entra ID) | Standard OAuth 2.0, integrates with existing app reg |
| API Pattern | RESTful | Simple, intuitive, matches HTTP semantics |
| APIM Policy | authentication-managed-identity | Built-in, reliable, cached tokens |
| RBAC Role | Storage Blob Data Contributor | Minimum role for all CRUD operations |
| Storage API Version | 2023-11-03 | Latest stable version |

## Dependencies Verified

| Dependency | Status | Notes |
|------------|--------|-------|
| APIM Instance | ✅ Ready | apim-ai-lab-0115 in rg-ai-apim |
| System Managed Identity | ✅ Ready | Principal ID: c856d119-9ba7-48b6-a627-047c01014d82 |
| Storage Account | ✅ Ready | stailab001 in rg-ai-storage |
| Storage Container | ✅ Ready | Container: data |
| App Registration | ✅ Ready | ID: 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 |

## Outstanding Items for Implementation

1. **Grant RBAC Role**: APIM MI needs Storage Blob Data Contributor on stailab001
2. **Create APIM API**: Define storage-api with 4 operations
3. **Create APIM Policies**: JWT validation + managed identity auth + storage requests
4. **Test End-to-End**: Obtain token, call each endpoint, verify storage operations
