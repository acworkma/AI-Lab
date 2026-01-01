// Point-to-Site VPN Gateway Module
// Creates P2S VPN Gateway attached to Virtual Hub for remote client connectivity
// Purpose: Enable secure remote access to Azure resources via VPN clients

targetScope = 'resourceGroup'

// Parameters
@description('Name of the P2S VPN Gateway resource')
param vpnGatewayName string

@description('Azure region for deployment')
param location string

@description('Resource ID of the Virtual Hub to attach the P2S VPN Gateway')
param virtualHubId string

@description('Resource ID of the VPN Server Configuration (defines auth methods and protocols)')
param vpnServerConfigurationId string

@description('VPN client address pool (CIDR notation) - addresses assigned to VPN clients')
param vpnClientAddressPool string = '172.16.0.0/24'

@description('P2S VPN Gateway scale units (1 unit = 500 Mbps, max 20 units)')
@minValue(1)
@maxValue(20)
param vpnGatewayScaleUnit int = 1

@description('Custom DNS servers for VPN clients (optional)')
param customDnsServers array = []

@description('Enable internet routing preference (default: use Azure backbone)')
param isRoutingPreferenceInternet bool = false

@description('Tags to apply to resources')
param tags object = {}

// Point-to-Site VPN Gateway for remote client connectivity
// Supports Microsoft Entra ID authentication, certificate-based auth, and RADIUS
resource p2sVpnGateway 'Microsoft.Network/p2sVpnGateways@2023-11-01' = {
  name: vpnGatewayName
  location: location
  tags: tags
  properties: {
    // Attach to Virtual Hub
    virtualHub: {
      id: virtualHubId
    }
    // Reference to VPN Server Configuration (auth methods, protocols, etc.)
    vpnServerConfiguration: {
      id: vpnServerConfigurationId
    }
    // P2S connection configuration
    p2SConnectionConfigurations: [
      {
        name: 'p2s-connection-config'
        properties: {
          // VPN client address pool - IP addresses assigned to connecting clients
          vpnClientAddressPool: {
            addressPrefixes: [
              vpnClientAddressPool
            ]
          }
          // Enable internet security to route client internet traffic through Azure
          enableInternetSecurity: false
        }
      }
    ]
    // Scale units determine aggregate throughput
    // 1 scale unit = 500 Mbps aggregate (can scale up to 20 units = 10 Gbps)
    vpnGatewayScaleUnit: vpnGatewayScaleUnit
    // Custom DNS servers for VPN clients (optional)
    customDnsServers: customDnsServers
    // Routing preference - use Azure backbone (false) or internet routing (true)
    isRoutingPreferenceInternet: isRoutingPreferenceInternet
  }
}

// Outputs for use by main template and validation scripts
@description('Resource ID of the P2S VPN Gateway')
output vpnGatewayId string = p2sVpnGateway.id

@description('Name of the P2S VPN Gateway')
output vpnGatewayName string = p2sVpnGateway.name

@description('P2S VPN Gateway scale units (aggregate throughput capacity)')
output vpnGatewayScaleUnit int = p2sVpnGateway.properties.vpnGatewayScaleUnit

@description('VPN client address pool')
output vpnClientAddressPool string = vpnClientAddressPool

@description('P2S VPN Gateway provisioning state')
output provisioningState string = p2sVpnGateway.properties.provisioningState
