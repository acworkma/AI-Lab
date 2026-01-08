// Storage Encryption Key Module
// Creates RSA key in existing Key Vault with rotation policy
// Called from storage.bicep as cross-resource-group deployment

targetScope = 'resourceGroup'

@description('Name of the existing Key Vault')
param keyVaultName string

@description('Name for the encryption key')
param keyName string

@description('Key rotation interval in days')
@minValue(30)
@maxValue(730)
param keyRotationDays int = 90

// Reference existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Create encryption key with rotation policy
resource encryptionKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: keyVault
  name: keyName
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'encrypt'
      'decrypt'
      'wrapKey'
      'unwrapKey'
    ]
    rotationPolicy: {
      lifetimeActions: [
        {
          trigger: {
            timeAfterCreate: 'P${keyRotationDays}D'
          }
          action: {
            type: 'rotate'
          }
        }
        {
          trigger: {
            timeBeforeExpiry: 'P30D'
          }
          action: {
            type: 'notify'
          }
        }
      ]
      attributes: {
        expiryTime: 'P2Y'
      }
    }
  }
}

@description('Key resource ID')
output keyId string = encryptionKey.id

@description('Key URI (without version for auto-rotation)')
output keyUri string = encryptionKey.properties.keyUri

@description('Key URI with version')
output keyUriWithVersion string = encryptionKey.properties.keyUriWithVersion
