// Private Foundry Infrastructure Orchestration (Phase 2)
// Deploys:
// - Dedicated delegated subnet + private endpoint subnet in shared VNet
// - Foundry account and model deployment
// - Dedicated AI Search, Storage, Cosmos DB dependencies
// - Private endpoints + centralized private DNS zone groups
// - Foundry project + pre-capability-host RBAC assignments

targetScope = 'subscription'

@description('Azure region for deployment')
param location string = 'eastus2'

@description('Environment tag (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Owner tag value')
param owner string = 'AI-Lab Team'

@description('Resource group name for Private Foundry resources')
param foundryResourceGroupName string = 'rg-ai-foundry'

@description('Core resource group containing shared VNet and centralized private DNS zones')
param coreResourceGroupName string = 'rg-ai-core'

@description('Shared services VNet name')
param sharedVnetName string = 'vnet-ai-shared'

@description('Delegated Agent subnet name (must be exclusive per Foundry account)')
param agentSubnetName string = 'snet-foundry-agent'

@description('Delegated Agent subnet address prefix')
param agentSubnetPrefix string = '10.1.0.128/25'

@description('Private Endpoint subnet name for Foundry resources')
param privateEndpointSubnetName string = 'PrivateEndpointSubnet'

@description('Private Endpoint subnet address prefix')
param privateEndpointSubnetPrefix string = '10.1.0.0/26'

@description('Additional custom tags')
param tags object = {}

@description('Foundry account base name prefix')
param foundryAccountPrefix string = 'fdryailab'

@description('Foundry project base name prefix')
param foundryProjectPrefix string = 'proj'

@description('Foundry project display name')
param foundryProjectDisplayName string = 'AI-Lab Private Foundry Project'

@description('Foundry project description')
param foundryProjectDescription string = 'Private network secured Foundry project'

@description('Model deployment name')
param modelName string = 'gpt-4.1'

@description('Model format/provider')
param modelFormat string = 'OpenAI'

@description('Model version')
param modelVersion string = '2025-04-14'

@description('Model SKU')
param modelSkuName string = 'GlobalStandard'

@description('Model capacity')
param modelCapacity int = 30

@description('Project capability host name')
param projectCapHostName string = 'caphostproj'

@description('Account capability host name')
param accountCapHostName string = 'caphostaccount'

@description('Create account capability host resource. Set false when service auto-creates one for the same client identity.')
param createAccountCapabilityHost bool = false

var allTags = union({
  environment: environment
  purpose: 'private-foundry-infrastructure'
  owner: owner
  deployedBy: 'bicep'
  project: '012-private-foundry'
}, tags)

var uniqueSuffix = substring(uniqueString(subscription().subscriptionId, foundryResourceGroupName, location), 0, 6)
var foundryAccountName = toLower('${foundryAccountPrefix}${uniqueSuffix}')
var foundryProjectName = toLower('${foundryProjectPrefix}${uniqueSuffix}')
var aiSearchName = toLower('${foundryAccountName}search')
var storageAccountNameBase = replace('${foundryAccountName}storage', '-', '')
var storageAccountName = toLower(length(storageAccountNameBase) > 24 ? substring(storageAccountNameBase, 0, 24) : storageAccountNameBase)
var cosmosDbName = toLower('${foundryAccountName}cosmosdb')

resource foundryResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: foundryResourceGroupName
  location: location
  tags: allTags
}

resource sharedVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  scope: resourceGroup(coreResourceGroupName)
  name: sharedVnetName
}

module foundrySubnets '../modules/foundry-subnets.bicep' = {
  name: 'deploy-foundry-subnets'
  scope: resourceGroup(coreResourceGroupName)
  params: {
    sharedVnetName: sharedVnetName
    agentSubnetName: agentSubnetName
    agentSubnetPrefix: agentSubnetPrefix
    privateEndpointSubnetName: privateEndpointSubnetName
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
  }
}

module foundryAccount '../modules/foundry-account.bicep' = {
  name: 'deploy-foundry-account'
  scope: foundryResourceGroup
  params: {
    accountName: foundryAccountName
    location: location
    modelName: modelName
    modelFormat: modelFormat
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
    agentSubnetId: foundrySubnets.outputs.agentSubnetId
    enableNetworkInjection: true
    tags: allTags
  }
}

module foundryDependencies '../modules/foundry-dependent-resources.bicep' = {
  name: 'deploy-foundry-dependencies'
  scope: foundryResourceGroup
  params: {
    location: location
    aiSearchName: aiSearchName
    storageAccountName: storageAccountName
    cosmosDbName: cosmosDbName
    tags: allTags
  }
}

module privateEndpointAndDns '../modules/foundry-private-endpoint-dns.bicep' = {
  name: 'deploy-foundry-private-endpoints'
  scope: foundryResourceGroup
  params: {
    aiAccountName: foundryAccount.outputs.accountName
    aiSearchName: foundryDependencies.outputs.aiSearchName
    storageName: foundryDependencies.outputs.storageName
    cosmosDbName: foundryDependencies.outputs.cosmosDbName
    coreResourceGroupName: coreResourceGroupName
    vnetName: sharedVnetName
    peSubnetName: privateEndpointSubnetName
    tags: allTags
  }
}

module foundryProject '../modules/foundry-project.bicep' = {
  name: 'deploy-foundry-project'
  scope: foundryResourceGroup
  params: {
    accountName: foundryAccount.outputs.accountName
    location: location
    projectName: foundryProjectName
    projectDescription: foundryProjectDescription
    displayName: foundryProjectDisplayName
    aiSearchName: foundryDependencies.outputs.aiSearchName
    cosmosDbName: foundryDependencies.outputs.cosmosDbName
    storageName: foundryDependencies.outputs.storageName
  }
  dependsOn: [
    privateEndpointAndDns
  ]
}

