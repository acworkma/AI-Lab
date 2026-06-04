// Private Endpoint for Azure OpenAI
// Connects to existing VNet subnet and links DNS zone group

@description('Azure region')
param location string

@description('OpenAI account name')
param accountName string

@description('OpenAI account resource ID')
param accountId string

@description('Resource group containing the VNet')
param vnetResourceGroupName string

@description('VNet name')
param vnetName string

@description('Subnet name for private endpoints')
param subnetName string

@description('Resource group containing DNS zones')
param dnsZoneResourceGroupName string

@description('Tags')
param tags object

// Reference existing subnet
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetResourceGroupName)
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: vnet
  name: subnetName
}

// Reference existing DNS zone
resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.openai.azure.com'
  scope: resourceGroup(dnsZoneResourceGroupName)
}

// Private endpoint
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${accountName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${accountName}'
        properties: {
          privateLinkServiceId: accountId
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

// DNS zone group
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-openai-azure-com'
        properties: {
          privateDnsZoneId: dnsZone.id
        }
      }
    ]
  }
}

output privateEndpointId string = privateEndpoint.id
