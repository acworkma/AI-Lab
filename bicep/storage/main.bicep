// Main Bicep Template - Enable CMK on Existing Private Storage Account
// Feature: 010-storage-cmk-refactor
// Purpose: Enable customer-managed key encryption on pre-deployed storage account
//          using key from pre-deployed Key Vault

targetScope = 'subscription'

// ============================================================================
// PARAMETERS (per contracts/bicep-interface.md)
// ============================================================================

@description('Azure region for managed identity')
param location string = 'eastus2'

@description('Environment tag (dev, test, or prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Owner identifier for resource tagging')
@minLength(1)
@maxLength(100)
param owner string

@description('Storage account name suffix (must match existing storage account stailab<suffix>)')
param storageNameSuffix string

@description('Key Vault resource group name')
param keyVaultResourceGroupName string = 'rg-ai-keyvault'

@description('Storage resource group name')
param storageResourceGroupName string = 'rg-ai-storage'

@description('Key Vault name (auto-discovered if empty)')
param keyVaultName string = ''

@description('Encryption key name')
param encryptionKeyName string = 'storage-encryption-key'

@description('Key size in bits')
@allowed([2048, 3072, 4096])
param keySize int = 4096

@description('Key rotation interval in ISO 8601 duration format')
param keyRotationInterval string = 'P18M'

@description('Key expiry time in ISO 8601 duration format')
param keyExpiryTime string = 'P2Y'

@description('Deployment timestamp (auto-generated)')
param deploymentTimestamp string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

// ============================================================================
// VARIABLES
// ============================================================================

// Storage account name follows 009-private-storage pattern: stailab<suffix>
var storageAccountName = 'stailab${storageNameSuffix}'

// Managed identity name derived from storage account
var managedIdentityName = 'id-${storageAccountName}-cmk'

// Key Vault Crypto Service Encryption User role ID
var keyVaultCryptoServiceEncryptionUserRoleId = 'e147488a-f6f5-4113-8e2d-b22465e65bf6'

// Tags for new resources (CMK-specific)
var cmkTags = {
  environment: environment
  purpose: 'CMK encryption identity for storage account'
  owner: owner
  deployedBy: 'bicep'
  deployedDate: deploymentTimestamp
  feature: '010-storage-cmk-refactor'
}

// ============================================================================
// EXISTING RESOURCE REFERENCES (T004, T005)
// ============================================================================

// Reference existing Key Vault resource group
resource keyVaultRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: keyVaultResourceGroupName
}

// Reference existing Storage resource group
resource storageRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: storageResourceGroupName
}

// ============================================================================
// KEY VAULT DISCOVERY (when keyVaultName not provided)
// ============================================================================

// Module to discover Key Vault name in rg-ai-keyvault
module keyVaultDiscovery 'kv-discovery.bicep' = {
  name: 'discover-keyvault-${deploymentTimestamp}'
  scope: keyVaultRg
  params: {
    providedKeyVaultName: keyVaultName
  }
}

// ============================================================================
// USER-ASSIGNED MANAGED IDENTITY (T008)
// ============================================================================

// Create managed identity in storage resource group for Key Vault access
module managedIdentity 'mi-cmk.bicep' = {
  name: 'deploy-mi-${managedIdentityName}'
  scope: storageRg
  params: {
    name: managedIdentityName
    location: location
    tags: cmkTags
  }
}

// ============================================================================
// ENCRYPTION KEY (T009)
// ============================================================================

// Create encryption key in Key Vault with rotation policy
module encryptionKey '../modules/storage-key.bicep' = {
  name: 'deploy-key-${encryptionKeyName}'
  scope: keyVaultRg
  params: {
    keyVaultName: keyVaultDiscovery.outputs.keyVaultName
    keyName: encryptionKeyName
    keySize: keySize
    keyRotationInterval: keyRotationInterval
    keyExpiryTime: keyExpiryTime
  }
}

// ============================================================================
// RBAC ROLE ASSIGNMENT (T010)
// ============================================================================

// Assign Key Vault Crypto Service Encryption User role to managed identity
module rbacAssignment '../modules/storage-rbac.bicep' = {
  name: 'deploy-rbac-cmk-${storageAccountName}'
  scope: keyVaultRg
  params: {
    keyVaultName: keyVaultDiscovery.outputs.keyVaultName
    principalId: managedIdentity.outputs.principalId
    roleDefinitionId: keyVaultCryptoServiceEncryptionUserRoleId
  }
}

// ============================================================================
// STORAGE ACCOUNT CMK UPDATE (T011, T012)
// ============================================================================

// Update storage account with CMK configuration
module storageCmk 'storage-cmk-update.bicep' = {
  name: 'update-cmk-${storageAccountName}'
  scope: storageRg
  params: {
    storageAccountName: storageAccountName
    managedIdentityId: managedIdentity.outputs.id
    keyVaultUri: keyVaultDiscovery.outputs.keyVaultUri
    keyName: encryptionKeyName
  }
  dependsOn: [
    encryptionKey
    rbacAssignment
  ]
}

// ============================================================================
// OUTPUTS (per contracts/bicep-interface.md - T007)
// ============================================================================

@description('Managed identity resource ID')
output managedIdentityId string = managedIdentity.outputs.id

@description('Managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId

@description('Encryption key name')
output encryptionKeyName string = encryptionKey.outputs.keyName

@description('Encryption key URI (versionless)')
output encryptionKeyUri string = encryptionKey.outputs.keyUri

@description('Storage account name')
output storageAccountName string = storageAccountName

@description('CMK enabled status')
output cmkEnabled bool = true

@description('Key Vault name')
output keyVaultName string = keyVaultDiscovery.outputs.keyVaultName
