// VPN Server Configuration Module
// Defines authentication and protocol settings for Point-to-Site VPN
// Purpose: Configure Microsoft Entra ID authentication for P2S VPN clients

targetScope = 'resourceGroup'

// Parameters
@description('Name of the VPN Server Configuration resource')
param vpnServerConfigName string

@description('Azure region for deployment')
param location string

@description('VPN authentication types (Certificate, Radius, or AAD)')
param vpnAuthenticationTypes array = [
  'AAD'
]

@description('VPN protocols to enable (IkeV2, OpenVPN, or both)')
param vpnProtocols array = [
  'OpenVPN'
]

@description('Microsoft Entra ID Tenant URL for authentication (e.g., https://login.microsoftonline.com/{tenant-id}/)')
param aadTenant string

@description('Microsoft Entra ID Audience (Application ID)')
param aadAudience string

@description('Microsoft Entra ID Issuer URL')
param aadIssuer string

@description('Tags to apply to resources')
param tags object = {}

// VPN Server Configuration - Defines how clients authenticate and connect
// Supports Microsoft Entra ID, certificate-based, and RADIUS authentication
resource vpnServerConfig 'Microsoft.Network/vpnServerConfigurations@2023-11-01' = {
  name: vpnServerConfigName
  location: location
  tags: tags
  properties: {
    // Authentication types - Microsoft Entra ID, Certificate, or RADIUS
    vpnAuthenticationTypes: vpnAuthenticationTypes
    // VPN protocols - IkeV2 and/or OpenVPN
    vpnProtocols: vpnProtocols
    // Microsoft Entra ID authentication parameters (if using AAD auth)
    aadAuthenticationParameters: contains(vpnAuthenticationTypes, 'AAD') ? {
      aadTenant: aadTenant
      aadAudience: aadAudience
      aadIssuer: aadIssuer
    } : null
  }
}

// Outputs
@description('Resource ID of the VPN Server Configuration')
output vpnServerConfigId string = vpnServerConfig.id

@description('Name of the VPN Server Configuration')
output vpnServerConfigName string = vpnServerConfig.name

@description('VPN authentication types configured')
output vpnAuthenticationTypes array = vpnServerConfig.properties.vpnAuthenticationTypes

@description('VPN protocols enabled')
output vpnProtocols array = vpnServerConfig.properties.vpnProtocols

@description('VPN Server Configuration provisioning state')
output provisioningState string = vpnServerConfig.properties.provisioningState
