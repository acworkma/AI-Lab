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
    subnets: [
      {
        name: 'PrivateEndpointSubnet'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: {
            id: privateEndpointNsg.id
          }
          // Disable network policies for private endpoints
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
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
