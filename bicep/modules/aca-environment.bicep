// Azure Container Apps Environment Module with Private Endpoint
// Creates a Consumption-only ACA environment with VNet injection, internal ingress,
// private endpoint, and Log Analytics integration
// Purpose: Private serverless container hosting with no public network exposure
//
// Security Decisions:
// - SR-001: Public network access disabled - all access via private endpoint only
// - SR-002: Internal-only ingress - environment has no public load balancer
// - SR-003: VNet injection - containers run inside dedicated subnet
// - SR-004: Managed identity for ACR pull - no credential secrets

targetScope = 'resourceGroup'

// ============================================================================
// REQUIRED PARAMETERS
// ============================================================================

@description('Name of the Container Apps Environment')
@minLength(2)
@maxLength(60)
param environmentName string

@description('Azure region for deployment')
param location string

@description('Resource ID of the subnet for ACA environment (minimum /23)')
param infrastructureSubnetId string

@description('Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string

// ============================================================================
// OPTIONAL PARAMETERS
// ============================================================================

@description('Resource ID of the private endpoint subnet')
param privateEndpointSubnetId string = ''

@description('Resource ID of the ACA private DNS zone (privatelink.azurecontainerapps.io)')
param privateDnsZoneId string = ''

@description('Enable zone redundancy for the environment')
param zoneRedundant bool = false

@description('Resource tags')
param tags object = {}

// ============================================================================
// VARIABLES
// ============================================================================

var privateEndpointName = '${environmentName}-pe'
var privateLinkServiceConnectionName = '${environmentName}-plsc'
var deployPrivateEndpoint = !empty(privateEndpointSubnetId) && !empty(privateDnsZoneId)

// ============================================================================
// CONTAINER APPS ENVIRONMENT
// ============================================================================

// Container Apps Environment - Consumption workload profile, VNet-injected, internal only
// SR-001: Public network access disabled
// SR-002: Internal-only ingress (no public load balancer)
// SR-003: VNet injection via dedicated subnet
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    // VNet configuration - inject into dedicated subnet
    vnetConfiguration: {
      infrastructureSubnetId: infrastructureSubnetId
      internal: true  // SR-002: Internal-only (no public load balancer)
    }
    // Log Analytics integration
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2023-09-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2023-09-01').primarySharedKey
      }
    }
    // Zone redundancy (disabled for lab, enable for prod)
    zoneRedundant: zoneRedundant
    // Consumption workload profile
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    // Disable public network access
    publicNetworkAccess: 'Disabled'
  }
}

// ============================================================================
// PRIVATE ENDPOINT
// ============================================================================

// Private Endpoint for ACA environment management and ingress
// Enables VPN-connected clients to reach the ACA environment
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (deployPrivateEndpoint) {
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
          privateLinkServiceId: containerAppEnvironment.id
          groupIds: [
            'managedEnvironments'
          ]
        }
      }
    ]
  }
}

// DNS Zone Group - Auto-register A record in private DNS zone
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (deployPrivateEndpoint) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecontainerapps-io'
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

@description('Container Apps Environment resource ID')
output environmentId string = containerAppEnvironment.id

@description('Container Apps Environment name')
output environmentName string = containerAppEnvironment.name

@description('Container Apps Environment default domain')
output defaultDomain string = containerAppEnvironment.properties.defaultDomain

@description('Container Apps Environment static IP')
output staticIp string = containerAppEnvironment.properties.staticIp

@description('Private endpoint IP address (for DNS verification)')
output privateEndpointIp string = deployPrivateEndpoint ? privateEndpoint.properties.customDnsConfigs[0].ipAddresses[0] : ''
