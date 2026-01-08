// Storage RBAC Assignment Module
// Assigns Key Vault role to managed identity for CMK access
// Called from storage.bicep as cross-resource-group deployment

targetScope = 'resourceGroup'

@description('Name of the Key Vault to assign role on')
param keyVaultName string

@description('Principal ID of the managed identity')
param principalId string

@description('Role definition ID to assign')
param roleDefinitionId string

// Reference existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Create RBAC assignment with deterministic GUID
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, principalId, roleDefinitionId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Role assignment resource ID')
output roleAssignmentId string = roleAssignment.id
