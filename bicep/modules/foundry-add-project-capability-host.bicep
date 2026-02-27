targetScope = 'resourceGroup'

@description('Cosmos DB connection name in Foundry project')
param cosmosDbConnection string

@description('Storage connection name in Foundry project')
param storageConnection string

@description('AI Search connection name in Foundry project')
param aiSearchConnection string

@description('Foundry project name')
param projectName string

@description('Foundry account name')
param accountName string

@description('Project capability host name')
param projectCapHost string = 'caphostproj'

var threadConnections = [
  cosmosDbConnection
]

var storageConnections = [
  storageConnection
]

var vectorStoreConnections = [
  aiSearchConnection
]

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: account
  name: projectName
}

resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: project
  name: projectCapHost
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    vectorStoreConnections: vectorStoreConnections
    storageConnections: storageConnections
    threadStorageConnections: threadConnections
  }
}

output projectCapHostName string = projectCapabilityHost.name
