// GitHub Copilot BYOK — APIM API & Backend
//
// Adds to the EXISTING APIM instance:
// - Named backend pointing to Foundry endpoint
// - Copilot BYOK API with OpenAI-compatible URL pattern
// - Named value (secret) for API key validation in policy
//
// Auth is handled in policy (not APIM subscription) to support both:
//   - api-key header (Azure/Foundry style)
//   - Authorization: Bearer (OpenAI-compatible style)
//
// Deploy to: rg-ai-apim

targetScope = 'resourceGroup'

@description('Name of the existing API Management instance')
param apimName string

@description('Foundry account endpoint URL (e.g., https://fdryailab123456.cognitiveservices.azure.com)')
param foundryEndpointUrl string

@description('Display name for the API')
param apiDisplayName string = 'Copilot BYOK API'

@description('Path prefix for the API')
param apiPath string = 'openai'

@secure()
@description('API key for GitHub Copilot BYOK authentication (validated in policy)')
param apiKey string

// Reference existing APIM instance — do NOT create or modify
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimName
}

// Named backend pointing to Foundry endpoint
resource foundryBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'foundry-codex'
  properties: {
    title: 'Azure AI Foundry - Codex'
    description: 'Azure AI Foundry endpoint for GitHub Copilot BYOK (gpt-5.2)'
    url: foundryEndpointUrl
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
    circuitBreaker: {
      rules: [
        {
          name: 'foundry-breaker'
          failureCondition: {
            count: 5
            interval: 'PT60S'
            statusCodeRanges: [
              {
                min: 500
                max: 599
              }
            ]
          }
          tripDuration: 'PT30S'
        }
      ]
    }
  }
}

// Named value (secret) — stores the API key for policy-level validation
resource apiKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'copilot-byok-api-key'
  properties: {
    displayName: 'copilot-byok-api-key'
    value: apiKey
    secret: true
    tags: [
      'copilot-byok'
    ]
  }
}

// Copilot BYOK API definition — no subscription required, auth handled in policy
resource copilotByokApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'copilot-byok-api'
  properties: {
    displayName: apiDisplayName
    description: 'GitHub Copilot BYOK API — proxies OpenAI-compatible requests to Azure AI Foundry. Auth validated in policy to support both api-key and Bearer token.'
    subscriptionRequired: false
    path: apiPath
    protocols: [
      'https'
    ]
    serviceUrl: '${foundryEndpointUrl}/openai'
    isCurrent: true
  }
  dependsOn: [
    apiKeyNamedValue
  ]
}

// List models operation — GitHub calls this to validate the connection and discover models
resource listModelsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: copilotByokApi
  name: 'list-models'
  properties: {
    displayName: 'List Models'
    description: 'Lists available models. Used by GitHub to validate connectivity and discover models.'
    method: 'GET'
    urlTemplate: '/models'
    request: {
      queryParameters: [
        {
          name: 'api-version'
          description: 'API version'
          type: 'string'
          required: false
        }
      ]
    }
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

// List deployments operation — GitHub may call this to enumerate deployments
resource listDeploymentsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: copilotByokApi
  name: 'list-deployments'
  properties: {
    displayName: 'List Deployments'
    description: 'Lists model deployments. Used by GitHub to discover available deployment IDs.'
    method: 'GET'
    urlTemplate: '/deployments'
    request: {
      queryParameters: [
        {
          name: 'api-version'
          description: 'API version'
          type: 'string'
          required: false
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'List of deployments'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

// Chat completions operation
resource chatCompletionsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: copilotByokApi
  name: 'chat-completions'
  properties: {
    displayName: 'Chat Completions'
    description: 'Creates a chat completion for the specified model deployment. Compatible with OpenAI chat/completions API format.'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        description: 'The model deployment name (e.g., gpt-5.2)'
        type: 'string'
        required: true
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          description: 'API version (e.g., 2024-10-21)'
          type: 'string'
          required: false
        }
      ]
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'Chat completion response'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
      {
        statusCode: 401
        description: 'Unauthorized — missing or invalid subscription key'
      }
      {
        statusCode: 429
        description: 'Rate limit exceeded'
      }
    ]
  }
}

// Completions operation (for code-generation models like codex)
resource completionsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: copilotByokApi
  name: 'completions'
  properties: {
    displayName: 'Completions'
    description: 'Creates a text completion for the specified model deployment. Used by code-generation models.'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        description: 'The model deployment name (e.g., gpt-5.2)'
        type: 'string'
        required: true
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          description: 'API version'
          type: 'string'
          required: false
        }
      ]
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'Completion response'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

// Responses operation (model specified in request body, not URL path)
resource responsesOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: copilotByokApi
  name: 'responses'
  properties: {
    displayName: 'Responses'
    description: 'Creates a response using the Responses API. Model is specified in the request body (e.g., gpt-5.2).'
    method: 'POST'
    urlTemplate: '/responses'
    request: {
      queryParameters: [
        {
          name: 'api-version'
          description: 'API version'
          type: 'string'
          required: false
        }
      ]
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'Response object'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

// API-level policy — managed identity auth + rate limiting
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: copilotByokApi
  name: 'policy'
  properties: {
    value: loadTextContent('./policies/managed-identity-auth.xml')
    format: 'xml'
  }
}

output apiName string = copilotByokApi.name
output apiPath string = copilotByokApi.properties.path
output gatewayUrl string = apim.properties.gatewayUrl
output baseApiUrl string = '${apim.properties.gatewayUrl}/${apiPath}'
