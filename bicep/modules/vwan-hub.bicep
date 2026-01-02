// Virtual WAN Hub Module
// Creates Azure Virtual WAN and Virtual Hub for hub-spoke topology
// Purpose: Central networking hub for all AI lab spoke connections

targetScope = 'resourceGroup'

// Parameters
@description('Name of the Virtual WAN resource')
param vwanName string

@description('Name of the Virtual Hub resource')
param vhubName string

@description('Azure region for deployment')
param location string

@description('Virtual Hub address prefix (CIDR notation)')
@minLength(9)
@maxLength(18)
param vhubAddressPrefix string = '10.0.0.0/16'

@description('Tags to apply to resources')
param tags object = {}

// Virtual WAN - Standard SKU required for VPN Gateway and spoke connections
// Decision rationale: Standard tier supports site-to-site VPN Gateway needed for Global Secure Access
// See research.md: Azure Virtual WAN Hub Architecture with Global Secure Access
resource virtualWan 'Microsoft.Network/virtualWans@2023-11-01' = {
  name: vwanName
  location: location
  tags: tags
  properties: {
    // Standard type required for VPN Gateway support and spoke virtual network connections
    type: 'Standard'
    // Enable branch-to-branch traffic for future spoke-to-spoke communication
    allowBranchToBranchTraffic: true
    // Encryption must be enabled for VPN connections (security requirement)
    disableVpnEncryption: false
  }
}

// Virtual Hub - Regional hub instance within the Virtual WAN
// Address space: 10.0.0.0/16 provides 65,536 addresses for hub services
// See data-model.md: Virtual Hub entity definition
resource virtualHub 'Microsoft.Network/virtualHubs@2023-11-01' = {
  name: vhubName
  location: location
  tags: tags
  properties: {
    // Reference to parent Virtual WAN
    virtualWan: {
      id: virtualWan.id
    }
    // Hub address space - must not overlap with spoke VNets
    // Recommended spoke ranges: 10.1.0.0/16, 10.2.0.0/16, etc.
    addressPrefix: vhubAddressPrefix
    // Standard SKU matches Virtual WAN tier
    sku: 'Standard'
  }
}

// Outputs for use by main template and validation scripts
@description('Resource ID of the Virtual WAN')
output vwanId string = virtualWan.id

@description('Name of the Virtual WAN')
output vwanName string = virtualWan.name

@description('Resource ID of the Virtual Hub')
output vhubId string = virtualHub.id

@description('Name of the Virtual Hub')
output vhubName string = virtualHub.name

@description('Virtual Hub address prefix')
output vhubAddressPrefix string = virtualHub.properties.addressPrefix

@description('Virtual Hub routing state (Provisioned when ready for connections)')
output vhubRoutingState string = virtualHub.properties.routingState
