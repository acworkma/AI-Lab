// DNS Private Resolver Module
// Adds DNS resolver with inbound endpoint for private DNS resolution over vWAN/P2S
// Assumes VNet already exists and has available address space for dedicated inbound subnet

targetScope = 'resourceGroup'

@description('Azure region for deployment')
param location string

@description('Name of the DNS resolver')
param resolverName string = 'dnsr-ai-shared'

@description('Resource ID of the VNet to host the resolver inbound subnet')
param vnetId string

@description('Name of the VNet (used for resource naming)')
param vnetName string

@description('CIDR for the inbound endpoint subnet (must not overlap existing subnets)')
param inboundSubnetPrefix string = '10.1.0.64/27'

@description('Tags to apply to resources')
param tags object = {}

// Subnet dedicated to DNS resolver inbound endpoint with required delegation
resource dnsInboundSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  name: '${vnetName}/DnsInboundSubnet'
  properties: {
    addressPrefix: inboundSubnetPrefix
    delegations: [
      {
        name: 'dnsresolver'
        properties: {
          serviceName: 'Microsoft.Network/dnsResolvers'
        }
      }
    ]
  }
}

// DNS Resolver resource
resource dnsResolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: resolverName
  location: location
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
  tags: tags
  dependsOn: [
    dnsInboundSubnet
  ]
}

// Inbound endpoint for clients (P2S/WSL) to query
resource inboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  name: '${resolverName}/inbound-endpoint'
  location: location
  properties: {
    ipConfigurations: [
      {
        subnet: {
          id: dnsInboundSubnet.id
        }
      }
    ]
  }
  tags: tags
  dependsOn: [
    dnsResolver
  ]
}

@description('Resource ID of the DNS resolver')
output resolverId string = dnsResolver.id

@description('Resource ID of the inbound endpoint')
output inboundEndpointId string = inboundEndpoint.id

@description('Inbound endpoint IP address')
output inboundEndpointIp string = inboundEndpoint.properties.ipConfigurations[0].privateIpAddress
