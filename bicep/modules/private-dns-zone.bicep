// Private DNS Zone Module (single zone)
// Creates a single private DNS zone and links it to a VNet
// Purpose: Reusable module for creating private DNS zones for private endpoint resolution

targetScope = 'resourceGroup'

@description('Name of the private DNS zone (e.g., privatelink.azure-api.net)')
param zoneName string

@description('Resource ID of the VNet to link the DNS zone to')
param vnetId string

@description('Tags to apply to resources')
param tags object = {}

// Private DNS Zone
resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: zoneName
  location: 'global'
  tags: tags
  properties: {}
}

// Link DNS zone to VNet for automatic resolution
resource dnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dnsZone
  name: '${split(vnetId, '/')[8]}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Outputs
@description('Resource ID of the private DNS zone')
output dnsZoneId string = dnsZone.id

@description('Name of the private DNS zone')
output dnsZoneName string = dnsZone.name
