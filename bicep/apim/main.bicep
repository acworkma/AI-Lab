// Azure API Management Standard v2 Deployment
// Orchestrates APIM deployment with VNet integration to shared services subnet
// Purpose: Deploy APIM as API gateway with public frontend and private backend access

targetScope = 'subscription'

// Parameters
@description('Name of the API Management instance (must be globally unique)')
param apimName string = 'apim-ai-lab'

@description('Azure region for deployment')
param location string = 'eastus2'

@description('Email address of the API publisher (required)')
param publisherEmail string

@description('Name of the API publisher organization')
param publisherName string = 'AI-Lab'

@description('APIM pricing tier')
@allowed([
  'Standardv2'
])
param sku string = 'Standardv2'

@description('Number of scale units')
@minValue(1)
@maxValue(10)
param skuCapacity int = 1

@description('Name of the shared services VNet for integration')
param sharedServicesVnetName string = 'vnet-ai-shared'

@description('Resource group containing the shared services VNet')
param sharedServicesVnetResourceGroup string = 'rg-ai-core'

@description('CIDR prefix for APIM integration subnet')
param apimSubnetPrefix string = '10.1.0.96/27'

@description('VPN client address pool for NSG rules')
param vpnClientAddressPool string = '172.16.0.0/24'

@description('Enable VNet integration (recommended for backend access)')
param enableVnetIntegration bool = true

@description('Resource tags')
param tags object = {
  environment: 'dev'
  purpose: 'API Management Gateway'
  owner: 'platform-team'
}

// Variables
var apimResourceGroupName = 'rg-ai-apim'
var apimNsgName = 'nsg-apim-integration'
var apimSubnetName = 'ApimIntegrationSubnet'

// Resource Group for APIM
resource apimResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: apimResourceGroupName
  location: location
  tags: tags
}

// Deploy APIM NSG to shared services resource group (where VNet lives)
module apimNsg '../modules/apim-nsg.bicep' = if (enableVnetIntegration) {
  name: 'deploy-apim-nsg'
  scope: resourceGroup(sharedServicesVnetResourceGroup)
  params: {
    nsgName: apimNsgName
    location: location
    vpnClientAddressPool: vpnClientAddressPool
    apimSubnetPrefix: apimSubnetPrefix
    tags: tags
  }
}

// Deploy APIM subnet to shared services VNet
module apimSubnet '../modules/apim-subnet.bicep' = if (enableVnetIntegration) {
  name: 'deploy-apim-subnet'
  scope: resourceGroup(sharedServicesVnetResourceGroup)
  params: {
    subnetName: apimSubnetName
    vnetName: sharedServicesVnetName
    subnetPrefix: apimSubnetPrefix
    nsgId: apimNsg.outputs.nsgId
  }
}

// Deploy API Management instance
module apim '../modules/apim.bicep' = {
  name: 'deploy-apim'
  scope: apimResourceGroup
  params: {
    apimName: apimName
    location: location
    publisherEmail: publisherEmail
    publisherName: publisherName
    sku: sku
    skuCapacity: skuCapacity
    enableVnetIntegration: enableVnetIntegration
    subnetId: enableVnetIntegration ? apimSubnet.outputs.subnetId : ''
    tags: tags
  }
}

// Outputs
@description('Name of the deployed APIM instance')
output apimName string = apim.outputs.apimName

@description('Full resource ID of APIM')
output apimResourceId string = apim.outputs.apimResourceId

@description('Public gateway URL')
output gatewayUrl string = apim.outputs.gatewayUrl

@description('Developer portal URL')
output developerPortalUrl string = apim.outputs.developerPortalUrl

@description('Management API URL')
output managementUrl string = apim.outputs.managementUrl

@description('System-assigned managed identity principal ID')
output principalId string = apim.outputs.principalId

@description('Resource ID of the APIM integration subnet')
output apimSubnetId string = enableVnetIntegration && apimSubnet != null ? apimSubnet.outputs.subnetId : ''

@description('APIM resource group name')
output resourceGroupName string = apimResourceGroupName
