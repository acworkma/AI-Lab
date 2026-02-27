targetScope = 'resourceGroup'

@description('Foundry account name')
param accountName string

@description('Account capability host name')
param accountCapHost string = 'caphostaccount'

@description('Customer subnet resource ID for account capability host')
param customerSubnetId string

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource accountCapabilityHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview' = {
  parent: account
  name: accountCapHost
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    #disable-next-line BCP037
    customerSubnet: customerSubnetId
  }
}

output accountCapHostName string = accountCapabilityHost.name
