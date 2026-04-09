// Azure API Management Standard v2 — Private Deployment
// Orchestrates APIM deployment with inbound private endpoint and Power Platform subnet
// Purpose: Fully private API gateway — no public network exposure
//
// Deploys:
// - APIM NSG + integration subnet (outbound VNet integration)
// - APIM Standard v2 with inbound private endpoint
// - privatelink.azure-api.net DNS zone
// - Power Platform delegated subnet (for Copilot Studio VNet support)

targetScope = 'subscription'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Name of the API Management instance (must be globally unique)')
param apimName string = 'apim-ai-lab-private'

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

@description('Name of the shared services VNet')
param sharedServicesVnetName string = 'vnet-ai-shared'

@description('Resource group containing the shared services VNet')
param sharedServicesVnetResourceGroup string = 'rg-ai-core'

@description('CIDR prefix for APIM integration subnet (outbound)')
param apimSubnetPrefix string = '10.1.0.128/27'

@description('CIDR prefix for Power Platform delegated subnet')
param ppSubnetPrefix string = '10.1.1.0/27'

@description('Name of the private endpoint subnet (existing)')
param privateEndpointSubnetName string = 'PrivateEndpointSubnet'

@description('VPN client address pool for NSG rules')
param vpnClientAddressPool string = '172.16.0.0/24'

@description('Enable VNet integration for outbound backend access')
param enableVnetIntegration bool = true

@description('Resource tags')
param tags object = {
  environment: 'dev'
  purpose: 'Private API Management Gateway'
  owner: 'platform-team'
}

// ============================================================================
// VARIABLES
// ============================================================================

var apimResourceGroupName = 'rg-ai-apim-private'
var apimNsgName = 'nsg-apim-private-integration'
var apimSubnetName = 'ApimPrivateIntegrationSubnet'
var ppSubnetName = 'PowerPlatformSubnet'
var apimDnsZoneName = 'privatelink.azure-api.net'

// ============================================================================
// RESOURCE GROUP
// ============================================================================

resource apimResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: apimResourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// NETWORKING — NSG, SUBNETS, DNS
// ============================================================================

// APIM integration subnet NSG (same pattern as public variant)
module apimNsg '../modules/apim-nsg.bicep' = if (enableVnetIntegration) {
  name: 'deploy-apim-private-nsg'
  scope: resourceGroup(sharedServicesVnetResourceGroup)
  params: {
    nsgName: apimNsgName
    location: location
    vpnClientAddressPool: vpnClientAddressPool
    apimSubnetPrefix: apimSubnetPrefix
    tags: tags
  }
}

// APIM integration subnet (outbound — for reaching private backends)
module apimSubnet '../modules/apim-subnet.bicep' = if (enableVnetIntegration) {
  name: 'deploy-apim-private-subnet'
  scope: resourceGroup(sharedServicesVnetResourceGroup)
  params: {
    subnetName: apimSubnetName
    vnetName: sharedServicesVnetName
    subnetPrefix: apimSubnetPrefix
    nsgId: apimNsg.outputs.nsgId
  }
}

// Power Platform delegated subnet (for Copilot Studio VNet support)
module ppSubnet '../modules/pp-subnet.bicep' = {
  name: 'deploy-pp-subnet'
  scope: resourceGroup(sharedServicesVnetResourceGroup)
  params: {
    subnetName: ppSubnetName
    vnetName: sharedServicesVnetName
    subnetPrefix: ppSubnetPrefix
  }
}

// Private DNS zone for APIM private endpoint
// Creates: privatelink.azure-api.net
module apimDnsZone '../modules/private-dns-zone.bicep' = {
  name: 'deploy-apim-dns-zone'
  scope: resourceGroup(sharedServicesVnetResourceGroup)
  params: {
    zoneName: apimDnsZoneName
    vnetId: resourceId(sharedServicesVnetResourceGroup, 'Microsoft.Network/virtualNetworks', sharedServicesVnetName)
    tags: tags
  }
}

// ============================================================================
// APIM INSTANCE WITH PRIVATE ENDPOINT
// ============================================================================

// Reference existing PE subnet
resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: '${sharedServicesVnetName}/${privateEndpointSubnetName}'
  scope: resourceGroup(sharedServicesVnetResourceGroup)
}

// Deploy private APIM with inbound PE and public access disabled
module apim '../modules/apim-private.bicep' = {
  name: 'deploy-apim-private'
  scope: apimResourceGroup
  params: {
    apimName: apimName
    location: location
    publisherEmail: publisherEmail
    publisherName: publisherName
    sku: sku
    skuCapacity: skuCapacity
    enableVnetIntegration: enableVnetIntegration
    vnetIntegrationSubnetId: enableVnetIntegration ? apimSubnet.outputs.subnetId : ''
    privateEndpointSubnetId: peSubnet.id
    privateDnsZoneId: apimDnsZone.outputs.dnsZoneId
    tags: tags
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Name of the deployed APIM instance')
output apimName string = apim.outputs.apimName

@description('Full resource ID of APIM')
output apimResourceId string = apim.outputs.apimResourceId

@description('Gateway URL (private — resolves via privatelink DNS)')
output gatewayUrl string = apim.outputs.gatewayUrl

@description('System-assigned managed identity principal ID')
output principalId string = apim.outputs.principalId

@description('APIM private endpoint IP address')
output privateEndpointIp string = apim.outputs.privateEndpointIp

@description('Power Platform subnet ID (for enterprise policy setup)')
output ppSubnetId string = ppSubnet.outputs.subnetId

@description('APIM resource group name')
output resourceGroupName string = apimResourceGroupName
