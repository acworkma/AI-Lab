// Main Bicep Template - Private Azure Storage Account with CMK
// Orchestrates deployment of storage resource group and CMK-enabled storage account
// Purpose: Secure blob storage with customer-managed encryption keys and private endpoint

targetScope = 'subscription'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Azure region for all resources')
param location string = 'eastus'

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

@description('Storage account name (3-24 lowercase letters/numbers, globally unique)')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Storage resource group name')
param resourceGroupName string = 'rg-ai-storage'

@description('Core infrastructure resource group name')
param coreResourceGroupName string = 'rg-ai-core'

@description('Name of the Key Vault in core resource group')
param keyVaultName string

@description('Name of the shared services VNet in core resource group')
param vnetName string = 'vnet-ai-sharedservices'

@description('Subnet name for private endpoints')
param privateEndpointSubnetName string = 'snet-private-endpoints'

@description('Private DNS zone name for blob storage')
#disable-next-line no-hardcoded-env-urls
param privateDnsZoneName string = 'privatelink.blob.core.windows.net'

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
])
param skuName string = 'Standard_LRS'

@description('Log Analytics workspace ID for diagnostics (empty = no logging)')
param logAnalyticsWorkspaceId string = ''

@description('Enable blob versioning')
param enableVersioning bool = false

@description('Deployment method for tagging (manual or automation)')
param deployedBy string = 'manual'

@description('Additional custom tags')
param customTags object = {}

@description('Deployment timestamp (auto-generated)')
param deploymentTimestamp string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

// ============================================================================
// VARIABLES
// ============================================================================

// Managed identity name derived from storage account
var managedIdentityName = 'id-${storageAccountName}-cmk'

// Encryption key name
var encryptionKeyName = 'storage-encryption-key'

// Merged tags combining constitutional requirements and custom tags
var allTags = union({
  environment: environment
  purpose: 'Private storage with CMK encryption for AI labs'
  owner: owner
  deployedBy: deployedBy
  deployedDate: deploymentTimestamp
  feature: '005-storage-cmk'
}, customTags)

// ============================================================================
// RESOURCE GROUP
// ============================================================================

// Resource Group - Container for storage infrastructure
module storageResourceGroup '../modules/resource-group.bicep' = {
  name: 'deploy-${resourceGroupName}'
  params: {
    name: resourceGroupName
    location: location
    environment: environment
    purpose: 'Private storage with CMK encryption for AI labs'
    owner: owner
    deployedBy: deployedBy
    additionalTags: union({
      project: 'ai-lab'
      component: 'storage'
      feature: '005-storage-cmk'
    }, customTags)
  }
}

// ============================================================================
// STORAGE MODULE
// ============================================================================

// Deploy storage account with CMK, private endpoint, and diagnostics
module storage '../modules/storage.bicep' = {
  name: 'deploy-${storageAccountName}'
  scope: resourceGroup(resourceGroupName)
  params: {
    storageAccountName: storageAccountName
    location: location
    keyVaultName: keyVaultName
    keyVaultResourceGroup: coreResourceGroupName
    managedIdentityName: managedIdentityName
    vnetName: vnetName
    vnetResourceGroup: coreResourceGroupName
    privateEndpointSubnetName: privateEndpointSubnetName
    privateDnsZoneName: privateDnsZoneName
    privateDnsZoneResourceGroup: coreResourceGroupName
    skuName: skuName
    enableVersioning: enableVersioning
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    encryptionKeyName: encryptionKeyName
    tags: allTags
  }
  dependsOn: [
    storageResourceGroup
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Storage account name')
output storageAccountName string = storage.outputs.storageAccountName

@description('Storage account resource ID')
output storageAccountId string = storage.outputs.storageAccountId

@description('Blob service endpoint URL')
output blobEndpoint string = storage.outputs.blobEndpoint

@description('Private endpoint IP address')
output blobPrivateIpAddress string = storage.outputs.blobPrivateIpAddress

@description('Managed identity principal ID')
output managedIdentityPrincipalId string = storage.outputs.managedIdentityPrincipalId

@description('Resource group name')
output resourceGroupName string = resourceGroupName
