# Data Model: APIM Storage OAuth Demo

**Feature**: 007-apim-storage-oauth | **Date**: 2025-01-15

This document defines the data entities, request/response structures, and policy configurations for the OAuth-protected storage API.

## Entities

### 1. BlobFile

Represents a file stored in Azure Blob Storage.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| name | string | Blob name (filename) | URL path parameter |
| contentType | string | MIME type of the file | Request Content-Type header |
| contentLength | integer | Size in bytes | Response header |
| lastModified | datetime | Last modification timestamp | Storage response |
| etag | string | Entity tag for versioning | Storage response |

**Validation Rules**:
- `name`: Required, 1-1024 characters, valid blob name characters
- `contentType`: Optional, defaults to `application/octet-stream`
- `contentLength`: Max 100MB for this demo

### 2. BlobList

Represents the list of blobs returned by the List operation.

| Field | Type | Description |
|-------|------|-------------|
| files | array[BlobInfo] | Array of blob metadata |
| count | integer | Total number of files |

### 3. BlobInfo (List Item)

Simplified blob information for list responses.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Blob name |
| contentLength | integer | Size in bytes |
| lastModified | string | ISO 8601 timestamp |
| contentType | string | MIME type |

### 4. ErrorResponse

Standard error response structure.

| Field | Type | Description |
|-------|------|-------------|
| error | object | Error details |
| error.code | string | Error code (e.g., "Unauthorized", "NotFound") |
| error.message | string | Human-readable error message |

---

## API Request/Response Models

### Upload File (PUT /storage/files/{filename})

**Request**:
```
PUT /storage/files/{filename}
Authorization: Bearer <jwt-token>
Content-Type: <mime-type>

<binary file content>
```

**Success Response (201 Created)**:
```json
{
  "name": "example.txt",
  "contentType": "text/plain",
  "contentLength": 1234,
  "etag": "0x8DC12345678ABCD"
}
```

**Error Responses**:
- 401 Unauthorized: Missing or invalid JWT token
- 400 Bad Request: Invalid filename or content
- 413 Payload Too Large: File exceeds 100MB limit

---

### List Files (GET /storage/files)

**Request**:
```
GET /storage/files
Authorization: Bearer <jwt-token>
```

**Success Response (200 OK)**:
```json
{
  "files": [
    {
      "name": "document.pdf",
      "contentLength": 102400,
      "lastModified": "2025-01-15T10:30:00Z",
      "contentType": "application/pdf"
    },
    {
      "name": "image.png",
      "contentLength": 51200,
      "lastModified": "2025-01-14T08:15:00Z",
      "contentType": "image/png"
    }
  ],
  "count": 2
}
```

**Error Responses**:
- 401 Unauthorized: Missing or invalid JWT token

---

### Download File (GET /storage/files/{filename})

**Request**:
```
GET /storage/files/{filename}
Authorization: Bearer <jwt-token>
```

**Success Response (200 OK)**:
```
Content-Type: <original-mime-type>
Content-Length: <file-size>
ETag: <etag>

<binary file content>
```

**Error Responses**:
- 401 Unauthorized: Missing or invalid JWT token
- 404 Not Found: File does not exist

---

### Delete File (DELETE /storage/files/{filename})

**Request**:
```
DELETE /storage/files/{filename}
Authorization: Bearer <jwt-token>
```

**Success Response (204 No Content)**:
```
(empty body)
```

**Error Responses**:
- 401 Unauthorized: Missing or invalid JWT token
- 404 Not Found: File does not exist

---

## State Transitions

### Blob Lifecycle

```
[Non-existent] --PUT--> [Exists] --DELETE--> [Non-existent]
                           |
                        PUT (overwrite)
                           |
                           v
                       [Updated]
```

**Notes**:
- PUT is idempotent - uploading the same filename overwrites
- No soft delete - DELETE is permanent
- No versioning enabled (can be added as enhancement)

---

## Policy Configuration Schema

### JWT Validation Settings

| Setting | Value | Description |
|---------|-------|-------------|
| Tenant ID | 38c1a7b0-f16b-45fd-a528-87d8720e868e | Entra ID tenant |
| Audience | 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 | App registration client ID |
| Issuer | https://login.microsoftonline.com/{tenant}/v2.0 | Token issuer |
| Header | Authorization | JWT location |
| Scheme | Bearer | Token prefix |

### Storage Backend Settings

| Setting | Value | Description |
|---------|-------|-------------|
| Storage Account | stailab001 | Target storage account |
| Container | data | Target container |
| Base URL | https://stailab001.blob.core.windows.net | Storage endpoint |
| API Version | 2023-11-03 | Storage REST API version |
| Auth Resource | https://storage.azure.com/ | OAuth resource for MI |

---

## Mapping: API Operations → Storage Operations

| API Operation | APIM Policy Action | Storage REST Call |
|---------------|-------------------|-------------------|
| List Files | `<send-request>` GET | `GET /data?restype=container&comp=list` |
| Download File | `<send-request>` GET | `GET /data/{filename}` |
| Upload File | `<send-request>` PUT | `PUT /data/{filename}` with `x-ms-blob-type: BlockBlob` |
| Delete File | `<send-request>` DELETE | `DELETE /data/{filename}` |

---

## XML Response Parsing (List Operation)

Azure Storage returns XML for list operations. APIM policies will transform to JSON.

**Storage Response (XML)**:
```xml
<?xml version="1.0" encoding="utf-8"?>
<EnumerationResults>
  <Blobs>
    <Blob>
      <Name>document.pdf</Name>
      <Properties>
        <Content-Length>102400</Content-Length>
        <Content-Type>application/pdf</Content-Type>
        <Last-Modified>Wed, 15 Jan 2025 10:30:00 GMT</Last-Modified>
      </Properties>
    </Blob>
  </Blobs>
</EnumerationResults>
```

**Transformed API Response (JSON)**:
```json
{
  "files": [
    {
      "name": "document.pdf",
      "contentLength": 102400,
      "contentType": "application/pdf",
      "lastModified": "2025-01-15T10:30:00Z"
    }
  ],
  "count": 1
}
```
