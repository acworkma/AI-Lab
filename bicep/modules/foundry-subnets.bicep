// Foundry subnet module
// Creates Foundry delegated agent subnet and private endpoint subnet in existing shared VNet

targetScope = 'resourceGroup'

@description('Shared VNet name')
param sharedVnetName string

@description('Delegated Agent subnet name')
param agentSubnetName string

@description('Delegated Agent subnet address prefix')
param agentSubnetPrefix string

@description('Private Endpoint subnet name')
param privateEndpointSubnetName string

@description('Private Endpoint subnet address prefix')
param privateEndpointSubnetPrefix string

resource sharedVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: sharedVnetName
}

resource foundryAgentSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: sharedVnet
  name: agentSubnetName
  properties: {
    addressPrefix: agentSubnetPrefix
    delegations: [
      {
        name: 'delegate-app-environments'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

resource foundryPrivateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: sharedVnet
  name: privateEndpointSubnetName
  properties: {
    addressPrefix: privateEndpointSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

@description('Delegated Agent subnet resource ID')
output agentSubnetId string = foundryAgentSubnet.id

@description('Private Endpoint subnet resource ID')
output privateEndpointSubnetId string = foundryPrivateEndpointSubnet.id
