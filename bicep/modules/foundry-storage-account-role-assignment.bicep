targetScope = 'resourceGroup'

param storageAccountName string
param projectPrincipalId string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource storageBlobDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  scope: resourceGroup()
}

resource storageBlobDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(projectPrincipalId, storageBlobDataContributorRole.id, storageAccount.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: storageBlobDataContributorRole.id
    principalType: 'ServicePrincipal'
  }
}
