// Power Platform Delegated Subnet Module
// Creates subnet delegated to Microsoft.PowerPlatform/enterprisePolicies
// Purpose: Enable Power Platform VNet support for Copilot Studio to reach private endpoints

targetScope = 'resourceGroup'

// Parameters
@description('Name of the subnet')
param subnetName string = 'PowerPlatformSubnet'

@description('Name of the parent VNet')
param vnetName string

@description('Subnet address prefix (minimum /27 for production, ~25-30 IPs needed)')
param subnetPrefix string = '10.1.1.0/27'

@description('Resource ID of the NSG to associate with this subnet (optional)')
param nsgId string = ''

// Reference the existing VNet
resource existingVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

// Create the Power Platform delegated subnet
// Containers injected at runtime get a NIC + private IP in this subnet
// They use the VNet's DNS (including private DNS zones) for name resolution
resource ppSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: existingVnet
  name: subnetName
  properties: {
    addressPrefix: subnetPrefix
    networkSecurityGroup: !empty(nsgId) ? {
      id: nsgId
    } : null
    // Required delegation for Power Platform VNet support
    delegations: [
      {
        name: 'delegation-powerplatform'
        properties: {
          serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
        }
      }
    ]
    // Allow private endpoint network policies so PP containers can reach PEs
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

// Outputs
@description('Resource ID of the Power Platform delegated subnet')
output subnetId string = ppSubnet.id

@description('Name of the Power Platform delegated subnet')
output subnetName string = ppSubnet.name

@description('Subnet address prefix')
output subnetPrefix string = ppSubnet.properties.addressPrefix
