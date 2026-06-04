// Azure OpenAI Account + Model Deployment
// kind=OpenAI, S0, public access disabled, system-assigned managed identity

@description('Azure region')
param location string

@description('Account name')
param accountName string

@description('Model name')
param modelName string

@description('Model version')
param modelVersion string

@description('Deployment name')
param deploymentName string

@description('Deployment capacity (TPM in thousands)')
param deploymentCapacity int

@description('Tags')
param tags object

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: accountName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
  tags: tags
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: deploymentName
  sku: {
    name: 'Standard'
    capacity: deploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

output accountId string = account.id
output endpoint string = account.properties.endpoint
output principalId string = account.identity.principalId
