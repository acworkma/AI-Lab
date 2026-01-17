# Bicep Interface Contract: Storage CMK

**Module**: `bicep/storage/main.bicep`  
**Scope**: Subscription  
**Purpose**: Enable CMK encryption on existing Storage Account

## Parameters

```bicep
// Required Parameters
@description('Azure region for managed identity')
param location string = 'eastus2'

@description('Environment tag (dev, test, or prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Owner identifier for resource tagging')
@minLength(1)
@maxLength(100)
param owner string

@description('Storage account name suffix (must match existing storage account)')
param storageNameSuffix string

// Optional Parameters with Defaults
@description('Key Vault resource group name')
param keyVaultResourceGroupName string = 'rg-ai-keyvault'

@description('Storage resource group name')
param storageResourceGroupName string = 'rg-ai-storage'

@description('Key Vault name (auto-discovered if not provided)')
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
```

## Outputs

```bicep
@description('Managed identity resource ID')
output managedIdentityId string

@description('Managed identity principal ID')
output managedIdentityPrincipalId string

@description('Encryption key name')
output encryptionKeyName string

@description('Encryption key URI (versionless)')
output encryptionKeyUri string

@description('Storage account name')
output storageAccountName string

@description('CMK enabled status')
output cmkEnabled bool = true
```

## Prerequisites

The following resources must exist before deployment:

| Resource | Resource Group | Deployed By |
|----------|----------------|-------------|
| Key Vault | rg-ai-keyvault | 008-private-keyvault |
| Storage Account | rg-ai-storage | 009-private-storage |
| Private DNS Zones | rg-ai-core | 001-vwan-core |

## Example Usage

```bash
# Deploy with what-if validation
az deployment sub create \
  --location eastus2 \
  --template-file bicep/storage/main.bicep \
  --parameters storageNameSuffix=0117 owner=adworkma \
  --what-if

# Actual deployment
az deployment sub create \
  --location eastus2 \
  --template-file bicep/storage/main.bicep \
  --parameters storageNameSuffix=0117 owner=adworkma
```
