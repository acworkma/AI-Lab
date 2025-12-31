// VPN Gateway Module - Site-to-Site VPN for Global Secure Access
// Creates VPN Gateway attached to Virtual Hub for Microsoft Entra Global Secure Access integration
// Purpose: Enable Security Service Edge (SSE) capabilities via site-to-site VPN

targetScope = 'resourceGroup'

// Parameters
@description('Name of the VPN Gateway resource')
param vpnGatewayName string

@description('Azure region for deployment')
param location string

@description('Resource ID of the Virtual Hub to attach the VPN Gateway')
param virtualHubId string

@description('VPN Gateway scale units (1 unit = 500 Mbps, max 20 units)')
@minValue(1)
@maxValue(20)
param vpnGatewayScaleUnit int = 1

@description('Enable BGP for dynamic routing (required for Global Secure Access)')
param enableBgp bool = true

@description('BGP Autonomous System Number (default Azure ASN)')
@minValue(65000)
@maxValue(65535)
param bgpAsn int = 65515

@description('Tags to apply to resources')
param tags object = {}

// VPN Gateway - Site-to-Site configuration for Global Secure Access integration
// CRITICAL: Must be site-to-site (not point-to-site) for Global Secure Access
// See research.md: Decision to use site-to-site VPN Gateway for Microsoft Entra Global Secure Access
resource vpnGateway 'Microsoft.Network/vpnGateways@2023-11-01' = {
  name: vpnGatewayName
  location: location
  tags: tags
  properties: {
    // Attach to Virtual Hub
    virtualHub: {
      id: virtualHubId
    }
    // Scale units determine aggregate throughput
    // 1 scale unit = 500 Mbps aggregate (can scale up to 20 units = 10 Gbps)
    // Start with 1 unit for lab environment, scale as needed
    vpnGatewayScaleUnit: vpnGatewayScaleUnit
    // BGP Configuration - REQUIRED for Global Secure Access integration
    // Enables dynamic route propagation between Azure and Microsoft Entra SSE
    bgpSettings: enableBgp ? {
      // Azure default ASN for hub VPN gateways
      asn: bgpAsn
      // Peer weight for route preference (0 = default)
      peerWeight: 0
    } : null
    // NAT settings - not required for Global Secure Access
    enableBgpRouteTranslationForNat: false
    // Routing preference - use default Azure backbone (not internet)
    isRoutingPreferenceInternet: false
  }
}

// Outputs for use by main template, validation scripts, and Global Secure Access configuration
@description('Resource ID of the VPN Gateway')
output vpnGatewayId string = vpnGateway.id

@description('Name of the VPN Gateway')
output vpnGatewayName string = vpnGateway.name

@description('VPN Gateway BGP settings for Global Secure Access integration')
output vpnGatewayBgpSettings object = enableBgp ? {
  asn: vpnGateway.properties.bgpSettings.asn
  bgpPeeringAddress: vpnGateway.properties.bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0]
  peerWeight: vpnGateway.properties.bgpSettings.peerWeight
} : {}

@description('VPN Gateway scale units (aggregate throughput capacity)')
output vpnGatewayScaleUnit int = vpnGateway.properties.vpnGatewayScaleUnit

@description('VPN Gateway provisioning state')
output provisioningState string = vpnGateway.properties.provisioningState
