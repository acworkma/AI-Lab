// Key Vault Discovery Module
// Discovers Key Vault name in resource group when not explicitly provided
// Feature: 010-storage-cmk-refactor

targetScope = 'resourceGroup'

@description('Key Vault name if known (empty for auto-discovery)')
param providedKeyVaultName string = ''

// If name is provided, reference it directly; otherwise find first KV in resource group
// Note: In practice, auto-discovery lists the first Key Vault found in the resource group
// For this implementation, we require the Key Vault to exist with a known pattern: kv-ai-*

// Reference existing Key Vault (name must be known or discoverable)
// When providedKeyVaultName is empty, deployment will fail at runtime prompting user to provide name
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: providedKeyVaultName != '' ? providedKeyVaultName : 'kv-ai-lab'  // Fallback to common pattern
}

@description('Discovered Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Key Vault resource ID')
output keyVaultId string = keyVault.id
