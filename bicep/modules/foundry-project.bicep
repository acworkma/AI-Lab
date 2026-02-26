targetScope = 'resourceGroup'

param accountName string
param location string
param projectName string
param projectDescription string
param displayName string

param aiSearchName string
param cosmosDbName string
param storageName string

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: aiSearchName
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: cosmosDbName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: account
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: projectDescription
    displayName: displayName
  }

  resource projectConnectionCosmosDb 'connections@2025-04-01-preview' = {
    name: cosmosDbName
    properties: {
      category: 'CosmosDB'
      target: cosmosDbAccount.properties.documentEndpoint
      authType: 'AAD'
      metadata: {
        ApiType: 'Azure'
        ResourceId: cosmosDbAccount.id
        location: cosmosDbAccount.location
      }
    }
  }

  resource projectConnectionStorage 'connections@2025-04-01-preview' = {
    name: storageName
    properties: {
      category: 'AzureStorageAccount'
      target: storageAccount.properties.primaryEndpoints.blob
      authType: 'AAD'
      metadata: {
        ApiType: 'Azure'
        ResourceId: storageAccount.id
        location: storageAccount.location
      }
    }
  }

  resource projectConnectionSearch 'connections@2025-04-01-preview' = {
    name: aiSearchName
    properties: {
      category: 'CognitiveSearch'
      target: 'https://${aiSearchName}.search.windows.net'
      authType: 'AAD'
      metadata: {
        ApiType: 'Azure'
        ResourceId: searchService.id
        location: searchService.location
      }
    }
  }
}

output projectName string = project.name
output projectId string = project.id
output projectPrincipalId string = project.identity.principalId
#disable-next-line BCP053
output projectWorkspaceId string = project.properties.internalId
output cosmosDbConnection string = cosmosDbName
output storageConnection string = storageName
output aiSearchConnection string = aiSearchName
