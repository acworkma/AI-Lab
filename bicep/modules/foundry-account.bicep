targetScope = 'resourceGroup'

@description('Name for the Foundry account')
param accountName string

@description('Deployment location')
param location string

@description('Model deployment name')
param modelName string = 'gpt-4.1'

@description('Model provider format')
param modelFormat string = 'OpenAI'

@description('Model version')
param modelVersion string = '2025-04-14'

@description('Model SKU')
param modelSkuName string = 'GlobalStandard'

@description('Model capacity (TPM units)')
param modelCapacity int = 30

@description('Delegated subnet ID for Foundry network injection')
param agentSubnetId string

@description('Enable network injection for Agent scenario')
param enableNetworkInjection bool = true

@description('Resource tags')
param tags object = {}

#disable-next-line BCP036
resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: accountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: []
      bypass: 'AzureServices'
    }
    networkInjections: enableNetworkInjection ? [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetId
        useMicrosoftManagedNetwork: false
      }
    ] : null
  }
}

#disable-next-line BCP081
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: account
  name: modelName
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      name: modelName
      format: modelFormat
      version: modelVersion
    }
  }
}

output accountName string = account.name
output accountId string = account.id
output accountEndpoint string = account.properties.endpoint
output accountPrincipalId string = account.identity.principalId
