// Foundry LLM API for Private Azure API Management
//
// Exposes Azure AI Foundry OpenAI-compatible endpoints through private APIM.
// APIM authenticates to Foundry using its system-assigned managed identity.
// Consumers authenticate via Entra ID JWT.
//
// Operations:
// - POST /deployments/{deployment-id}/chat/completions - Chat completions (streaming supported)
// - GET  /models - List available model deployments

@description('Name of the private API Management instance')
param apimName string = 'apim-ai-lab-private'

@description('Display name for the Foundry API')
param apiDisplayName string = 'Foundry LLM API (Private)'

@description('Path prefix for the API')
param apiPath string = 'openai'

@description('Backend URL for the Foundry account (OpenAI-compatible base)')
param backendUrl string = 'https://fdryailabbzn6hg.cognitiveservices.azure.com/openai'

@description('Default API version for OpenAI endpoints')
param defaultApiVersion string = '2024-10-21'

// Reference existing private APIM instance
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimName
}

// Named value for default API version
resource apiVersionNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'foundry-api-version'
  properties: {
    displayName: 'foundry-api-version'
    value: defaultApiVersion
    secret: false
  }
}

// Backend definition with managed identity auth
resource foundryBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'foundry-llm-backend'
  properties: {
    title: 'Foundry LLM Backend'
    description: 'Private Foundry account (fdryailabbzn6hg) accessed via managed identity'
    url: backendUrl
    protocol: 'http'
    credentials: {
      header: {}
      query: {}
    }
  }
}

// Foundry LLM API definition
resource foundryApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'foundry-llm-api'
  properties: {
    displayName: apiDisplayName
    description: 'Azure AI Foundry OpenAI-compatible API exposed via private APIM. Backend auth uses APIM managed identity — no API keys. Supports SSE streaming for chat completions.'
    subscriptionRequired: false
    path: apiPath
    protocols: [
      'https'
    ]
    serviceUrl: backendUrl
    isCurrent: true
  }
}

// Operation: Chat Completions
resource chatCompletionsOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: foundryApi
  name: 'chat-completions'
  properties: {
    displayName: 'Chat Completions'
    description: 'Creates a completion for the chat message. Supports streaming via SSE.'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        description: 'Model deployment name (e.g., gpt-4.1)'
        type: 'string'
        required: true
      }
    ]
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
        description: 'Chat completion response (JSON or SSE stream)'
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
      {
        statusCode: 429
        description: 'Rate limited'
      }
    ]
  }
}

// Operation: List Models
resource listModelsOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: foundryApi
  name: 'list-models'
  properties: {
    displayName: 'List Models'
    description: 'Lists available model deployments'
    method: 'GET'
    urlTemplate: '/models'
    responses: [
      {
        statusCode: 200
        description: 'List of available models'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

// API-level policy for JWT validation
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: foundryApi
  name: 'policy'
  properties: {
    value: loadTextContent('./policies/jwt-validation.xml')
    format: 'xml'
  }
}

// Operation-level policy for chat completions (managed identity + streaming)
resource chatCompletionsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: chatCompletionsOp
  name: 'policy'
  properties: {
    value: loadTextContent('./policies/openai-passthrough.xml')
    format: 'xml'
  }
}

// Operation-level policy for list models
resource listModelsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: listModelsOp
  name: 'policy'
  properties: {
    value: loadTextContent('./policies/openai-passthrough.xml')
    format: 'xml'
  }
}
