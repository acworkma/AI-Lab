// Main Bicep Template - Core Azure vWAN Infrastructure with P2S VPN
// Orchestrates deployment of resource group, Virtual WAN hub, Point-to-Site VPN Gateway, and Key Vault
// Purpose: Foundation hub infrastructure for AI lab spoke connections with secure remote access

targetScope = 'subscription'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Azure region for all resources')
param location string = 'eastus2'

@description('Environment tag (dev, test, or prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Owner identifier for resource tagging')
@minLength(1)
@maxLength(100)
param owner string

@description('Resource group name (fixed per constitution)')
param resourceGroupName string = 'rg-ai-core'

@description('Virtual WAN name')
param vwanName string = 'vwan-ai-hub'

@description('Virtual Hub name')
param vhubName string = 'hub-ai-eastus2'

@description('Virtual Hub address prefix (CIDR notation, must not overlap with spoke VNets)')
param vhubAddressPrefix string = '10.0.0.0/16'

@description('VPN Gateway name')
param vpnGatewayName string = 'vpngw-ai-hub'

@description('VPN Gateway scale units (1 unit = 500 Mbps, max 20)')
@minValue(1)
@maxValue(20)
param vpnGatewayScaleUnit int = 1

@description('VPN Server Configuration name')
param vpnServerConfigName string = 'vpnconfig-ai-hub'

@description('VPN client address pool (CIDR notation)')
param vpnClientAddressPool string = '172.16.0.0/24'

@description('Microsoft Entra ID Tenant ID for VPN authentication')
param aadTenantId string

@description('Azure VPN Client Application ID (Microsoft Entra ID)')
param aadAudience string = '41b23e61-6c1e-4545-b367-cd054e0ed4b4'

@description('Microsoft Entra ID Issuer URL')
param aadIssuer string

@description('Key Vault name (must be globally unique, 3-24 characters)')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('Key Vault SKU (standard or premium)')
@allowed([
  'standard'
  'premium'
])
param keyVaultSku string = 'standard'

@description('Enable purge protection for Key Vault (recommended for production)')
param enablePurgeProtection bool = false

@description('Deployment method for tagging (manual or automation)')
param deployedBy string = 'manual'

@description('Additional custom tags')
param tags object = {}

@description('Deployment timestamp (auto-generated)')
param deploymentTimestamp string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

// ============================================================================
// VARIABLES
// ============================================================================

// Merged tags combining constitutional requirements and custom tags
// See constitution.md: Principle 3 - Resource Organization - Tagging Requirements
var allTags = union({
  environment: environment
  purpose: 'Core hub infrastructure for AI labs'
  owner: owner
  deployedBy: deployedBy
  deployedDate: deploymentTimestamp
}, tags)

// ============================================================================
// RESOURCE GROUP
// ============================================================================

// Resource Group - Container for all core infrastructure
// See data-model.md: Resource Group entity definition
module resourceGroup 'modules/resource-group.bicep' = {
  name: 'deploy-rg-ai-core'
  params: {
    name: resourceGroupName
    location: location
    environment: environment
    purpose: 'Core hub infrastructure for AI labs'
    owner: owner
    deployedBy: deployedBy
    deploymentTimestamp: deploymentTimestamp
    additionalTags: tags
  }
}

// ============================================================================
// VIRTUAL WAN AND HUB
// ============================================================================

// Virtual WAN Hub - Central networking hub for spoke connections
// Deployment time: ~5-7 minutes
// See research.md: Azure Virtual WAN Hub Architecture with Global Secure Access
module vwanHub 'modules/vwan-hub.bicep' = {
  name: 'deploy-vwan-hub'
  scope: az.resourceGroup(resourceGroupName)
  dependsOn: [
    resourceGroup
  ]
  params: {
    vwanName: vwanName
    vhubName: vhubName
    location: location
    vhubAddressPrefix: vhubAddressPrefix
    tags: allTags
  }
}

// ============================================================================
// VPN SERVER CONFIGURATION
// ============================================================================

