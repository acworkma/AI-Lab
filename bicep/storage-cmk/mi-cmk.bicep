// User-Assigned Managed Identity Module for CMK
// Creates managed identity used for Key Vault access
// Feature: 010-storage-cmk-refactor (T008)

targetScope = 'resourceGroup'

@description('Managed identity name')
param name string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

// Create user-assigned managed identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

@description('Managed identity resource ID')
output id string = managedIdentity.id

@description('Managed identity principal ID (object ID)')
output principalId string = managedIdentity.properties.principalId

@description('Managed identity client ID')
output clientId string = managedIdentity.properties.clientId

@description('Managed identity name')
output name string = managedIdentity.name
