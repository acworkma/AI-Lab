// Foundry Model Deployment for GitHub Copilot BYOK
//
// Deploys gpt-5.2 to the EXISTING Foundry account.
// Does NOT modify the Foundry account or existing model deployments.
//
// Deploy to: rg-ai-foundry

targetScope = 'resourceGroup'

@description('Name of the existing Foundry account')
param foundryAccountName string

@description('Model deployment name')
param modelName string = 'gpt-5.2'

@description('Model provider format')
param modelFormat string = 'OpenAI'

@description('Model version')
param modelVersion string = '2025-12-11'

@description('Model SKU name')
param modelSkuName string = 'GlobalStandard'

@description('Model capacity in TPM units')
param modelCapacity int = 50

// Reference existing Foundry account — do NOT create or modify
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccountName
}

// Deploy codex model as a child resource of the existing account
#disable-next-line BCP081
resource codexModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: foundryAccount
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

output modelDeploymentName string = codexModelDeployment.name
output foundryAccountName string = foundryAccount.name
output foundryEndpoint string = foundryAccount.properties.endpoint
