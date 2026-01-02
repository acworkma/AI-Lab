// Azure Container Registry Module
// Creates private ACR with RBAC authorization and private endpoint connectivity
// Purpose: Private container image registry for lab environments

targetScope = 'resourceGroup'

// Parameters
@description('Azure Container Registry name (globally unique, 5-50 alphanumeric characters)')
@minLength(5)
@maxLength(50)
param acrName string

@description('Azure region for deployment')
param location string

@description('ACR SKU (Standard or Premium required for private endpoints and import)')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Standard'

@description('Enable admin user (not recommended, use RBAC instead)')
param adminUserEnabled bool = false

@description('Public network access (Disabled for private-only access)')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@description('Resource ID of the subnet for private endpoint')
param privateEndpointSubnetId string

@description('Resource ID of the ACR private DNS zone')
param acrDnsZoneId string

@description('Tags to apply to resources')
param tags object = {}

// Azure Container Registry - Private container image registry
// Standard SKU supports import from public registries and private endpoints
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: acrSku
  }
  properties: {
    // Disable admin user - use RBAC for authentication
    adminUserEnabled: adminUserEnabled
    // Disable public network access - private endpoint only
    publicNetworkAccess: publicNetworkAccess
    // Enable zone redundancy for Premium SKU (optional)
    zoneRedundancy: acrSku == 'Premium' ? 'Enabled' : 'Disabled'
    // Network rule set (deny all public access)
    networkRuleSet: {
      defaultAction: 'Deny'
    }
    // Policies
    policies: {
      // Quarantine policy - scan images before use (Premium only)
      quarantinePolicy: {
        status: 'disabled'
      }
      // Trust policy - content trust for image signing (Premium only)
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      // Retention policy - automatically delete untagged manifests
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
      // Export policy - allow image export
      exportPolicy: {
        status: 'enabled'
      }
    }
    // Data endpoint - regional endpoints for data operations
    dataEndpointEnabled: false
    // Encryption - customer-managed keys (Premium only)
    encryption: {
      status: 'disabled'
    }
  }
}

// Private Endpoint - Connect ACR to private subnet
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${acrName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${acrName}-pl-connection'
        properties: {
          privateLinkServiceId: containerRegistry.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone Group - Link private endpoint to DNS zone
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: acrDnsZoneId
        }
      }
    ]
  }
}

// Outputs for use by deployment scripts and validation
@description('Resource ID of the Azure Container Registry')
output acrId string = containerRegistry.id

@description('Name of the Azure Container Registry')
output acrName string = containerRegistry.name

@description('Login server URL for the ACR')
output acrLoginServer string = containerRegistry.properties.loginServer

@description('ACR SKU')
output acrSku string = containerRegistry.sku.name

@description('Public network access status')
output publicNetworkAccess string = containerRegistry.properties.publicNetworkAccess

@description('Resource ID of the private endpoint')
output privateEndpointId string = privateEndpoint.id

@description('Private endpoint name')
output privateEndpointName string = privateEndpoint.name

@description('ACR provisioning state')
output provisioningState string = containerRegistry.properties.provisioningState
