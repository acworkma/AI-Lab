// Storage Encryption Key Module
// Creates RSA key in existing Key Vault with rotation policy
// Called from storage/main.bicep as cross-resource-group deployment
// Feature: 010-storage-cmk-refactor

targetScope = 'resourceGroup'

@description('Name of the existing Key Vault')
param keyVaultName string

@description('Name for the encryption key')
param keyName string

@description('Key size in bits (2048, 3072, or 4096)')
@allowed([2048, 3072, 4096])
param keySize int = 4096

@description('Key rotation interval in ISO 8601 duration format (e.g., P18M for 18 months)')
param keyRotationInterval string = 'P18M'

@description('Key expiry time in ISO 8601 duration format (e.g., P2Y for 2 years)')
param keyExpiryTime string = 'P2Y'

// Reference existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Create encryption key with rotation policy (RSA 4096 recommended per research.md)
resource encryptionKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: keyVault
  name: keyName
  properties: {
    kty: 'RSA'
    keySize: keySize
    keyOps: [
      'wrapKey'
      'unwrapKey'
    ]
    rotationPolicy: {
      lifetimeActions: [
        {
          trigger: {
            timeAfterCreate: keyRotationInterval
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
        expiryTime: keyExpiryTime
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

@description('Key name')
output keyName string = encryptionKey.name
