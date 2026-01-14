// APIM Integration Subnet NSG Module
// Network Security Group for Azure API Management Standard v2 VNet integration
// Purpose: Control inbound/outbound traffic for APIM integration subnet

targetScope = 'resourceGroup'

// Parameters
@description('Name of the NSG')
param nsgName string = 'nsg-apim-integration'

@description('Azure region for deployment')
param location string

@description('VPN client address pool for inbound rules')
param vpnClientAddressPool string = '172.16.0.0/24'

@description('APIM subnet address prefix')
param apimSubnetPrefix string = '10.1.0.96/27'

@description('Tags to apply to resources')
param tags object = {}

// Network Security Group for APIM integration subnet
// Standard v2 uses VNet integration (not injection) which has different requirements
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      // Inbound Rules
      {
        name: 'AllowVpnClientInbound'
        properties: {
          description: 'Allow inbound traffic from VPN clients to developer portal/management'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '443'
            '3443'
          ]
          sourceAddressPrefix: vpnClientAddressPool
          destinationAddressPrefix: apimSubnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowVnetInbound'
        properties: {
          description: 'Allow inbound traffic from VNet (hub-spoke communication)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          description: 'Allow Azure Load Balancer health probes'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
      // Outbound Rules
      {
        name: 'AllowStorageOutbound'
        properties: {
          description: 'Allow outbound to Azure Storage for APIM dependencies'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowKeyVaultOutbound'
        properties: {
          description: 'Allow outbound to Azure Key Vault for secrets/certificates'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureKeyVault'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowSqlOutbound'
        properties: {
          description: 'Allow outbound to Azure SQL for APIM configuration store'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowEventHubOutbound'
        properties: {
          description: 'Allow outbound to Event Hub for logging'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '5671'
            '5672'
            '443'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'EventHub'
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowVnetOutbound'
        properties: {
          description: 'Allow outbound to VNet for backend connectivity'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 140
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowAzureMonitorOutbound'
        properties: {
          description: 'Allow outbound to Azure Monitor for diagnostics'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 150
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowAzureActiveDirectoryOutbound'
        properties: {
          description: 'Allow outbound to Azure AD for authentication'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureActiveDirectory'
          access: 'Allow'
          priority: 160
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyInternetOutbound'
        properties: {
          description: 'Deny direct internet access (use service tags for Azure services)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
          access: 'Deny'
          priority: 4096
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Outputs
@description('Resource ID of the NSG')
output nsgId string = apimNsg.id

@description('Name of the NSG')
output nsgName string = apimNsg.name
