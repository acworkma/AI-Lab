/*
  Azure DNS Private Resolver Module
  ==================================
  
  Purpose:
    Deploys a DNS Private Resolver with inbound endpoint to enable P2S VPN clients
    to resolve Azure Private DNS zones (privatelink.azurecr.io, privatelink.vaultcore.azure.net, etc.)
    to private endpoint IPs.
  
  Dependencies:
    - VNet must exist (provided via vnetId parameter)
    - VNet must have available address space for inbound subnet (e.g., 10.1.0.64/27)
    - Private DNS zones should be linked to the VNet for resolution to work
  
  Inputs:
    - resolverName: Name of the DNS resolver resource (default: 'dnsr-ai-shared')
    - vnetId: Resource ID of the VNet hosting the resolver
    - vnetName: Name of the VNet (for subnet resource naming)
    - inboundSubnetPrefix: CIDR for inbound endpoint subnet (default: '10.1.0.64/27')
    - location: Azure region
    - tags: Resource tags
  
  Outputs:
    - resolverId: DNS resolver resource ID
    - inboundEndpointId: Inbound endpoint resource ID
    - inboundEndpointIp: Private IP of inbound endpoint (for client DNS configuration)
  
  Usage:
    Configure P2S clients (WSL, laptops, etc.) to use the inboundEndpointIp as primary DNS server.
    Clients can then query private DNS zones and public domains via the resolver.
  
  Reference: https://learn.microsoft.com/azure/dns/dns-private-resolver-overview
*/

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

// Subnet dedicated to DNS resolver inbound endpoint
// IMPORTANT: Must have 'Microsoft.Network/dnsResolvers' delegation
// IP allocation: Endpoint auto-assigns IP from this subnet (typically .68 if /27 subnet)
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

// Inbound endpoint for DNS queries from P2S clients (WSL, VPN users)
// IP Configuration: Auto-assigned from inbound subnet (no manual IP specification)
// Reachable from: Any network with routing to the VNet (P2S via vHub, peered VNets)
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
