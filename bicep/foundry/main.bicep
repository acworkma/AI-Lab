// Private Foundry Infrastructure Orchestration (Phase 1)
// Provisions dedicated Foundry networking primitives in shared VNet:
// - Delegated Agent subnet (Microsoft.App/environments)
// - Dedicated Private Endpoint subnet

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
param privateEndpointSubnetName string = 'snet-foundry-pe'

@description('Private Endpoint subnet address prefix')
param privateEndpointSubnetPrefix string = '10.1.0.96/27'

@description('Additional custom tags')
param tags object = {}

var allTags = union({
  environment: environment
  purpose: 'private-foundry-infrastructure'
  owner: owner
  deployedBy: 'bicep'
  project: '012-private-foundry'
}, tags)

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

@description('Foundry resource group name')
output resourceGroupName string = foundryResourceGroup.name

@description('Shared VNet resource ID')
output sharedVnetId string = sharedVnet.id

@description('Delegated Agent subnet resource ID')
output agentSubnetId string = foundrySubnets.outputs.agentSubnetId

@description('Private Endpoint subnet resource ID')
output privateEndpointSubnetId string = foundrySubnets.outputs.privateEndpointSubnetId
