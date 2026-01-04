// Main Bicep Template - Private Azure Container Registry
// Orchestrates deployment of ACR resource group and private container registry
// Purpose: Private container image storage with private endpoint connectivity to core infrastructure

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

@description('ACR resource group name')
param resourceGroupName string = 'rg-ai-acr'

@description('Core infrastructure resource group name')
param coreResourceGroupName string = 'rg-ai-core'

@description('ACR SKU (Standard or Premium)')
@allowed([
  'Standard'
  'Premium'
])
param acrSku string = 'Standard'

@description('Resource ID of the private endpoint subnet from core infrastructure')
param privateEndpointSubnetId string

@description('Resource ID of the ACR private DNS zone from core infrastructure')
param acrDnsZoneId string

@description('Deployment method for tagging (manual or automation)')
param deployedBy string = 'manual'

@description('Additional custom tags')
param tags object = {}

@description('Deployment timestamp (auto-generated)')
param deploymentTimestamp string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

// ============================================================================
// VARIABLES
// ============================================================================

// Generate unique ACR name using resource group ID hash
var uniqueSuffix = uniqueString(subscription().subscriptionId, resourceGroupName)
var acrName = 'acraihub${uniqueSuffix}'

// Merged tags combining constitutional requirements and custom tags
var allTags = union({
  environment: environment
  purpose: 'Private container registry for AI labs'
  owner: owner
  deployedBy: deployedBy
  deployedDate: deploymentTimestamp
}, tags)

// ============================================================================
// RESOURCE GROUP
// ============================================================================

// Resource Group - Container for ACR infrastructure
module resourceGroup '../modules/resource-group.bicep' = {
  name: 'deploy-rg-ai-acr'
  params: {
    name: resourceGroupName
    location: location
    environment: environment
    purpose: 'Private container registry for AI labs'
    owner: owner
    deployedBy: deployedBy
    deploymentTimestamp: deploymentTimestamp
    additionalTags: tags
  }
}

// ============================================================================
// AZURE CONTAINER REGISTRY
// ============================================================================

// Azure Container Registry - Private container image registry
// Deployment time: ~2-3 minutes
// Requires core infrastructure (shared services VNet and DNS zones) to be deployed first
module acr '../modules/acr.bicep' = {
  name: 'deploy-acr'
  scope: az.resourceGroup(resourceGroupName)
  dependsOn: [
    resourceGroup
  ]
  params: {
    acrName: acrName
    location: location
    acrSku: acrSku
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    // Private endpoint subnet from core infrastructure (passed as parameter)
    privateEndpointSubnetId: privateEndpointSubnetId
    // ACR DNS zone from core infrastructure (passed as parameter)
    acrDnsZoneId: acrDnsZoneId
    tags: allTags
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

// Resource Group Outputs
@description('Resource ID of the ACR resource group')
output resourceGroupId string = resourceGroup.outputs.id

@description('Name of the ACR resource group')
output resourceGroupName string = resourceGroup.outputs.name

// ACR Outputs
@description('Resource ID of the Azure Container Registry')
output acrId string = acr.outputs.acrId

@description('Name of the Azure Container Registry')
output acrName string = acr.outputs.acrName

@description('ACR login server URL')
output acrLoginServer string = acr.outputs.acrLoginServer

@description('ACR SKU')
output acrSku string = acr.outputs.acrSku

@description('Private endpoint resource ID')
output privateEndpointId string = acr.outputs.privateEndpointId

// Deployment Metadata
@description('All applied tags')
output appliedTags object = allTags

@description('Deployment timestamp')
output deploymentTimestamp string = deploymentTimestamp
