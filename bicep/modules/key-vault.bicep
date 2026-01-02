// Key Vault Module
// Creates Azure Key Vault for centralized secrets management across all AI labs
// Purpose: Secure storage for VPN keys, connection strings, passwords, certificates

targetScope = 'resourceGroup'

// Parameters
@description('Name of the Key Vault (must be globally unique, 3-24 characters)')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('Azure region for deployment')
param location string

@description('Key Vault SKU (standard or premium)')
@allowed([
  'standard'
  'premium'
])
param keyVaultSku string = 'standard'

@description('Enable RBAC authorization (recommended over access policies)')
param enableRbacAuthorization bool = true

@description('Enable soft-delete with 90-day retention (cannot be disabled per Azure policy)')
param enableSoftDelete bool = true

@description('Soft-delete retention period in days')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

@description('Enable purge protection (recommended for production environments)')
param enablePurgeProtection bool = false

@description('Network access default action (Allow or Deny)')
@allowed([
  'Allow'
  'Deny'
])
param networkAclsDefaultAction string = 'Allow'

@description('Tags to apply to resources')
param tags object = {}

// Key Vault - Centralized secrets management for all labs
// Decision rationale: RBAC authorization model provides consistent permissions across Azure
// See research.md: Azure Key Vault Best Practices - RBAC vs Access Policies
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    // Tenant ID for Azure AD authentication
    tenantId: subscription().tenantId
    // SKU selection: standard for secrets/keys, premium adds HSM-backed keys
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    // RBAC authorization model (recommended for new deployments)
    // Access Policies are in maintenance mode per Microsoft guidance
    enableRbacAuthorization: enableRbacAuthorization
    // Soft-delete configuration (required by Azure policy, cannot be disabled)
    // Provides 90-day recovery window for accidentally deleted secrets
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    // Purge protection prevents permanent deletion during retention period
    // Enable for production to prevent malicious or accidental data loss
    enablePurgeProtection: enablePurgeProtection ? true : null
    // Network access controls
    // Initially allow all networks for ease of setup
    // Can restrict to vWAN subnet or private endpoint later for enhanced security
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: networkAclsDefaultAction
      ipRules: []
      virtualNetworkRules: []
    }
    // Public network access enabled initially
    // Can disable and use private endpoint for production
    publicNetworkAccess: 'Enabled'
  }
}

// Outputs for use by main template, spoke labs, and validation scripts
@description('Resource ID of the Key Vault')
output keyVaultId string = keyVault.id

@description('Name of the Key Vault')
output keyVaultName string = keyVault.name

@description('Key Vault URI for secret references')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Key Vault tenant ID')
output keyVaultTenantId string = keyVault.properties.tenantId

@description('Is RBAC authorization enabled')
output enableRbacAuthorization bool = keyVault.properties.enableRbacAuthorization
