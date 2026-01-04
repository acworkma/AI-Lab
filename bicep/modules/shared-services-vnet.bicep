/*
  Shared Services VNet Module
  ============================
  
  Purpose:
    Creates a VNet for shared core services (DNS Private Resolver, jump boxes, monitoring, etc.)
    that need to be accessible from all spokes and P2S clients via vWAN hub routing.
  
  Dependencies:
    - Virtual WAN hub must exist (provided via virtualHubId parameter)
    - Hub must be in 'Succeeded' provisioning state before creating connection
  
  Inputs:
    - vnetName: Name of the shared services VNet (default: 'vnet-ai-shared')
    - vnetAddressPrefix: Address space for VNet (default: '10.1.0.0/24', 256 IPs)
    - virtualHubId: Resource ID of the vWAN hub to connect to
    - location: Azure region
    - tags: Resource tags
  
  Outputs:
    - vnetId: VNet resource ID (used by DNS resolver module)
    - vnetName: VNet name (used by DNS resolver for subnet naming)
    - vnetAddressPrefix: Address space (for documentation)
    - hubConnectionId: Hub connection resource ID
  
  Network Design:
    - Address Space: 10.1.0.0/24 (256 IPs total)
    - Subnets: Created by dependent modules (e.g., dns-resolver.bicep creates DnsInboundSubnet)
    - Hub Connection: Routes traffic between P2S clients (172.16.0.0/24) and this VNet
    - Routing: Associated with defaultRouteTable for automatic spoke-to-spoke routing
*/

targetScope = 'resourceGroup'

@description('Azure region for deployment')
param location string

@description('Name of the shared services VNet')
param vnetName string = 'vnet-ai-shared'

@description('Address prefix for the shared services VNet')
param vnetAddressPrefix string = '10.1.0.0/24'

@description('Resource ID of the virtual hub to connect to')
param virtualHubId string

@description('Tags to apply to resources')
param tags object = {}

// Shared Services VNet
// Note: Initial deployment has no subnets; subnets are added by dependent modules
// (e.g., dns-resolver.bicep adds DnsInboundSubnet with /27 CIDR)
resource sharedVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: []
  }
  tags: tags
}

// Hub Virtual Network Connection (connects VNet to vWAN hub)
// Routing Configuration:
//   - Associated Route Table: defaultRouteTable (receives routes from other spokes)
//   - Propagated Route Tables: defaultRouteTable (advertises VNet routes to spokes/P2S)
//   - Internet Security: Enabled (routes 0.0.0.0/0 through Azure Firewall if present in hub)
resource hubConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2023-11-01' = {
  name: '${last(split(virtualHubId, '/'))}/${vnetName}-connection'
  properties: {
    remoteVirtualNetwork: {
      id: sharedVnet.id
    }
    enableInternetSecurity: true
    routingConfiguration: {
      associatedRouteTable: {
        id: '${virtualHubId}/hubRouteTables/defaultRouteTable'
      }
      propagatedRouteTables: {
        ids: [
          {
            id: '${virtualHubId}/hubRouteTables/defaultRouteTable'
          }
        ]
        labels: [
          'default'
        ]
      }
    }
  }
}

@description('Resource ID of the shared services VNet')
output vnetId string = sharedVnet.id

@description('Name of the shared services VNet')
output vnetName string = sharedVnet.name

@description('Address prefix of the shared services VNet')
output vnetAddressPrefix string = vnetAddressPrefix

@description('Resource ID of the hub connection')
output hubConnectionId string = hubConnection.id
