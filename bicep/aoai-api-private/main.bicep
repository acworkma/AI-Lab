// Legacy Azure OpenAI API for Private APIM
//
// Exposes the legacy Azure OpenAI service endpoints through private APIM.
// APIM authenticates to Azure OpenAI using its system-assigned managed identity.
// Consumers authenticate via Entra ID JWT.
//
// Operations:
// - POST /deployments/{deployment-id}/chat/completions - Chat completions (streaming supported)
// - GET  /models - List available model deployments

@description('Name of the private API Management instance')
param apimName string = 'apim-ai-lab-private'

@description('Display name for the Azure OpenAI API')
param apiDisplayName string = 'Azure OpenAI API (Legacy/Private)'

@description('Path prefix for the API')
param apiPath string = 'aoai'

@description('Backend URL for the Azure OpenAI account')
param backendUrl string = 'https://oai-ailab-private.openai.azure.com/openai'

@description('Default API version for OpenAI endpoints')
param defaultApiVersion string = '2024-10-21'

// Reference existing private APIM instance
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimName
}

// Named value for default API version
resource apiVersionNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-api-version'
  properties: {
    displayName: 'aoai-api-version'
    value: defaultApiVersion
    secret: false
  }
}

// Backend definition with managed identity auth
resource aoaiBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-legacy-backend'
  properties: {
    title: 'Azure OpenAI Legacy Backend'
    description: 'Private Azure OpenAI account (oai-ailab-private) accessed via managed identity'
    url: backendUrl
    protocol: 'http'
  }
}

// API definition
resource aoaiApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-legacy-api'
  properties: {
    displayName: apiDisplayName
    description: 'Legacy Azure OpenAI Service API exposed through private APIM with Entra ID auth'
    path: apiPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    serviceUrl: backendUrl
    apiType: 'http'
  }
}

// API-level policy (JWT validation)
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: aoaiApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('policies/jwt-validation.xml')
  }
}

// Operation: Chat Completions
resource chatCompletionsOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: aoaiApi
  name: 'chat-completions'
  properties: {
    displayName: 'Chat Completions'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
        description: 'Model deployment name (e.g., gpt-4.1)'
      }
    ]
    description: 'Creates a chat completion for the given messages. Supports streaming via SSE.'
  }
}

// Chat completions operation policy (managed identity + streaming)
resource chatCompletionsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: chatCompletionsOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('policies/openai-passthrough.xml')
  }
}

// Operation: List Models
resource listModelsOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: aoaiApi
  name: 'list-models'
  properties: {
    displayName: 'List Models'
    method: 'GET'
    urlTemplate: '/models'
    description: 'Lists available model deployments on the Azure OpenAI account.'
  }
}

// List models operation policy
resource listModelsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: listModelsOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('policies/openai-passthrough.xml')
  }
}
