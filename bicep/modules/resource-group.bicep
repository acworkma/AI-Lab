// Resource Group Module
// Creates an Azure resource group with standardized tagging
// Per constitution: All resources must be tagged with environment, purpose, owner

@description('Name of the resource group')
param name string

@description('Azure region for the resource group')
param location string

@description('Environment tag (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string

@description('Purpose of the resource group')
param purpose string

@description('Owner of the resource group (team or individual)')
param owner string

@description('How deployment was triggered')
@allowed([
  'manual'
  'automation'
])
param deployedBy string = 'manual'

@description('Additional custom tags')
param additionalTags object = {}

@description('Deployment timestamp (auto-generated)')
param deploymentTimestamp string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

// Merge required tags with additional tags
var tags = union({
  environment: environment
  purpose: purpose
  owner: owner
  deployedBy: deployedBy
  deployedDate: deploymentTimestamp
}, additionalTags)

// Resource group
targetScope = 'subscription'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: name
  location: location
  tags: tags
}

// Outputs
@description('Resource group name')
output name string = resourceGroup.name

@description('Resource group ID')
output id string = resourceGroup.id

@description('Resource group location')
output location string = resourceGroup.location

@description('Resource group tags')
output tags object = resourceGroup.tags
