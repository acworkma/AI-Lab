// Shared Services VNet Module
// Creates VNet for shared core services (DNS resolver, future jump boxes, etc.)
// Connected to vWAN hub for spoke and P2S client routing

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
