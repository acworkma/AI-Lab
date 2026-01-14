// Sample Backend Configuration for API Management
// Purpose: Template for defining reusable backend entities in APIM
// Usage: Deploy this module after APIM is provisioned to create named backends

targetScope = 'resourceGroup'

// Parameters
@description('Name of the API Management instance')
param apimName string

@description('Unique name for the backend entity')
param backendName string

@description('Display name for the backend')
param backendTitle string = backendName

@description('Description of the backend')
param backendDescription string = 'Backend service for API'

@description('Backend service URL')
param backendUrl string

@description('Protocol (http or https)')
@allowed([
  'http'
  'https'
])
param protocol string = 'https'

@description('Validate SSL certificate chain')
param validateCertificateChain bool = true

@description('Validate SSL certificate name')
param validateCertificateName bool = true

@description('Enable circuit breaker')
param enableCircuitBreaker bool = false

@description('Circuit breaker failure threshold')
param circuitBreakerThreshold int = 3

@description('Circuit breaker reset interval in seconds')
param circuitBreakerResetInterval int = 30

// Reference existing APIM
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimName
}

// Backend Entity
// Creates a named backend that can be referenced in policies
resource backend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: backendName
  properties: {
    title: backendTitle
    description: backendDescription
    url: backendUrl
    protocol: protocol
    // TLS configuration
    tls: {
      validateCertificateChain: validateCertificateChain
      validateCertificateName: validateCertificateName
    }
    // Circuit breaker (optional)
    circuitBreaker: enableCircuitBreaker ? {
      rules: [
        {
          name: 'default-breaker'
          failureCondition: {
            count: circuitBreakerThreshold
            interval: 'PT${circuitBreakerResetInterval}S'
            statusCodeRanges: [
              {
                min: 500
                max: 599
              }
            ]
          }
          tripDuration: 'PT${circuitBreakerResetInterval}S'
        }
      ]
    } : null
    // Credentials (optional - uncomment if needed)
    // credentials: {
    //   header: {
    //     'X-Api-Key': ['{{backend-api-key}}']  // Reference named value
    //   }
    // }
  }
}

// Outputs
@description('Backend resource ID')
output backendId string = backend.id

@description('Backend name')
output backendName string = backend.name

// ============================================================================
// Usage Examples
// ============================================================================
/*

Example 1: Private endpoint backend
----------------------------------
module internalBackend 'backends/sample-backend.bicep' = {
  name: 'deploy-internal-backend'
  params: {
    apimName: 'apim-ai-lab'
    backendName: 'internal-orders-api'
    backendTitle: 'Internal Orders Service'
    backendUrl: 'https://orders.privatelink.azurewebsites.net'
    validateCertificateChain: true
  }
}

Example 2: Development backend (relaxed SSL)
-------------------------------------------
module devBackend 'backends/sample-backend.bicep' = {
  name: 'deploy-dev-backend'
  params: {
    apimName: 'apim-ai-lab'
    backendName: 'dev-service'
    backendUrl: 'https://dev-api.internal.local'
    validateCertificateChain: false
    validateCertificateName: false
  }
}

Example 3: Backend with circuit breaker
--------------------------------------
module resilientBackend 'backends/sample-backend.bicep' = {
  name: 'deploy-resilient-backend'
  params: {
    apimName: 'apim-ai-lab'
    backendName: 'critical-service'
    backendUrl: 'https://critical.api.company.com'
    enableCircuitBreaker: true
    circuitBreakerThreshold: 5
    circuitBreakerResetInterval: 60
  }
}

Using the backend in policy
---------------------------
<inbound>
    <base />
    <set-backend-service backend-id="internal-orders-api" />
</inbound>

*/
