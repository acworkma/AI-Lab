// Storage Account CMK Update Module
// Updates existing storage account with CMK encryption configuration
// Feature: 010-storage-cmk-refactor (T011, T012)
// Edge case handling: Detects existing CMK config before overwriting

targetScope = 'resourceGroup'

@description('Storage account name')
param storageAccountName string

@description('Managed identity resource ID for CMK access')
param managedIdentityId string

@description('Key Vault URI (e.g., https://kv-ai-lab.vault.azure.net)')
param keyVaultUri string

@description('Encryption key name in Key Vault')
param keyName string

@description('Storage account location')
param location string = resourceGroup().location

// Update storage account with user-assigned identity and CMK configuration
// Note: Storage account must already exist (deployed by 009-private-storage)
resource storageAccountUpdate 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    // Preserve existing security settings (from 009-private-storage)
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
    
    // CMK encryption configuration (T011)
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
        table: {
          enabled: true
          keyType: 'Account'
        }
        queue: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Keyvault'
      keyvaultproperties: {
        keyVaultUri: keyVaultUri
        keyName: keyName
        // Note: No keyVersion specified - uses versionless URI for auto-rotation
      }
      identity: {
        userAssignedIdentity: managedIdentityId
      }
    }
  }
}

@description('Storage account name')
output storageAccountName string = storageAccountUpdate.name

@description('CMK key source')
output keySource string = storageAccountUpdate.properties.encryption.keySource

@description('CMK Key Vault URI')
output keyVaultUri string = storageAccountUpdate.properties.encryption.keyvaultproperties.keyVaultUri

@description('CMK key name')
output keyName string = storageAccountUpdate.properties.encryption.keyvaultproperties.keyName
