# Feature Specification: APIM Storage OAuth Demo

**Feature Branch**: `007-apim-storage-oauth`  
**Created**: 2026-01-15  
**Status**: Draft  
**Project Type**: Solution  
**Input**: User description: "OAuth client calling APIM to interact with storage account using managed identity"

## Overview

This Solutions project demonstrates an end-to-end OAuth-secured API flow where:
1. A client authenticates via OAuth 2.0 (Entra ID)
2. Calls an API exposed through Azure API Management
3. APIM validates the JWT token
4. APIM uses its managed identity to read/write to Azure Blob Storage
5. Returns results to the authenticated client

### Infrastructure Dependencies

| Resource | Name | Resource Group | Details |
|----------|------|----------------|---------|
| APIM | apim-ai-lab-0115 | rg-ai-apim | Gateway: https://apim-ai-lab-0115.azure-api.net |
| APIM Managed Identity | c856d119-9ba7-48b6-a627-047c01014d82 | rg-ai-apim | System-assigned |
| Storage Account | stailab001 | rg-ai-storage | Blob: https://stailab001.blob.core.windows.net/ |
| Storage Container | data | rg-ai-storage | Existing container for demo |
| Key Vault | kv-ai-core-lab1 | rg-ai-core | For any secrets if needed |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Upload File via OAuth-Protected API (Priority: P1)

An authenticated client uploads a file to blob storage through the APIM-protected API. The client obtains an OAuth token from Entra ID, calls the APIM endpoint with the bearer token, and APIM uses its managed identity to write the blob.

**Why this priority**: Core write functionality - proves the OAuth → APIM → Managed Identity → Storage flow works end-to-end.

**Independent Test**: Can be tested with a curl command using a valid bearer token to upload a file and verify it appears in the storage container.

**Acceptance Scenarios**:

1. **Given** a client with a valid OAuth token, **When** they PUT a file to `/storage/files/{filename}`, **Then** the file is stored in the `data` container and a success response (201) is returned.
2. **Given** a client with an expired OAuth token, **When** they PUT a file to `/storage/files/{filename}`, **Then** a 401 Unauthorized response is returned.
3. **Given** a client with no token, **When** they PUT a file to `/storage/files/{filename}`, **Then** a 401 Unauthorized response is returned.

---

### User Story 2 - List Files via OAuth-Protected API (Priority: P1)

An authenticated client lists files in the storage container through the APIM-protected API.

**Why this priority**: Core read functionality - demonstrates managed identity can read from storage.

**Independent Test**: Can be tested with a curl command using a valid bearer token to list files and verify the response contains expected blob names.

**Acceptance Scenarios**:

1. **Given** a client with a valid OAuth token, **When** they GET `/storage/files`, **Then** a JSON array of file names is returned with a 200 status.
2. **Given** the container has 3 files, **When** an authenticated client calls GET `/storage/files`, **Then** all 3 file names are returned.

---

### User Story 3 - Download File via OAuth-Protected API (Priority: P2)

An authenticated client downloads a specific file from storage through the APIM-protected API.

**Why this priority**: Completes the CRUD operations but less critical than upload/list for initial demo.

**Independent Test**: Can be tested by uploading a file, then downloading it and verifying content matches.

**Acceptance Scenarios**:

1. **Given** a file `test.txt` exists in the container, **When** an authenticated client calls GET `/storage/files/test.txt`, **Then** the file content is returned with appropriate content-type.
2. **Given** a file does not exist, **When** an authenticated client calls GET `/storage/files/missing.txt`, **Then** a 404 Not Found is returned.

---

### User Story 4 - Delete File via OAuth-Protected API (Priority: P3)

An authenticated client deletes a file from storage through the APIM-protected API.

**Why this priority**: Destructive operation, lower priority for initial demo.

**Independent Test**: Can be tested by uploading a file, deleting it, and verifying it no longer appears in list.

**Acceptance Scenarios**:

1. **Given** a file `deleteme.txt` exists, **When** an authenticated client calls DELETE `/storage/files/deleteme.txt`, **Then** the file is removed and a 204 No Content is returned.

---

### Edge Cases

- What happens when the blob name contains special characters?
- How does the system handle files larger than 4MB (chunked upload)?
- What happens if APIM managed identity loses storage permissions?
- How does the system handle concurrent uploads to the same filename?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST validate OAuth 2.0 bearer tokens on all API endpoints
- **FR-002**: System MUST reject requests with missing, expired, or invalid tokens with 401 status
- **FR-003**: System MUST use APIM's managed identity (not connection strings) to access storage
- **FR-004**: System MUST support upload (POST), list (GET), download (GET), and delete (DELETE) operations
- **FR-005**: System MUST return appropriate HTTP status codes (200, 201, 204, 400, 401, 404, 500)
- **FR-006**: System MUST set correct Content-Type headers for file downloads
- **FR-007**: System MUST log all API calls for auditing purposes

### Non-Functional Requirements

- **NFR-001**: API responses MUST complete within 5 seconds for files under 1MB
- **NFR-002**: System MUST work with APIM Standard v2 tier
- **NFR-003**: Solution MUST NOT require any stored credentials or connection strings

### Key Entities

- **API Endpoint**: RESTful endpoints exposed through APIM for storage operations
- **OAuth Token**: Entra ID issued JWT token containing user claims and audience
- **Blob**: File stored in Azure Blob Storage container
- **APIM Policy**: XML policies for JWT validation and backend authentication

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Authenticated clients can upload files to storage in under 3 seconds (for files < 1MB)
- **SC-002**: JWT validation correctly rejects 100% of invalid/expired tokens
- **SC-003**: All 4 CRUD operations (create, read, list, delete) work via the API
- **SC-004**: Zero secrets or connection strings stored in code or configuration
- **SC-005**: Demo can be executed end-to-end using only curl commands and a valid token

## Assumptions

- APIM instance (apim-ai-lab-0115) is already deployed and accessible
- Storage account (stailab001) is already deployed with `data` container
- APIM managed identity will be granted Storage Blob Data Contributor role on the storage account
- Entra ID app registration exists for obtaining client tokens (can use existing apim-ai-lab-0115-devportal app or create new one)
- Client testing will use audience matching the APIM app registration

## Out of Scope

- Custom domain configuration for APIM
- Private endpoint for storage (uses public endpoint with managed identity auth)
- File chunking for large files (> 100MB)
- User-level authorization (all authenticated users have same permissions)
