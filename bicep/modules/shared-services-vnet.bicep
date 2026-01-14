// Shared Services VNet Module
// Creates spoke VNet for shared infrastructure services with private endpoints
// Purpose: Host private endpoints for ACR, Key Vault, Storage, and other shared PaaS services

targetScope = 'resourceGroup'

// Parameters
@description('Name of the shared services VNet')
param vnetName string

@description('Azure region for deployment')
param location string

@description('VNet address space (CIDR notation)')
param vnetAddressPrefix string = '10.1.0.0/24'

@description('Private endpoint subnet address prefix')
param privateEndpointSubnetPrefix string = '10.1.0.0/26'

@description('Virtual Hub resource ID to connect this spoke VNet')
param virtualHubId string

@description('VPN client address pool for NSG rules')
param vpnClientAddressPool string = '172.16.0.0/24'

@description('Enable APIM integration subnet')
param enableApimSubnet bool = false

@description('APIM integration subnet address prefix (minimum /27, recommended /26)')
param apimSubnetPrefix string = '10.1.0.64/26'

@description('Tags to apply to resources')
param tags object = {}

// Network Security Group for private endpoint subnet
// Allows inbound from VPN clients and hub, denies internet
resource privateEndpointNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${vnetName}-pe-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowVpnClientInbound'
        properties: {
          description: 'Allow inbound traffic from VPN clients'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: vpnClientAddressPool
          destinationAddressPrefix: '10.1.0.0/26'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowVnetInbound'
        properties: {
          description: 'Allow inbound traffic from VNet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

// APIM Integration Subnet NSG (conditionally created)
// Controls traffic for APIM VNet integration
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = if (enableApimSubnet) {
  name: '${vnetName}-apim-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      // Inbound Rules
      {
        name: 'AllowVpnClientInbound'
        properties: {
          description: 'Allow inbound from VPN clients to developer portal/management'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [ '443', '3443' ]
          sourceAddressPrefix: vpnClientAddressPool
          destinationAddressPrefix: apimSubnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowVnetInbound'
        properties: {
          description: 'Allow inbound from VNet (hub-spoke communication)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          description: 'Allow Azure Load Balancer health probes'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
      // Outbound Rules
      {
        name: 'AllowStorageOutbound'
        properties: {
          description: 'Allow outbound to Azure Storage for APIM dependencies'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowKeyVaultOutbound'
        properties: {
          description: 'Allow outbound to Azure Key Vault for secrets/certificates'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureKeyVault'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowSqlOutbound'
        properties: {
          description: 'Allow outbound to Azure SQL for APIM configuration store'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowVnetOutbound'
        properties: {
          description: 'Allow outbound to VNet for backend connectivity'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowAzureMonitorOutbound'
        properties: {
          description: 'Allow outbound to Azure Monitor for diagnostics'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 140
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowAzureActiveDirectoryOutbound'
        properties: {
          description: 'Allow outbound to Azure AD for authentication'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureActiveDirectory'
          access: 'Allow'
          priority: 150
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyInternetOutbound'
        properties: {
          description: 'Deny direct internet access (use service tags for Azure services)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
          access: 'Deny'
          priority: 4096
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Base subnets - always include PrivateEndpointSubnet
var baseSubnets = [
  {
    name: 'PrivateEndpointSubnet'
    properties: {
      addressPrefix: privateEndpointSubnetPrefix
      networkSecurityGroup: {
        id: privateEndpointNsg.id
      }
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
    }
  }
]

// APIM subnet configuration (conditionally added)
var apimSubnet = enableApimSubnet ? [
  {
    name: 'ApimIntegrationSubnet'
    properties: {
      addressPrefix: apimSubnetPrefix
      networkSecurityGroup: {
        id: apimNsg.id
      }
      delegations: [
        {
          name: 'delegation-web-serverfarms'
          properties: {
            serviceName: 'Microsoft.Web/serverFarms'
          }
        }
      ]
      serviceEndpoints: [
        { service: 'Microsoft.Storage' }
        { service: 'Microsoft.KeyVault' }
        { service: 'Microsoft.Sql' }
        { service: 'Microsoft.EventHub' }
      ]
      privateEndpointNetworkPolicies: 'Enabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
    }
  }
] : []

// Combined subnets
var allSubnets = concat(baseSubnets, apimSubnet)

// Shared Services VNet - First spoke for shared infrastructure
// Address space: 10.1.0.0/24 provides 256 addresses
resource sharedServicesVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: allSubnets
  }
}

// Hub Connection - Connect shared services VNet to Virtual Hub
// Enables routing between VPN clients and private endpoints
resource hubConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2023-11-01' = {
  name: '${last(split(virtualHubId, '/'))}/connection-to-shared-services'
  properties: {
    remoteVirtualNetwork: {
      id: sharedServicesVnet.id
    }
    // Disable internet security - no forced tunneling through hub
    enableInternetSecurity: false
    // Use default routing configuration
    routingConfiguration: {
      associatedRouteTable: {
        id: '${virtualHubId}/hubRouteTables/defaultRouteTable'
      }
      propagatedRouteTables: {
        labels: [
          'default'
        ]
        ids: [
          {
            id: '${virtualHubId}/hubRouteTables/defaultRouteTable'
          }
        ]
      }
    }
  }
}

// Outputs for use by main template and downstream deployments
@description('Resource ID of the shared services VNet')
output vnetId string = sharedServicesVnet.id

@description('Name of the shared services VNet')
output vnetName string = sharedServicesVnet.name

@description('VNet address prefix')
output vnetAddressPrefix string = vnetAddressPrefix

@description('Resource ID of the private endpoint subnet')
output privateEndpointSubnetId string = sharedServicesVnet.properties.subnets[0].id

@description('Name of the private endpoint subnet')
output privateEndpointSubnetName string = sharedServicesVnet.properties.subnets[0].name

@description('Private endpoint subnet address prefix')
output privateEndpointSubnetPrefix string = privateEndpointSubnetPrefix

@description('Hub connection provisioning state')
output hubConnectionState string = hubConnection.properties.provisioningState

@description('Resource ID of the APIM integration subnet (empty if not enabled)')
output apimSubnetId string = enableApimSubnet ? sharedServicesVnet.properties.subnets[1].id : ''

@description('Name of the APIM integration subnet (empty if not enabled)')
output apimSubnetName string = enableApimSubnet ? 'ApimIntegrationSubnet' : ''

@description('APIM subnet address prefix (empty if not enabled)')
output apimSubnetPrefix string = enableApimSubnet ? apimSubnetPrefix : ''
