// MCP API for Azure API Management
//
// Exposes the MCP server (running in ACA) through APIM as a public API
// with Entra ID JWT authentication. Simple passthrough for MCP streamable
// HTTP (SSE) transport.
//
// Operations:
// - POST /  - MCP endpoint (JSON-RPC 2.0 over HTTP with SSE responses)

@description('Name of the API Management instance')
param apimName string

@description('Display name for the MCP API')
param apiDisplayName string = 'MCP API'

@description('Path prefix for the API')
param apiPath string = 'mcp'

@description('Backend URL for the MCP server in ACA (includes /mcp path)')
param backendUrl string = 'https://mcp-server.delightfulocean-ec53e247.eastus2.azurecontainerapps.io/mcp'

// Reference existing APIM instance
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimName
}

// MCP API definition
resource mcpApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'mcp-api'
  properties: {
    displayName: apiDisplayName
    description: 'MCP (Model Context Protocol) server exposed via APIM with Entra ID JWT authentication. Proxies streamable HTTP (SSE) requests to ACA backend.'
    subscriptionRequired: false
    path: apiPath
    protocols: [
      'https'
    ]
    serviceUrl: backendUrl
    isCurrent: true
  }
}

// MCP endpoint operation - POST /
resource mcpOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'mcp-endpoint'
  properties: {
    displayName: 'MCP Endpoint'
    description: 'MCP streamable HTTP endpoint. Accepts JSON-RPC 2.0 requests, returns JSON or SSE (text/event-stream) responses.'
    method: 'POST'
    urlTemplate: '/'
    request: {
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'MCP response (JSON-RPC 2.0 or SSE stream)'
        representations: [
          {
            contentType: 'application/json'
          }
          {
            contentType: 'text/event-stream'
          }
        ]
      }
      {
        statusCode: 401
        description: 'Unauthorized - missing or invalid JWT token'
      }
    ]
  }
}

// API-level policy for JWT validation
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: mcpApi
  name: 'policy'
  properties: {
    value: loadTextContent('./policies/jwt-validation.xml')
    format: 'xml'
  }
}

// Operation-level policy for MCP passthrough with SSE support
resource mcpOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: mcpOperation
  name: 'policy'
  properties: {
    value: loadTextContent('./policies/mcp-passthrough.xml')
    format: 'xml'
  }
}
