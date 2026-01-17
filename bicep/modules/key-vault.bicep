// Azure Key Vault Module with Private Endpoint
// Creates private Key Vault with RBAC authorization, soft-delete, and private endpoint connectivity
// Purpose: Secure centralized secrets management with no public network exposure
//
// Security Decisions (SR-001 to SR-006):
// - Public network access disabled (SR-001): All access via private endpoint only
// - RBAC authorization (SR-002): Modern authorization model, no legacy access policies
// - Soft-delete enabled (SR-003): Protection against accidental deletion, 90-day retention
// - Purge protection configurable (SR-004): Disabled for lab, enable for production
// - Template deployment enabled: Allows Bicep parameter file Key Vault references

targetScope = 'resourceGroup'

// ============================================================================
// REQUIRED PARAMETERS
// ============================================================================

@description('Name of the Key Vault (3-24 characters, alphanumeric and hyphens)')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('Azure region for deployment')
param location string

@description('Resource ID of the subnet for private endpoint')
param privateEndpointSubnetId string

@description('Resource ID of the privatelink.vaultcore.azure.net DNS zone')
param privateDnsZoneId string

// ============================================================================
// OPTIONAL PARAMETERS
// ============================================================================

@description('Key Vault SKU (standard or premium for HSM-backed keys)')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Enable purge protection (CANNOT be disabled once enabled)')
param enablePurgeProtection bool = false

@description('Soft-delete retention in days (7-90)')
@minValue(7)
@maxValue(90)
param softDeleteRetentionDays int = 90

@description('Allow Bicep/ARM template deployments to retrieve secrets')
param enabledForTemplateDeployment bool = true

@description('Allow VMs to retrieve certificates')
param enabledForDeployment bool = false

@description('Allow Azure Disk Encryption to retrieve secrets')
param enabledForDiskEncryption bool = false

@description('Resource tags')
param tags object = {}

// ============================================================================
// VARIABLES
// ============================================================================

// Private endpoint naming convention
var privateEndpointName = '${keyVaultName}-pe'
var privateLinkServiceConnectionName = '${keyVaultName}-plsc'

// ============================================================================
// KEY VAULT RESOURCE
// ============================================================================

// Key Vault with RBAC authorization and private endpoint only access
// SR-001: Public network access disabled
// SR-002: RBAC authorization (enableRbacAuthorization: true)
// SR-003: Soft-delete enabled
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    // Tenant configuration
    tenantId: subscription().tenantId
    
    // SKU configuration (FR-009: Standard SKU)
    sku: {
      family: 'A'
      name: skuName
    }
    
    // Authorization: RBAC only (FR-005, SR-002)
    // No access policies - all permissions via Azure RBAC
    enableRbacAuthorization: true
    accessPolicies: []
    
    // Soft-delete configuration (FR-006, SR-003)
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionDays
    
    // Purge protection (SR-004) - configurable, disabled for lab
    enablePurgeProtection: enablePurgeProtection ? true : null
    
    // Template deployment integration (FR-003 for Bicep references)
    enabledForTemplateDeployment: enabledForTemplateDeployment
    enabledForDeployment: enabledForDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    
    // Network configuration (FR-004, SR-001)
    // All traffic must use private endpoint
    // Note: AzureServices bypass required when enabledForTemplateDeployment is true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: enabledForTemplateDeployment ? 'AzureServices' : 'None'
      defaultAction: 'Deny'    // Deny all public access
      ipRules: []              // No IP allowlist
      virtualNetworkRules: []  // No VNet rules (using private endpoint)
    }
  }
}

// ============================================================================
// PRIVATE ENDPOINT
// ============================================================================

// Private endpoint for Key Vault (FR-007)
// Connects Key Vault to snet-private-endpoints in shared services VNet
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: privateLinkServiceConnectionName
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'  // Key Vault subresource type
          ]
        }
      }
    ]
  }
}

// ============================================================================
// PRIVATE DNS ZONE GROUP
// ============================================================================

// DNS zone group for automatic A record registration (FR-008)
// Creates: <vault-name>.privatelink.vaultcore.azure.net -> private IP
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'keyvault-dns-config'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Key Vault name')
output name string = keyVault.name

@description('Key Vault resource ID')
output id string = keyVault.id

@description('Key Vault URI (https://...)')
output uri string = keyVault.properties.vaultUri

@description('Private endpoint resource ID')
output privateEndpointId string = privateEndpoint.id

@description('Private endpoint private IP address')
output privateEndpointIp string = privateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
