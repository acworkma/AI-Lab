// Azure Storage Account Module with Customer-Managed Keys (CMK)
// Creates private storage with CMK encryption, managed identity, and private endpoint
// Purpose: Secure blob storage with organizational control over encryption keys

targetScope = 'resourceGroup'

// ============================================================================
// Required Parameters
// ============================================================================

@description('Globally unique storage account name (3-24 lowercase letters/numbers)')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region for deployment')
param location string

@description('Name of existing Key Vault for encryption key (in core resource group)')
param keyVaultName string

@description('Resource group containing the Key Vault')
param keyVaultResourceGroup string

@description('Name for user-assigned managed identity')
param managedIdentityName string

@description('Shared services VNet name')
param vnetName string

@description('Resource group containing the VNet')
param vnetResourceGroup string

@description('Subnet name for private endpoint')
param privateEndpointSubnetName string

@description('Private DNS zone name for blob storage')
#disable-next-line no-hardcoded-env-urls
param privateDnsZoneName string = 'privatelink.blob.core.windows.net'

@description('Resource group containing the private DNS zone')
param privateDnsZoneResourceGroup string

// ============================================================================
// Optional Parameters
// ============================================================================

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Premium_LRS'
])
param skuName string = 'Standard_LRS'

@description('Enable soft delete for blobs')
param enableBlobSoftDelete bool = true

@description('Blob soft delete retention days (1-365)')
@minValue(1)
@maxValue(365)
param blobSoftDeleteRetentionDays int = 7

@description('Enable soft delete for containers')
param enableContainerSoftDelete bool = true

@description('Container soft delete retention days (1-365)')
@minValue(1)
@maxValue(365)
param containerSoftDeleteRetentionDays int = 7

@description('Enable blob versioning')
param enableVersioning bool = false

@description('Key Vault key name for CMK encryption')
param encryptionKeyName string = 'storage-encryption-key'

@description('Key rotation interval in days (30-730)')
@minValue(30)
@maxValue(730)
param keyRotationDays int = 90

@description('Log Analytics workspace ID for diagnostics (empty = no logging)')
param logAnalyticsWorkspaceId string = ''

@description('Resource tags')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

// Key Vault Crypto Service Encryption User role ID
var keyVaultCryptoServiceEncryptionUserRoleId = 'e147488a-f6f5-4113-8e2d-b22465e65bf6'

// Private endpoint naming
var privateEndpointName = 'pe-${storageAccountName}-blob'

// ============================================================================
// Existing Resources (Cross-Resource-Group References)
// ============================================================================

// Reference existing Key Vault in core resource group
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultResourceGroup)
}

// Reference existing VNet in core resource group
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetResourceGroup)
}

// Reference existing subnet for private endpoint
resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: privateEndpointSubnetName
}

// Reference existing private DNS zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: privateDnsZoneName
  scope: resourceGroup(privateDnsZoneResourceGroup)
}

// ============================================================================
// 1. User-Assigned Managed Identity
// ============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// ============================================================================
// 2. Encryption Key in Key Vault (Cross-RG)
// ============================================================================

// Module to create key in existing Key Vault (cross-resource-group)
module encryptionKey 'storage-key.bicep' = {
  name: 'deploy-${encryptionKeyName}'
  scope: resourceGroup(keyVaultResourceGroup)
  params: {
    keyVaultName: keyVaultName
    keyName: encryptionKeyName
    keyRotationDays: keyRotationDays
  }
}

// ============================================================================
// 3. RBAC Assignment - Key Vault Crypto Service Encryption User
// ============================================================================

// Assign role to managed identity on Key Vault (cross-RG scope)
module keyVaultRoleAssignment 'storage-rbac.bicep' = {
  name: 'rbac-${storageAccountName}-kv'
  scope: resourceGroup(keyVaultResourceGroup)
  params: {
    keyVaultName: keyVaultName
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: keyVaultCryptoServiceEncryptionUserRoleId
  }
  dependsOn: [
    encryptionKey
  ]
}

// ============================================================================
// 4. Storage Account with CMK
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: skuName
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    // Security: Disable public network access
    publicNetworkAccess: 'Disabled'
    // Security: Disable anonymous blob access
    allowBlobPublicAccess: false
    // Security: Require Entra ID authentication (no shared keys)
    allowSharedKeyAccess: false
    // Security: Enforce TLS 1.2+
    minimumTlsVersion: 'TLS1_2'
    // Security: HTTPS only
    supportsHttpsTrafficOnly: true
    // Security: Enable infrastructure encryption (double encryption)
    encryption: {
      requireInfrastructureEncryption: true
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Keyvault'
      keyvaultproperties: {
        keyname: encryptionKeyName
        keyvaulturi: keyVault.properties.vaultUri
      }
      identity: {
        userAssignedIdentity: managedIdentity.id
      }
    }
    // Network: Deny all by default
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'None'
    }
    // Access tier
    accessTier: 'Hot'
  }
  dependsOn: [
    keyVaultRoleAssignment
    encryptionKey
  ]
}

// ============================================================================
// 5. Blob Service Configuration
// ============================================================================

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    // Soft delete for containers
    containerDeleteRetentionPolicy: {
      enabled: enableContainerSoftDelete
      days: containerSoftDeleteRetentionDays
    }
    // Soft delete for blobs
    deleteRetentionPolicy: {
      enabled: enableBlobSoftDelete
      days: blobSoftDeleteRetentionDays
    }
    // Versioning
    isVersioningEnabled: enableVersioning
  }
}

// ============================================================================
// 6. Private Endpoint
// ============================================================================

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${storageAccountName}-blob-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

// ============================================================================
// 7. Private DNS Zone Group
// ============================================================================

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// ============================================================================
// 8. Diagnostic Settings (if Log Analytics workspace provided)
// ============================================================================

resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${storageAccountName}-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
      {
        category: 'Capacity'
        enabled: true
      }
    ]
  }
}

resource blobServiceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${storageAccountName}-blob-diagnostics'
  scope: blobService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'StorageRead'
        enabled: true
      }
      {
        category: 'StorageWrite'
        enabled: true
      }
      {
        category: 'StorageDelete'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
      {
        category: 'Capacity'
        enabled: true
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account resource ID')
output storageAccountId string = storageAccount.id

@description('Blob service endpoint URL')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Private endpoint resource ID')
output blobPrivateEndpointId string = privateEndpoint.id

@description('Private endpoint IP address')
output blobPrivateIpAddress string = privateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]

@description('Managed identity resource ID')
output managedIdentityId string = managedIdentity.id

@description('Managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Encryption key resource ID')
output encryptionKeyId string = encryptionKey.outputs.keyId
