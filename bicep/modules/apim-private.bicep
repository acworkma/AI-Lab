// Azure API Management Standard v2 Module — Private Variant
// Creates an APIM Standard v2 instance with VNet integration and inbound private endpoint
// Purpose: Fully private API gateway — no public network exposure
//
// Key differences from apim.bicep:
// - Adds inbound private endpoint for gateway access
// - Disables public network access
// - Requires privatelink.azure-api.net DNS zone for PE resolution

targetScope = 'resourceGroup'

// ============================================================================
// REQUIRED PARAMETERS
// ============================================================================

@description('Name of the API Management instance (must be globally unique)')
@minLength(1)
@maxLength(50)
param apimName string

@description('Azure region for deployment')
param location string

@description('Email address of the API publisher (required)')
param publisherEmail string

@description('Resource ID of the subnet for private endpoint')
param privateEndpointSubnetId string

@description('Resource ID of the privatelink.azure-api.net DNS zone')
param privateDnsZoneId string

// ============================================================================
// OPTIONAL PARAMETERS
// ============================================================================

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

@description('Enable VNet integration (outbound to backends)')
param enableVnetIntegration bool = false

@description('Resource ID of the subnet for VNet integration (outbound)')
param vnetIntegrationSubnetId string = ''

@description('Tags to apply to resources')
param tags object = {}

// ============================================================================
// VARIABLES
// ============================================================================

var privateEndpointName = '${apimName}-pe'
var privateLinkServiceConnectionName = '${apimName}-plsc'

// ============================================================================
// API MANAGEMENT INSTANCE
// ============================================================================

// Standard v2 with system-assigned managed identity
// Public network access disabled — all inbound via private endpoint
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
    // VNet integration (outbound only — for reaching private backends)
    virtualNetworkType: enableVnetIntegration ? 'External' : 'None'
    virtualNetworkConfiguration: enableVnetIntegration ? {
      subnetResourceId: vnetIntegrationSubnetId
    } : null
    // Disable public network access — all inbound via private endpoint
    publicNetworkAccess: 'Disabled'
    developerPortalStatus: 'Enabled'
    legacyPortalStatus: 'Disabled'
    apiVersionConstraint: {
      minApiVersion: '2021-08-01'
    }
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'False'
    }
    certificates: []
  }
}

// ============================================================================
// PRIVATE ENDPOINT
// ============================================================================

// Inbound private endpoint for APIM gateway
// Only the Gateway sub-resource is supported for private endpoint
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: privateLinkServiceConnectionName
        properties: {
          privateLinkServiceId: apim.id
          groupIds: [
            'Gateway' // Only supported sub-resource for APIM
          ]
        }
      }
    ]
  }
}

// ============================================================================
// PRIVATE DNS ZONE GROUP
// ============================================================================

// Auto-registers A record: <apim-name>.privatelink.azure-api.net -> private IP
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'apim-dns-config'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Name of the deployed APIM instance')
output apimName string = apim.name

@description('Full resource ID of APIM')
output apimResourceId string = apim.id

@description('Gateway URL (resolves to private IP via private DNS)')
output gatewayUrl string = apim.properties.gatewayUrl

@description('Developer portal URL')
output developerPortalUrl string = apim.properties.developerPortalUrl

@description('Management API URL')
output managementUrl string = apim.properties.managementApiUrl

@description('System-assigned managed identity principal ID')
output principalId string = apim.identity.principalId

@description('Private endpoint resource ID')
output privateEndpointId string = privateEndpoint.id

@description('Private endpoint private IP address')
output privateEndpointIp string = privateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
