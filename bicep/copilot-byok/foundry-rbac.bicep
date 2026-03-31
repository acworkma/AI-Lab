// RBAC Assignment: APIM Managed Identity → Foundry Account
//
// Assigns the Cognitive Services OpenAI User role to the APIM
// managed identity so it can call the Foundry chat/completions API.
//
// Deploy to: rg-ai-foundry

targetScope = 'resourceGroup'

@description('Name of the existing Foundry account')
param foundryAccountName string

@description('Principal ID of the APIM managed identity')
param apimPrincipalId string

// Cognitive Services OpenAI User role definition ID
var cognitiveServicesOpenAIUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

// Reference existing Foundry account
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccountName
}

// Assign Cognitive Services OpenAI User role to APIM managed identity
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryAccount.id, apimPrincipalId, cognitiveServicesOpenAIUserRoleId)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRoleId)
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = roleAssignment.id