// VPN Server Configuration - Authentication and protocol settings for P2S VPN
// Deployment time: ~1 minute
module vpnServerConfig 'modules/vpn-server-configuration.bicep' = {
  name: 'deploy-vpn-server-config'
  scope: az.resourceGroup(resourceGroupName)
  dependsOn: [
    resourceGroup
  ]
  params: {
    vpnServerConfigName: vpnServerConfigName
    location: location
    vpnAuthenticationTypes: ['AAD']
    vpnProtocols: ['OpenVPN']
    aadTenant: 'https://login.microsoftonline.com/${aadTenantId}/'
    aadAudience: aadAudience
    aadIssuer: aadIssuer
    tags: allTags
  }
}

// ============================================================================
// VPN GATEWAY
// ============================================================================

// Point-to-Site VPN Gateway - Secure remote client access
// Deployment time: ~15-20 minutes (longest resource)
module vpnGateway 'modules/vpn-gateway.bicep' = {
  name: 'deploy-vpn-gateway'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    vpnGatewayName: vpnGatewayName
    location: location
    virtualHubId: vwanHub.outputs.vhubId
    vpnServerConfigurationId: vpnServerConfig.outputs.vpnServerConfigId
    vpnClientAddressPool: vpnClientAddressPool
    vpnGatewayScaleUnit: vpnGatewayScaleUnit
    tags: allTags
  }
}

// ============================================================================
// KEY VAULT
// ============================================================================

// Key Vault - Centralized secrets management for all labs
// Deployment time: ~1 minute
// Can deploy in parallel with Virtual WAN (no dependency)
// See research.md: Azure Key Vault Best Practices - RBAC authorization model
module keyVault 'modules/key-vault.bicep' = {
  name: 'deploy-key-vault'
  scope: az.resourceGroup(resourceGroupName)
  dependsOn: [
    resourceGroup
  ]
  params: {
    keyVaultName: keyVaultName
    location: location
    keyVaultSku: keyVaultSku
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: enablePurgeProtection
    networkAclsDefaultAction: 'Allow'
    tags: allTags
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

// Resource Group Outputs
@description('Resource ID of the resource group')
output resourceGroupId string = resourceGroup.outputs.id

@description('Name of the resource group')
output resourceGroupName string = resourceGroup.outputs.name

@description('Location of the resource group')
output resourceGroupLocation string = resourceGroup.outputs.location

// Virtual WAN Outputs
@description('Resource ID of the Virtual WAN')
output vwanId string = vwanHub.outputs.vwanId

@description('Name of the Virtual WAN')
output vwanName string = vwanHub.outputs.vwanName

// Virtual Hub Outputs
@description('Resource ID of the Virtual Hub')
output vhubId string = vwanHub.outputs.vhubId

@description('Name of the Virtual Hub')
output vhubName string = vwanHub.outputs.vhubName

@description('Virtual Hub address prefix')
output vhubAddressPrefix string = vwanHub.outputs.vhubAddressPrefix

@description('Virtual Hub routing state (Provisioned when ready for spoke connections)')
output vhubRoutingState string = vwanHub.outputs.vhubRoutingState

// VPN Server Configuration Outputs
@description('Resource ID of the VPN Server Configuration')
output vpnServerConfigId string = vpnServerConfig.outputs.vpnServerConfigId

@description('Name of the VPN Server Configuration')
output vpnServerConfigName string = vpnServerConfig.outputs.vpnServerConfigName

// VPN Gateway Outputs
@description('Resource ID of the P2S VPN Gateway')
output vpnGatewayId string = vpnGateway.outputs.vpnGatewayId

@description('Name of the P2S VPN Gateway')
output vpnGatewayName string = vpnGateway.outputs.vpnGatewayName

@description('VPN client address pool')
output vpnClientAddressPool string = vpnGateway.outputs.vpnClientAddressPool

@description('VPN Gateway scale units')
output vpnGatewayScaleUnit int = vpnGateway.outputs.vpnGatewayScaleUnit

// Key Vault Outputs
@description('Resource ID of the Key Vault')
output keyVaultId string = keyVault.outputs.keyVaultId

@description('Name of the Key Vault')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('Key Vault URI for secret references in parameter files')
output keyVaultUri string = keyVault.outputs.keyVaultUri

// Deployment Metadata
@description('All applied tags')
output appliedTags object = allTags

@description('Deployment timestamp')
output deploymentTimestamp string = deploymentTimestamp
