// ============================================================================
// Orchestration: main.bicep
// Purpose: Deploy Private Azure Storage Account infrastructure
// Feature: 009-private-storage
// Scope: Subscription-level deployment
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Azure region for deployment')
param location string = 'eastus2'

@description('Environment tag value')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Owner tag value')
param owner string

@description('Unique suffix for storage account name (default: MMDD format)')
param storageNameSuffix string = utcNow('MMdd')

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param skuName string = 'Standard_LRS'

@description('Enable blob soft-delete')
param enableBlobSoftDelete bool = true

@description('Soft-delete retention in days')
param softDeleteRetentionDays int = 7

@description('Core infrastructure resource group name')
param coreResourceGroupName string = 'rg-ai-core'

@description('Shared services VNet name')
param vnetName string = 'vnet-ai-shared'

@description('Private endpoint subnet name')
param subnetName string = 'PrivateEndpointSubnet'

@description('Principal ID to assign Storage Blob Data Contributor role (optional)')
param adminPrincipalId string = ''

// ============================================================================
// Variables
// ============================================================================

var storageResourceGroupName = 'rg-ai-storage'

var tags = {
  environment: environment
  purpose: 'Private Storage Account infrastructure'
  owner: owner
  deployedBy: 'bicep'
}

// ============================================================================
// Existing Resources (from core infrastructure)
// ============================================================================

resource coreResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: coreResourceGroupName
}

resource existingVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  scope: coreResourceGroup
  name: vnetName
}

resource existingSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: existingVnet
  name: subnetName
}

resource existingDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  scope: coreResourceGroup
  // Using hardcoded zone name as this is Azure Public Cloud specific
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.blob.core.windows.net'
}

// ============================================================================
// Resource Group
// ============================================================================

resource storageResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: storageResourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// Storage Account Module
// ============================================================================

module storageAccount '../modules/storage-account.bicep' = {
  scope: storageResourceGroup
  name: 'storage-account-deployment-${uniqueString(deployment().name)}'
  params: {
    location: location
    environment: environment
    owner: owner
    storageNameSuffix: storageNameSuffix
    skuName: skuName
    enableBlobSoftDelete: enableBlobSoftDelete
    softDeleteRetentionDays: softDeleteRetentionDays
    privateEndpointSubnetId: existingSubnet.id
    privateDnsZoneId: existingDnsZone.id
    adminPrincipalId: adminPrincipalId
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource group name')
output resourceGroupName string = storageResourceGroup.name

@description('Storage account resource ID')
output storageAccountId string = storageAccount.outputs.storageAccountId

@description('Storage account name')
output storageAccountName string = storageAccount.outputs.storageAccountName

@description('Blob service endpoint URL')
output blobEndpoint string = storageAccount.outputs.blobEndpoint

@description('Private endpoint resource ID')
output privateEndpointId string = storageAccount.outputs.privateEndpointId

@description('Private endpoint name')
output privateEndpointName string = storageAccount.outputs.privateEndpointName
