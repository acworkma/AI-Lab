// Private Azure OpenAI Infrastructure
// Deploys:
// - Resource group
// - Azure OpenAI account (kind=OpenAI, S0) with public access disabled
// - gpt-4.1 model deployment (Standard)
// - Private endpoint in shared VNet
// - DNS zone group linking to existing privatelink.openai.azure.com zone

targetScope = 'subscription'

@description('Azure region for deployment')
param location string = 'eastus2'

@description('Resource group name')
param resourceGroupName string = 'rg-ai-aoai'

@description('Azure OpenAI account name')
param accountName string = 'oai-ai-lab'

@description('Model to deploy')
param modelName string = 'gpt-4.1'

@description('Model version')
param modelVersion string = '2025-04-14'

@description('Model deployment name')
param deploymentName string = 'gpt-4.1'

@description('Deployment capacity (tokens per minute in thousands)')
param deploymentCapacity int = 10

@description('Core resource group containing shared VNet and DNS zones')
param coreResourceGroupName string = 'rg-ai-core'

@description('Shared VNet name')
param vnetName string = 'vnet-ai-shared'

@description('Private endpoint subnet name')
param privateEndpointSubnetName string = 'PrivateEndpointSubnet'

@description('Tags')
param tags object = {
  project: 'ai-lab'
  component: 'aoai-private'
}

// Create resource group
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Deploy Azure OpenAI resources
module aoai 'modules/aoai-account.bicep' = {
  name: 'deploy-aoai-account'
  scope: rg
  params: {
    location: location
    accountName: accountName
    modelName: modelName
    modelVersion: modelVersion
    deploymentName: deploymentName
    deploymentCapacity: deploymentCapacity
    tags: tags
  }
}

// Deploy private endpoint
module pe 'modules/private-endpoint.bicep' = {
  name: 'deploy-aoai-private-endpoint'
  scope: rg
  params: {
    location: location
    accountName: accountName
    accountId: aoai.outputs.accountId
    vnetResourceGroupName: coreResourceGroupName
    vnetName: vnetName
    subnetName: privateEndpointSubnetName
    dnsZoneResourceGroupName: coreResourceGroupName
    tags: tags
  }
}

output accountName string = accountName
output accountEndpoint string = aoai.outputs.endpoint
output principalId string = aoai.outputs.principalId
