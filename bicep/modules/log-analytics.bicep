// Log Analytics Workspace Module
// Creates a Log Analytics workspace for diagnostics and monitoring
// Purpose: Centralized log collection for Azure Container Apps and other services

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Name of the Log Analytics workspace')
@minLength(4)
@maxLength(63)
param workspaceName string

@description('Azure region for deployment')
param location string

@description('Retention period in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('SKU for the workspace')
@allowed([
  'PerGB2018'
  'Free'
  'Standalone'
])
param sku string = 'PerGB2018'

@description('Resource tags')
param tags object = {}

// ============================================================================
// LOG ANALYTICS WORKSPACE
// ============================================================================

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Log Analytics workspace resource ID')
output workspaceId string = workspace.id

@description('Log Analytics workspace name')
output workspaceName string = workspace.name

@description('Log Analytics workspace customer ID (for agent configuration)')
output customerId string = workspace.properties.customerId