module storageRoleAssignment '../modules/foundry-storage-account-role-assignment.bicep' = {
  name: 'foundry-storage-account-rbac'
  scope: foundryResourceGroup
  params: {
    storageAccountName: foundryDependencies.outputs.storageName
    projectPrincipalId: foundryProject.outputs.projectPrincipalId
  }
  dependsOn: [
    privateEndpointAndDns
  ]
}

module searchRoleAssignment '../modules/foundry-search-role-assignments.bicep' = {
  name: 'foundry-search-rbac'
  scope: foundryResourceGroup
  params: {
    aiSearchName: foundryDependencies.outputs.aiSearchName
    projectPrincipalId: foundryProject.outputs.projectPrincipalId
  }
  dependsOn: [
    privateEndpointAndDns
  ]
}

module cosmosRoleAssignment '../modules/foundry-cosmosdb-account-role-assignment.bicep' = {
  name: 'foundry-cosmos-rbac'
  scope: foundryResourceGroup
  params: {
    cosmosDbName: foundryDependencies.outputs.cosmosDbName
    projectPrincipalId: foundryProject.outputs.projectPrincipalId
  }
  dependsOn: [
    privateEndpointAndDns
  ]
}

module formatProjectWorkspaceId '../modules/foundry-format-project-workspace-id.bicep' = {
  name: 'foundry-format-project-workspace-id'
  scope: foundryResourceGroup
  params: {
    projectWorkspaceId: foundryProject.outputs.projectWorkspaceId
  }
}

module addAccountCapabilityHost '../modules/foundry-add-account-capability-host.bicep' = if (createAccountCapabilityHost) {
  name: 'foundry-account-capability-host-${substring(uniqueString(deployment().name), 0, 6)}'
  scope: foundryResourceGroup
  params: {
    accountName: foundryAccount.outputs.accountName
    accountCapHost: accountCapHostName
    customerSubnetId: foundrySubnets.outputs.agentSubnetId
  }
}

module addProjectCapabilityHost '../modules/foundry-add-project-capability-host.bicep' = {
  name: 'foundry-project-capability-host'
  scope: foundryResourceGroup
  params: {
    accountName: foundryAccount.outputs.accountName
    projectName: foundryProject.outputs.projectName
    projectCapHost: projectCapHostName
    cosmosDbConnection: foundryProject.outputs.cosmosDbConnection
    storageConnection: foundryProject.outputs.storageConnection
    aiSearchConnection: foundryProject.outputs.aiSearchConnection
  }
  dependsOn: [
    addAccountCapabilityHost
    storageRoleAssignment
    searchRoleAssignment
    cosmosRoleAssignment
  ]
}

module storageContainerRoleAssignments '../modules/foundry-blob-storage-container-role-assignments.bicep' = {
  name: 'foundry-storage-container-rbac'
  scope: foundryResourceGroup
  params: {
    storageName: foundryDependencies.outputs.storageName
    aiProjectPrincipalId: foundryProject.outputs.projectPrincipalId
    workspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
  }
  dependsOn: [
    addProjectCapabilityHost
  ]
}

module cosmosContainerRoleAssignments '../modules/foundry-cosmos-container-role-assignments.bicep' = {
  name: 'foundry-cosmos-container-rbac'
  scope: foundryResourceGroup
  params: {
    cosmosAccountName: foundryDependencies.outputs.cosmosDbName
    projectPrincipalId: foundryProject.outputs.projectPrincipalId
    projectWorkspaceId: formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid
  }
  dependsOn: [
    addProjectCapabilityHost
    storageContainerRoleAssignments
  ]
}

@description('Foundry resource group name')
output resourceGroupName string = foundryResourceGroup.name

@description('Shared VNet resource ID')
output sharedVnetId string = sharedVnet.id

@description('Delegated Agent subnet resource ID')
output agentSubnetId string = foundrySubnets.outputs.agentSubnetId

@description('Private Endpoint subnet resource ID')
output privateEndpointSubnetId string = foundrySubnets.outputs.privateEndpointSubnetId

@description('Foundry account name')
output foundryAccountName string = foundryAccount.outputs.accountName

@description('Foundry account resource ID')
output foundryAccountId string = foundryAccount.outputs.accountId

@description('Foundry project name')
output foundryProjectName string = foundryProject.outputs.projectName

@description('Foundry project resource ID')
output foundryProjectId string = foundryProject.outputs.projectId

@description('Foundry project principal ID for RBAC')
output foundryProjectPrincipalId string = foundryProject.outputs.projectPrincipalId

@description('Foundry project capability host name')
output foundryProjectCapabilityHostName string = addProjectCapabilityHost.outputs.projectCapHostName

@description('Foundry account capability host name')
output foundryAccountCapabilityHostName string = createAccountCapabilityHost ? addAccountCapabilityHost!.outputs.accountCapHostName : 'service-managed-existing'

@description('Foundry formatted workspace GUID')
output foundryProjectWorkspaceGuid string = formatProjectWorkspaceId.outputs.projectWorkspaceIdGuid

@description('AI Search resource ID')
output aiSearchId string = foundryDependencies.outputs.aiSearchId

@description('Storage resource ID')
output storageId string = foundryDependencies.outputs.storageId

@description('Cosmos DB resource ID')
output cosmosDbId string = foundryDependencies.outputs.cosmosDbId
