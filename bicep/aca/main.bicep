// Main Bicep Template - Private Azure Container Apps Environment
// Orchestrates deployment of ACA resource group with VNet-injected environment,
// private endpoint connectivity, Log Analytics, and managed identity for ACR
// Purpose: Serverless container hosting infrastructure with private-only access
//
// Deployment scope: Subscription
// Creates: rg-ai-aca -> Log Analytics -> ACA Environment -> Private Endpoint -> DNS registration

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

@description('ACA Environment name')
param environmentName string = 'cae-ai-lab'

@description('ACA resource group name')
param resourceGroupName string = 'rg-ai-aca'

@description('Core infrastructure resource group name')
param coreResourceGroupName string = 'rg-ai-core'

@description('Name of the shared services VNet in core resource group')
param vnetName string = 'vnet-ai-shared'

@description('Subnet name for ACA environment (VNet-injected, minimum /23)')
param acaSubnetName string = 'AcaEnvironmentSubnet'

@description('Subnet name for private endpoints')
param privateEndpointSubnetName string = 'PrivateEndpointSubnet'

@description('Private DNS zone name for Container Apps')
param privateDnsZoneName string = 'privatelink.azurecontainerapps.io'

@description('Enable zone redundancy for ACA environment')
param zoneRedundant bool = false

@description('Existing Log Analytics workspace resource ID (leave empty to create new)')
param existingLogAnalyticsWorkspaceId string = ''

@description('Log Analytics workspace retention in days (when creating new)')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Deployment method for tagging (manual or automation)')
param deployedBy string = 'manual'

@description('Deployment timestamp (auto-generated)')
param deploymentTimestamp string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

// ============================================================================
// VARIABLES
// ============================================================================

var logAnalyticsName = 'log-ai-aca'

var allTags = {
  environment: environment
  purpose: 'Private Container Apps environment'
  owner: owner
  deployedBy: deployedBy
  deployedDate: deploymentTimestamp
  feature: '012-private-aca'
}

var createLogAnalytics = empty(existingLogAnalyticsWorkspaceId)

// ============================================================================
// EXISTING RESOURCES (Cross-Resource-Group References)
// ============================================================================

// Reference existing VNet in core resource group
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
  scope: resourceGroup(coreResourceGroupName)
}

// Reference existing ACA environment subnet
resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: acaSubnetName
}

// Reference existing subnet for private endpoints
resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: privateEndpointSubnetName
}

// Reference existing private DNS zone for Container Apps
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: privateDnsZoneName
  scope: resourceGroup(coreResourceGroupName)
}

// ============================================================================
// RESOURCE GROUP
// ============================================================================

module acaResourceGroup '../modules/resource-group.bicep' = {
  name: 'deploy-${resourceGroupName}'
  params: {
    name: resourceGroupName
    location: location
    environment: environment
    purpose: 'Private Container Apps environment'
    owner: owner
    deployedBy: deployedBy
    additionalTags: {
      project: 'ai-lab'
      component: 'aca'
      feature: '012-private-aca'
    }
  }
}

// ============================================================================
// LOG ANALYTICS WORKSPACE (conditional - only if no existing workspace provided)
// ============================================================================

module logAnalytics '../modules/log-analytics.bicep' = if (createLogAnalytics) {
  name: 'deploy-${logAnalyticsName}'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    workspaceName: logAnalyticsName
    location: location
    retentionInDays: logAnalyticsRetentionDays
    tags: allTags
  }
  dependsOn: [
    acaResourceGroup
  ]
}

// ============================================================================
// CONTAINER APPS ENVIRONMENT
// ============================================================================

module acaEnvironment '../modules/aca-environment.bicep' = {
  name: 'deploy-${environmentName}'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    environmentName: environmentName
    location: location
    infrastructureSubnetId: acaSubnet.id
    logAnalyticsWorkspaceId: createLogAnalytics ? logAnalytics.outputs.workspaceId : existingLogAnalyticsWorkspaceId
    privateEndpointSubnetId: privateEndpointSubnet.id
    privateDnsZoneId: privateDnsZone.id
    zoneRedundant: zoneRedundant
    tags: allTags
  }
  dependsOn: [
    acaResourceGroup
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Resource group name where ACA environment is deployed')
output resourceGroupName string = resourceGroupName

@description('Container Apps Environment name')
output environmentName string = acaEnvironment.outputs.environmentName

@description('Container Apps Environment resource ID')
output environmentId string = acaEnvironment.outputs.environmentId

@description('Container Apps Environment default domain')
output defaultDomain string = acaEnvironment.outputs.defaultDomain

@description('Container Apps Environment static IP')
output staticIp string = acaEnvironment.outputs.staticIp

@description('Private endpoint IP address (for DNS verification)')
output privateEndpointIp string = acaEnvironment.outputs.privateEndpointIp

@description('Log Analytics workspace resource ID')
output logAnalyticsWorkspaceId string = createLogAnalytics ? logAnalytics.outputs.workspaceId : existingLogAnalyticsWorkspaceId
