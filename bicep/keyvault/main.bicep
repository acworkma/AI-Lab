// Main Bicep Template - Private Azure Key Vault
// Orchestrates deployment of Key Vault resource group with private endpoint connectivity
// Purpose: Secure centralized secrets management with private endpoint access only
//
// Deployment scope: Subscription
// Creates: rg-ai-keyvault -> Key Vault -> Private Endpoint -> DNS registration

targetScope = 'subscription'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Azure region for all resources')
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

@description('Unique suffix for Key Vault name (defaults to MMDD, override for same-day redeploy)')
param keyVaultNameSuffix string = utcNow('MMdd')

@description('Key Vault resource group name')
param resourceGroupName string = 'rg-ai-keyvault'

@description('Core infrastructure resource group name')
param coreResourceGroupName string = 'rg-ai-core'

@description('Name of the shared services VNet in core resource group')
param vnetName string = 'vnet-ai-shared'

@description('Subnet name for private endpoints')
param privateEndpointSubnetName string = 'PrivateEndpointSubnet'

@description('Private DNS zone name for Key Vault')
param privateDnsZoneName string = 'privatelink.vaultcore.azure.net'

@description('Key Vault SKU (standard or premium for HSM-backed keys)')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Enable purge protection (CANNOT be disabled once enabled - enable for prod)')
param enablePurgeProtection bool = false

@description('Deployment method for tagging (manual or automation)')
param deployedBy string = 'manual'

@description('Deployment timestamp (auto-generated)')
param deploymentTimestamp string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

// ============================================================================
// VARIABLES
// ============================================================================

// Key Vault name with unique suffix to avoid soft-delete collision
// Pattern: kv-ai-lab-<MMDD> (e.g., kv-ai-lab-0117)
var keyVaultName = 'kv-ai-lab-${keyVaultNameSuffix}'

// Resource tags following constitution requirements
var allTags = {
  environment: environment
  purpose: 'Key Vault for centralized secrets management'
  owner: owner
  deployedBy: deployedBy
  deployedDate: deploymentTimestamp
  feature: '008-private-keyvault'
}

// ============================================================================
// EXISTING RESOURCES (Cross-Resource-Group References)
// ============================================================================

// Reference existing VNet in core resource group
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
  scope: resourceGroup(coreResourceGroupName)
}

// Reference existing subnet for private endpoints
resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: privateEndpointSubnetName
}

// Reference existing private DNS zone for Key Vault
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: privateDnsZoneName
  scope: resourceGroup(coreResourceGroupName)
}

// ============================================================================
// RESOURCE GROUP
// ============================================================================

// Resource Group - Container for Key Vault infrastructure
// Following constitution naming: rg-ai-[service]
module keyVaultResourceGroup '../modules/resource-group.bicep' = {
  name: 'deploy-${resourceGroupName}'
  params: {
    name: resourceGroupName
    location: location
    environment: environment
    purpose: 'Key Vault for centralized secrets management'
    owner: owner
    deployedBy: deployedBy
    additionalTags: {
      project: 'ai-lab'
      component: 'keyvault'
      feature: '008-private-keyvault'
    }
  }
}

// ============================================================================
// KEY VAULT MODULE
// ============================================================================

// Deploy Key Vault with private endpoint and DNS integration
module keyVault '../modules/key-vault.bicep' = {
  name: 'deploy-${keyVaultName}'
  scope: resourceGroup(resourceGroupName)
  params: {
    keyVaultName: keyVaultName
    location: location
    privateEndpointSubnetId: privateEndpointSubnet.id
    privateDnsZoneId: privateDnsZone.id
    skuName: skuName
    enablePurgeProtection: enablePurgeProtection
    enabledForTemplateDeployment: true  // Allow Bicep Key Vault references
    tags: allTags
  }
  dependsOn: [
    keyVaultResourceGroup
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Resource group name where Key Vault is deployed')
output resourceGroupName string = resourceGroupName

@description('Key Vault name')
output keyVaultName string = keyVault.outputs.name

@description('Key Vault URI (https://...)')
output keyVaultUri string = keyVault.outputs.uri

@description('Key Vault resource ID')
output keyVaultId string = keyVault.outputs.id

@description('Private endpoint IP address (for DNS verification)')
output privateEndpointIp string = keyVault.outputs.privateEndpointIp
