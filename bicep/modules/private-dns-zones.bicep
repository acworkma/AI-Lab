// Private DNS Zones Module
// Creates common Azure private DNS zones for private endpoint name resolution
// Purpose: Enable DNS resolution for private endpoints from VPN-connected clients

targetScope = 'resourceGroup'

// Parameters
@description('Azure region for deployment (metadata only, DNS zones are global)')
param location string

@description('Resource ID of the VNet to link DNS zones to')
param vnetId string

@description('Name of the VNet for DNS zone link naming')
param vnetName string

@description('Tags to apply to resources')
param tags object = {}

// Private DNS Zone for Azure Container Registry
resource acrDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
  tags: tags
  properties: {}
}

// Link ACR DNS zone to shared services VNet
resource acrDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: acrDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone for Azure Key Vault
resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
  properties: {}
}

// Link Key Vault DNS zone to shared services VNet
resource keyVaultDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone for Azure Blob Storage
resource blobDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
  tags: tags
  properties: {}
}

// Link Blob DNS zone to shared services VNet
resource blobDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: blobDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone for Azure File Storage
resource fileDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.file.core.windows.net'
  location: 'global'
  tags: tags
  properties: {}
}

// Link File DNS zone to shared services VNet
resource fileDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: fileDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone for Azure SQL Database
resource sqlDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.database.windows.net'
  location: 'global'
  tags: tags
  properties: {}
}

// Link SQL DNS zone to shared services VNet
resource sqlDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: sqlDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone for Azure AI Services (Foundry)
resource foundryAiServicesDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.services.ai.azure.com'
  location: 'global'
  tags: tags
  properties: {}
}

// Link AI Services DNS zone to shared services VNet
resource foundryAiServicesDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: foundryAiServicesDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone for Azure OpenAI
resource openAiDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.openai.azure.com'
  location: 'global'
  tags: tags
  properties: {}
}

// Link OpenAI DNS zone to shared services VNet
resource openAiDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: openAiDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone for Cognitive Services account endpoints
resource cognitiveServicesDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.cognitiveservices.azure.com'
  location: 'global'
  tags: tags
  properties: {}
}

// Link Cognitive Services DNS zone to shared services VNet
resource cognitiveServicesDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: cognitiveServicesDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone for Azure AI Search
resource searchDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.search.windows.net'
  location: 'global'
  tags: tags
  properties: {}
}

// Link Search DNS zone to shared services VNet
resource searchDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: searchDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Private DNS Zone for Azure Cosmos DB (SQL API)
resource cosmosDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
  tags: tags
  properties: {}
}

// Link Cosmos DNS zone to shared services VNet
resource cosmosDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: cosmosDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Outputs for use by downstream deployments
@description('Resource ID of the ACR private DNS zone')
output acrDnsZoneId string = acrDnsZone.id

@description('Name of the ACR private DNS zone')
output acrDnsZoneName string = acrDnsZone.name

@description('Resource ID of the Key Vault private DNS zone')
output keyVaultDnsZoneId string = keyVaultDnsZone.id

@description('Name of the Key Vault private DNS zone')
output keyVaultDnsZoneName string = keyVaultDnsZone.name

@description('Resource ID of the Blob Storage private DNS zone')
output blobDnsZoneId string = blobDnsZone.id

@description('Name of the Blob Storage private DNS zone')
output blobDnsZoneName string = blobDnsZone.name

@description('Resource ID of the File Storage private DNS zone')
output fileDnsZoneId string = fileDnsZone.id

@description('Name of the File Storage private DNS zone')
output fileDnsZoneName string = fileDnsZone.name

@description('Resource ID of the SQL Database private DNS zone')
output sqlDnsZoneId string = sqlDnsZone.id

@description('Name of the SQL Database private DNS zone')
output sqlDnsZoneName string = sqlDnsZone.name

@description('Resource ID of the AI Services private DNS zone')
output foundryAiServicesDnsZoneId string = foundryAiServicesDnsZone.id

@description('Name of the AI Services private DNS zone')
output foundryAiServicesDnsZoneName string = foundryAiServicesDnsZone.name

@description('Resource ID of the OpenAI private DNS zone')
output openAiDnsZoneId string = openAiDnsZone.id

@description('Name of the OpenAI private DNS zone')
output openAiDnsZoneName string = openAiDnsZone.name

@description('Resource ID of the Cognitive Services private DNS zone')
output cognitiveServicesDnsZoneId string = cognitiveServicesDnsZone.id

@description('Name of the Cognitive Services private DNS zone')
output cognitiveServicesDnsZoneName string = cognitiveServicesDnsZone.name

@description('Resource ID of the Search private DNS zone')
output searchDnsZoneId string = searchDnsZone.id

@description('Name of the Search private DNS zone')
output searchDnsZoneName string = searchDnsZone.name

@description('Resource ID of the Cosmos private DNS zone')
output cosmosDnsZoneId string = cosmosDnsZone.id

@description('Name of the Cosmos private DNS zone')
output cosmosDnsZoneName string = cosmosDnsZone.name
