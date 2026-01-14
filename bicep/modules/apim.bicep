// Azure API Management Standard v2 Module
// Creates an APIM Standard v2 instance with optional VNet integration
// Purpose: Centralized API gateway with public frontend and private backend connectivity

targetScope = 'resourceGroup'

// Parameters
@description('Name of the API Management instance (must be globally unique)')
@minLength(1)
@maxLength(50)
param apimName string

@description('Azure region for deployment')
param location string

@description('Email address of the API publisher (required)')
param publisherEmail string

@description('Name of the API publisher organization')
param publisherName string = 'AI-Lab'

@description('APIM pricing tier')
@allowed([
  'Standardv2'
])
param sku string = 'Standardv2'

@description('Number of scale units')
@minValue(1)
@maxValue(10)
param skuCapacity int = 1

@description('Enable VNet integration')
param enableVnetIntegration bool = false

@description('Resource ID of the subnet for VNet integration')
param subnetId string = ''

@description('Tags to apply to resources')
param tags object = {}

// API Management Instance
// Standard v2 tier with system-assigned managed identity
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    // VNet integration configuration (Standard v2 uses different approach than Premium)
    virtualNetworkType: enableVnetIntegration ? 'External' : 'None'
    virtualNetworkConfiguration: enableVnetIntegration ? {
      subnetResourceId: subnetId
    } : null
    // Enable developer portal
    developerPortalStatus: 'Enabled'
    // Disable legacy portal
    legacyPortalStatus: 'Disabled'
    // API version constraint
    apiVersionConstraint: {
      minApiVersion: '2021-08-01'
    }
    // Custom properties
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'False'
    }
    // Certificates (empty for now, can be extended)
    certificates: []
  }
}

// Outputs
@description('Name of the deployed APIM instance')
output apimName string = apim.name

@description('Full resource ID of APIM')
output apimResourceId string = apim.id

@description('Public gateway URL')
output gatewayUrl string = apim.properties.gatewayUrl

@description('Developer portal URL')
output developerPortalUrl string = apim.properties.developerPortalUrl

@description('Management API URL')
output managementUrl string = apim.properties.managementApiUrl

@description('System-assigned managed identity principal ID')
output principalId string = apim.identity.principalId

@description('APIM provisioning state')
output provisioningState string = apim.properties.provisioningState
