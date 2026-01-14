// APIM Integration Subnet Module
// Creates subnet for Azure API Management Standard v2 VNet integration
// Purpose: Provide dedicated subnet with Microsoft.Web/serverFarms delegation for APIM

targetScope = 'resourceGroup'

// Parameters
@description('Name of the subnet')
param subnetName string = 'ApimIntegrationSubnet'

@description('Name of the parent VNet')
param vnetName string

@description('Subnet address prefix (minimum /27, recommended /26)')
param subnetPrefix string = '10.1.0.96/27'

@description('Resource ID of the NSG to associate with this subnet')
param nsgId string

// Reference the existing VNet
resource existingVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

// Create the APIM integration subnet
// Note: Standard v2 uses Microsoft.Web/serverFarms delegation (not Microsoft.ApiManagement)
resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: existingVnet
  name: subnetName
  properties: {
    addressPrefix: subnetPrefix
    networkSecurityGroup: {
      id: nsgId
    }
    // Required delegation for APIM Standard v2 VNet integration
    delegations: [
      {
        name: 'delegation-web-serverfarms'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
    // Service endpoints for Azure services accessed by APIM
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
      }
      {
        service: 'Microsoft.KeyVault'
      }
      {
        service: 'Microsoft.Sql'
      }
      {
        service: 'Microsoft.EventHub'
      }
    ]
    // Allow private endpoint network policies
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

// Outputs
@description('Resource ID of the APIM integration subnet')
output subnetId string = apimSubnet.id

@description('Name of the APIM integration subnet')
output subnetName string = apimSubnet.name

@description('Subnet address prefix')
output subnetPrefix string = apimSubnet.properties.addressPrefix
