targetScope = 'resourceGroup'

param cosmosDbName string
param projectPrincipalId string

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: cosmosDbName
}

resource cosmosDbOperatorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '230815da-be43-4aae-9cb4-875f7bd000aa'
  scope: resourceGroup()
}

resource cosmosDbOperatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cosmosDbAccount
  name: guid(projectPrincipalId, cosmosDbOperatorRole.id, cosmosDbAccount.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: cosmosDbOperatorRole.id
    principalType: 'ServicePrincipal'
  }
}
