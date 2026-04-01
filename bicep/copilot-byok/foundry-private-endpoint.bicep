// Private Endpoint for Foundry Account
//
// Creates a private endpoint in the shared services VNet PE subnet
// and registers it in the existing privatelink.cognitiveservices.azure.com DNS zone.
// This enables APIM (VNet-integrated) to reach Foundry via private network.
//
// Deploy to: rg-ai-core (where the VNet and DNS zones live)

targetScope = 'resourceGroup'

@description('Name of the Foundry Cognitive Services account')
param foundryAccountName string

@description('Resource group of the Foundry account')
param foundryResourceGroupName string = 'rg-foundry'

@description('Shared services VNet name')
param vnetName string = 'vnet-ai-shared'

@description('Private endpoint subnet name')
param subnetName string = 'PrivateEndpointSubnet'

@description('Location')
param location string = resourceGroup().location

// Reference existing VNet and subnet
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: subnetName
}

// Reference existing private DNS zone
resource cognitiveServicesDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.cognitiveservices.azure.com'
}

// Private endpoint for Foundry account
resource foundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${foundryAccountName}-pe'
  location: location
  properties: {
    subnet: {
      id: peSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${foundryAccountName}-connection'
        properties: {
          privateLinkServiceId: resourceId(foundryResourceGroupName, 'Microsoft.CognitiveServices/accounts', foundryAccountName)
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

// DNS zone group — auto-registers A record in private DNS zone
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: foundryPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cognitiveservices'
        properties: {
          privateDnsZoneId: cognitiveServicesDnsZone.id
        }
      }
    ]
  }
}

output privateEndpointName string = foundryPrivateEndpoint.name
output privateEndpointId string = foundryPrivateEndpoint.id
