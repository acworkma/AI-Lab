// GitHub Copilot BYOK — APIM API, Backend, Product & Subscription
//
// Adds to the EXISTING APIM instance:
// - Named backend pointing to Foundry endpoint
// - Copilot BYOK API with native Foundry URL pattern
// - "GitHub Copilot" product with subscription requirement
// - Named subscription (key = GitHub API key)
//
// Operations:
// - POST /openai/deployments/{deployment-id}/chat/completions  - Chat completions
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

@description('Display name for the APIM product')
param productDisplayName string = 'GitHub Copilot'

@description('Display name for the subscription')
param subscriptionDisplayName string = 'GitHub Copilot BYOK'

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
    description: 'Azure AI Foundry endpoint for GitHub Copilot BYOK (gpt-5.1-codex-mini)'
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

// "GitHub Copilot" product — groups the BYOK API and requires subscription
resource copilotProduct 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = {
  parent: apim
  name: 'github-copilot'
  properties: {
    displayName: productDisplayName
    description: 'GitHub Copilot BYOK — provides access to Azure AI Foundry models via APIM subscription key. Rate limited to 60 requests/minute.'
    state: 'published'
    subscriptionRequired: true
    approvalRequired: false
    subscriptionsLimit: 10
  }
}

// Copilot BYOK API definition
resource copilotByokApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'copilot-byok-api'
  properties: {
    displayName: apiDisplayName
    description: 'GitHub Copilot BYOK API — proxies OpenAI-compatible chat/completions requests to Azure AI Foundry via managed identity authentication.'
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    path: apiPath
    protocols: [
      'https'
    ]
    serviceUrl: '${foundryEndpointUrl}/openai'
    isCurrent: true
  }
}

// Associate API with the GitHub Copilot product
resource productApiLink 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: copilotProduct
  name: copilotByokApi.name
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
        description: 'The model deployment name (e.g., gpt-5.1-codex-mini)'
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

// API-level policy — managed identity auth + rate limiting
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: copilotByokApi
  name: 'policy'
  properties: {
    value: loadTextContent('./policies/managed-identity-auth.xml')
    format: 'xml'
  }
}

// Named subscription for GitHub Copilot
resource copilotSubscription 'Microsoft.ApiManagement/service/subscriptions@2023-09-01-preview' = {
  parent: apim
  name: 'github-copilot-byok'
  properties: {
    displayName: subscriptionDisplayName
    scope: copilotProduct.id
    state: 'active'
    allowTracing: false
  }
}

output apiName string = copilotByokApi.name
output apiPath string = copilotByokApi.properties.path
output productName string = copilotProduct.name
output subscriptionName string = copilotSubscription.name
output gatewayUrl string = apim.properties.gatewayUrl
output deploymentUrl string = '${apim.properties.gatewayUrl}/${apiPath}/deployments'
