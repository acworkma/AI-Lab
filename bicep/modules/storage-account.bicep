// ============================================================================
// Module: storage-account.bicep
// Purpose: Reusable Azure Storage Account with private endpoint and RBAC
// Feature: 009-private-storage
// ============================================================================

@description('Azure region for deployment')
param location string = 'eastus2'

@description('Environment tag value')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Owner tag value - required')
param owner string

@description('Unique suffix for storage account name (default: MMDD)')
param storageNameSuffix string

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param skuName string = 'Standard_LRS'

@description('Enable blob soft-delete')
param enableBlobSoftDelete bool = true

@description('Soft-delete retention in days')
@minValue(1)
@maxValue(365)
param softDeleteRetentionDays int = 7

@description('Resource ID of subnet for private endpoint')
param privateEndpointSubnetId string

@description('Resource ID of privatelink.blob.core.windows.net DNS zone')
param privateDnsZoneId string

@description('Principal ID to assign Storage Blob Data Contributor role (optional)')
param adminPrincipalId string = ''

// ============================================================================
// Variables
// ============================================================================

var storageAccountName = 'stailab${storageNameSuffix}'
var privateEndpointName = '${storageAccountName}-pe'

var tags = {
  environment: environment
  purpose: 'Private Storage Account infrastructure'
  owner: owner
  deployedBy: 'bicep'
}

// Storage Blob Data Contributor role GUID
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// ============================================================================
// Storage Account
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowSharedKeyAccess: false  // RBAC-only authentication
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'None'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// ============================================================================
// Blob Services (soft-delete configuration)
// ============================================================================

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: enableBlobSoftDelete
      days: softDeleteRetentionDays
    }
  }
}

// ============================================================================
// Private Endpoint
// ============================================================================

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
        name: '${storageAccountName}-plsc'
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
// DNS Zone Group (auto-registers A record in private DNS zone)
// ============================================================================

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob-dns'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// ============================================================================
// Optional RBAC Assignment (Storage Blob Data Contributor)
// ============================================================================

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(adminPrincipalId)) {
  scope: storageAccount
  name: guid(storageAccount.id, adminPrincipalId, storageBlobDataContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: adminPrincipalId
    principalType: 'User'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource ID of the storage account')
output storageAccountId string = storageAccount.id

@description('Name of the storage account')
output storageAccountName string = storageAccount.name

@description('Blob service endpoint URL')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Resource ID of the private endpoint')
output privateEndpointId string = privateEndpoint.id

@description('Private endpoint name (use az cli to get IP: az network nic show --ids $(az network private-endpoint show -n <pe-name> -g <rg> --query networkInterfaces[0].id -o tsv) --query ipConfigurations[0].privateIPAddress)')
output privateEndpointName string = privateEndpoint.name
