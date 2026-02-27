targetScope = 'resourceGroup'

@description('Foundry account name')
param aiAccountName string

@description('AI Search name')
param aiSearchName string

@description('Storage account name')
param storageName string

@description('Cosmos DB account name')
param cosmosDbName string

@description('Core resource group with shared VNet and DNS zones')
param coreResourceGroupName string

@description('Shared VNet name')
param vnetName string

@description('Private endpoint subnet name')
param peSubnetName string

param tags object = {}

resource aiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: aiAccountName
}

resource aiSearch 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: aiSearchName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosDbName
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(coreResourceGroupName)
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: peSubnetName
}

resource zoneAiServices 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.services.ai.azure.com'
  scope: resourceGroup(coreResourceGroupName)
}
resource zoneOpenAi 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.openai.azure.com'
  scope: resourceGroup(coreResourceGroupName)
}
resource zoneCognitiveServices 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.cognitiveservices.azure.com'
  scope: resourceGroup(coreResourceGroupName)
}
resource zoneSearch 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.search.windows.net'
  scope: resourceGroup(coreResourceGroupName)
}
resource zoneBlob 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  scope: resourceGroup(coreResourceGroupName)
}
resource zoneCosmos 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.documents.azure.com'
  scope: resourceGroup(coreResourceGroupName)
}

resource aiAccountPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${aiAccountName}-private-endpoint'
  location: resourceGroup().location
  tags: tags
  properties: {
    subnet: {
      id: peSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${aiAccountName}-private-link-service-connection'
        properties: {
          privateLinkServiceId: aiAccount.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

resource aiSearchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${aiSearchName}-private-endpoint'
  location: resourceGroup().location
  tags: tags
  properties: {
    subnet: {
      id: peSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${aiSearchName}-private-link-service-connection'
        properties: {
          privateLinkServiceId: aiSearch.id
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
  }
}

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${storageName}-private-endpoint'
  location: resourceGroup().location
  tags: tags
  properties: {
    subnet: {
      id: peSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${storageName}-private-link-service-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource cosmosPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${cosmosDbName}-private-endpoint'
  location: resourceGroup().location
  tags: tags
  properties: {
    subnet: {
      id: peSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${cosmosDbName}-private-link-service-connection'
        properties: {
          privateLinkServiceId: cosmosDbAccount.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

resource aiAccountDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: aiAccountPrivateEndpoint
  name: '${aiAccountName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'aiservices-config'
        properties: {
          privateDnsZoneId: zoneAiServices.id
        }
      }
      {
        name: 'openai-config'
        properties: {
          privateDnsZoneId: zoneOpenAi.id
        }
      }
      {
        name: 'cognitive-config'
        properties: {
          privateDnsZoneId: zoneCognitiveServices.id
        }
      }
    ]
  }
}

resource aiSearchDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: aiSearchPrivateEndpoint
  name: '${aiSearchName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'search-config'
        properties: {
          privateDnsZoneId: zoneSearch.id
        }
      }
    ]
  }
}

resource storageDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: storagePrivateEndpoint
  name: '${storageName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob-config'
        properties: {
          privateDnsZoneId: zoneBlob.id
        }
      }
    ]
  }
}

resource cosmosDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: cosmosPrivateEndpoint
  name: '${cosmosDbName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cosmos-config'
        properties: {
          privateDnsZoneId: zoneCosmos.id
        }
      }
    ]
  }
}

output aiAccountPrivateEndpointId string = aiAccountPrivateEndpoint.id
output aiSearchPrivateEndpointId string = aiSearchPrivateEndpoint.id
output storagePrivateEndpointId string = storagePrivateEndpoint.id
output cosmosPrivateEndpointId string = cosmosPrivateEndpoint.id
