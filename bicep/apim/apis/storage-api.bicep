// Storage API for Azure API Management
// 
// Provides OAuth-protected access to Azure Blob Storage
// Uses APIM managed identity for storage authentication
//
// Operations:
// - PUT /files/{filename}    - Upload blob
// - GET /files               - List blobs  
// - GET /files/{filename}    - Download blob
// - DELETE /files/{filename} - Delete blob

@description('Name of the API Management instance')
param apimName string

@description('Display name for the Storage API')
param apiDisplayName string = 'Storage API'

@description('Path prefix for the API')
param apiPath string = 'storage'

// Reference existing APIM instance
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimName
}

// Storage API definition
resource storageApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'storage-api'
  properties: {
    displayName: apiDisplayName
    description: 'OAuth-protected API for Azure Blob Storage operations using APIM managed identity'
    subscriptionRequired: false
    path: apiPath
    protocols: [
      'https'
    ]
    serviceUrl: 'https://stailab001.blob.core.windows.net'
    isCurrent: true
  }
}

// List files operation - GET /files
resource listFilesOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: storageApi
  name: 'list-files'
  properties: {
    displayName: 'List Files'
    description: 'Returns a list of all files in the storage container'
    method: 'GET'
    urlTemplate: '/files'
    responses: [
      {
        statusCode: 200
        description: 'Successful response with file list'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
      {
        statusCode: 401
        description: 'Unauthorized - missing or invalid token'
      }
    ]
  }
}

// Upload file operation - PUT /files/{filename}
resource uploadFileOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: storageApi
  name: 'upload-file'
  properties: {
    displayName: 'Upload File'
    description: 'Uploads a file to the storage container'
    method: 'PUT'
    urlTemplate: '/files/{filename}'
    templateParameters: [
      {
        name: 'filename'
        description: 'Name of the file to upload'
        type: 'string'
        required: true
      }
    ]
    responses: [
      {
        statusCode: 201
        description: 'File created successfully'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
      {
        statusCode: 401
        description: 'Unauthorized - missing or invalid token'
      }
    ]
  }
}

// Download file operation - GET /files/{filename}
resource downloadFileOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: storageApi
  name: 'download-file'
  properties: {
    displayName: 'Download File'
    description: 'Downloads a specific file from storage'
    method: 'GET'
    urlTemplate: '/files/{filename}'
    templateParameters: [
      {
        name: 'filename'
        description: 'Name of the file to download'
        type: 'string'
        required: true
      }
    ]
    responses: [
      {
        statusCode: 200
        description: 'File content'
      }
      {
        statusCode: 401
        description: 'Unauthorized - missing or invalid token'
      }
      {
        statusCode: 404
        description: 'File not found'
      }
    ]
  }
}

// Delete file operation - DELETE /files/{filename}
resource deleteFileOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: storageApi
  name: 'delete-file'
  properties: {
    displayName: 'Delete File'
    description: 'Deletes a file from storage'
    method: 'DELETE'
    urlTemplate: '/files/{filename}'
    templateParameters: [
      {
        name: 'filename'
        description: 'Name of the file to delete'
        type: 'string'
        required: true
      }
    ]
    responses: [
      {
        statusCode: 204
        description: 'File deleted successfully'
      }
      {
        statusCode: 401
        description: 'Unauthorized - missing or invalid token'
      }
      {
        statusCode: 404
        description: 'File not found'
      }
    ]
  }
}

// API-level policy for JWT validation
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: storageApi
  name: 'policy'
  properties: {
    value: loadTextContent('../policies/jwt-validation.xml')
    format: 'xml'
  }
}

// Operation-level policies for storage operations

// List files policy
resource listFilesPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: listFilesOperation
  name: 'policy'
  properties: {
    value: loadTextContent('../policies/storage-operations.xml')
    format: 'xml'
  }
}

// Upload file policy
resource uploadFilePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: uploadFileOperation
  name: 'policy'
  properties: {
    value: loadTextContent('../policies/storage-operations.xml')
    format: 'xml'
  }
}

// Download file policy
resource downloadFilePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: downloadFileOperation
  name: 'policy'
  properties: {
    value: loadTextContent('../policies/storage-operations.xml')
    format: 'xml'
  }
}

// Delete file policy
resource deleteFilePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: deleteFileOperation
  name: 'policy'
  properties: {
    value: loadTextContent('../policies/storage-operations.xml')
    format: 'xml'
  }
}

// Outputs
output apiId string = storageApi.id
output apiName string = storageApi.name
output apiPath string = storageApi.properties.path
