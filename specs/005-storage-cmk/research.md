# Research: Storage Account with Customer Managed Keys

**Feature**: 005-storage-cmk  
**Phase**: 0 - Research & Decision Log  
**Date**: 2025-01-22

## Overview

Research findings for implementing Azure Storage Account with Customer-Managed Keys (CMK) on private endpoints. This document resolves all "NEEDS CLARIFICATION" items from Technical Context and documents key decisions.

## Research Tasks Completed

1. **Azure Storage CMK Architecture Best Practices**
2. **Private Endpoint DNS Integration Patterns**
3. **Managed Identity Key Vault Access Configuration**
4. **Bicep Patterns from Existing Modules**
5. **Storage Account Network Security**

---

## Decision 1: Storage Account SKU and Tier

### Decision
Use **Standard_LRS** (Standard locally-redundant storage) for lab environment

### Rationale
- **Lab Context**: This is a learning/demonstration environment, not production
- **Cost Optimization**: LRS is most cost-effective for non-critical data
- **Specification Alignment**: User confirmed Standard_LRS in spec clarifications
- **CMK Compatibility**: All Standard tier SKUs support customer-managed keys
- **Sufficient for Purpose**: Single-region redundancy adequate for lab scenarios

### Alternatives Considered
- **Standard_ZRS** (Zone-redundant): Higher availability but unnecessary cost for lab
- **Standard_GRS** (Geo-redundant): Cross-region redundancy overkill for temporary lab data
- **Premium_LRS**: Better performance but premium cost unjustified for demos

### References
- [Azure Storage redundancy documentation](https://learn.microsoft.com/en-us/azure/storage/common/storage-redundancy)
- [Customer-managed keys support matrix](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-overview#supported-azure-storage-services)

---

## Decision 2: Private Endpoint Scope

### Decision
Deploy **blob storage private endpoint only** (not file/table/queue)

### Rationale
- **User Specification**: Clarified in spec - blob storage is primary use case
- **Simplicity Principle**: Constitution Principle 1 - start simple, expand if needed
- **DNS Zone Alignment**: Core infrastructure already has `privatelink.blob.core.windows.net`
- **Common Pattern**: Blob storage is most frequently used service for object storage demos

### Alternatives Considered
- **All Storage Services**: Would require 4 private endpoints + DNS zones (blob/file/table/queue)
  - Rejected: Adds complexity without clear lab requirement
- **File Storage Only**: Alternative for SMB scenarios
  - Rejected: Blob storage more versatile for demos

### References
- [Private endpoints for Azure Storage](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)
- Project spec.md: "Private endpoint for blob storage"

---

## Decision 3: Customer-Managed Key Configuration

### Decision
Use **user-assigned managed identity** for Key Vault access with **automatic key rotation enabled**

### Rationale
- **Security Best Practice**: Managed identity eliminates credential management
- **Constitution Alignment**: Principle 4 - no shared access keys, identity-based auth
- **Key Rotation**: Automatic rotation improves security posture without manual intervention
- **RBAC Model**: Managed identity gets Key Vault Crypto Service Encryption User role
- **Existing Pattern**: Matches approach used in 002-private-acr for Key Vault access

### Alternatives Considered
- **System-assigned managed identity**: Less flexible for multi-resource scenarios
  - Rejected: User-assigned identity can be reused if other storage accounts needed
- **Service principal**: Requires secret management
  - Rejected: Violates constitution principle (no shared secrets)
- **Manual key rotation**: Simpler but less secure
  - Rejected: Automatic rotation is Azure best practice

### Configuration Details
```bicep
// Key Vault Key
resource storageKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  name: 'storage-encryption-key'
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: ['encrypt', 'decrypt', 'wrapKey', 'unwrapKey']
    rotationPolicy: {
      lifetimeActions: [{
        trigger: { timeAfterCreate: 'P90D' }  // 90 days
        action: { type: 'Rotate' }
      }]
      attributes: {
        expiryTime: 'P2Y'  // 2 years
      }
    }
  }
}

// RBAC Assignment
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, keyVaultCryptoUser)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 
      'e147488a-f6f5-4113-8e2d-b22465e65bf6')  // Key Vault Crypto Service Encryption User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
```

### References
- [Customer-managed keys for Azure Storage encryption](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-overview)
- [Configure customer-managed keys with managed identity](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-configure-existing-account)
- [Key Vault key rotation](https://learn.microsoft.com/en-us/azure/key-vault/keys/how-to-configure-key-rotation)

---

## Decision 4: DNS Integration Pattern

### Decision
**Leverage existing core infrastructure** - no new DNS resources required

### Rationale
- **Infrastructure Ready**: Core deployment already has:
  - Private DNS zone: `privatelink.blob.core.windows.net` (deployed in rg-ai-core)
  - DNS Private Resolver: 10.1.0.68 (for P2S VPN clients)
  - VNet links: Private DNS zones linked to shared services VNet
- **Zero Additional Configuration**: Private endpoint auto-registers in existing DNS zone
- **Constitution Principle 6**: Modularity - storage depends on core, doesn't duplicate DNS infrastructure

### How It Works
1. Storage module creates private endpoint in shared services VNet subnet
2. Private endpoint automatically registers A record in existing `privatelink.blob.core.windows.net` zone
3. VPN clients query DNS resolver (10.1.0.68) → resolver queries VNet-linked private DNS zone
4. DNS returns private IP (10.1.x.x) instead of public IP

### Verification from Core Infrastructure
```bash
# From bicep/modules/private-dns-zones.bicep (already deployed)
resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
}

# From bicep/modules/dns-resolver.bicep (already deployed)
resource inboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  name: 'inbound-endpoint'
  properties: {
    ipConfigurations: [{
      subnet: { id: dnsResolverSubnetId }
      privateIpAllocationMethod: 'Dynamic'  // Gets 10.1.0.68
    }]
  }
}
```

### Alternatives Considered
- **Deploy separate DNS zone**: Redundant, violates DRY principle
  - Rejected: Core infrastructure already has complete DNS setup
- **Public endpoint with firewall rules**: Less secure
  - Rejected: Violates constitution principle 3 (private access only)

### References
- [Private endpoint DNS integration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- Project docs/core-infrastructure/README.md: DNS Private Resolver documentation
- bicep/modules/private-dns-zones.bicep: Existing DNS zone deployment

---

## Decision 5: Network Security Configuration

### Decision
**Disable public network access entirely** with private endpoint as sole access path

### Rationale
- **Zero Trust Model**: No public surface area, attack surface minimized
- **Constitution Principle 3**: Private connectivity only via VPN → VNet → private endpoint
- **Defense in Depth**: Even if firewall misconfigured, public access disabled at resource level
- **Compliance Alignment**: Matches production patterns for regulated workloads

### Configuration
```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  properties: {
    publicNetworkAccess: 'Disabled'  // Complete public access block
    allowBlobPublicAccess: false      // Disable anonymous blob access
    allowSharedKeyAccess: false       // Require Entra ID auth only
    minimumTlsVersion: 'TLS1_2'       // Enforce TLS 1.2+
    networkAcls: {
      defaultAction: 'Deny'           // Deny all by default
      bypass: 'None'                  // No exceptions
    }
  }
}
```

### Access Path
```
User → VPN Client → P2S Gateway → Hub VNet → 
Shared Services VNet → Private Endpoint → Storage Account (10.1.x.x)
```

### Alternatives Considered
- **Public access with IP allowlist**: Brittle, doesn't work for mobile users
  - Rejected: Violates constitution principle 3
- **Public access with VNet firewall rules**: Still exposes public endpoint
  - Rejected: Unnecessary attack surface

### References
- [Azure Storage network security](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security)
- [Disable public access to storage account](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security#change-the-default-network-access-rule)

---

## Decision 6: Bicep Module Architecture Pattern

### Decision
Follow **002-private-acr module pattern**: Separate reusable module + orchestration template

### Rationale
- **Consistency**: Matches established project pattern from ACR deployment
- **Reusability**: `bicep/modules/storage.bicep` can be imported by other templates
- **Separation of Concerns**: 
  - Module: Storage account resource logic (parameters → outputs)
  - Orchestration: Parameter file handling, dependency coordination
- **Testing**: Module can be validated independently

### Structure
```
bicep/
├── modules/
│   ├── storage.bicep              # Reusable module (like acr.bicep pattern)
│   └── [other modules]
└── storage/
    ├── main.bicep                 # Orchestration (imports ../modules/storage.bicep)
    ├── main.parameters.json       # Deployment parameters
    └── main.parameters.example.json  # Template for users
```

### Module Interface Pattern
```bicep
// bicep/modules/storage.bicep
param storageAccountName string
param location string
param keyVaultName string
param managedIdentityId string
param vnetName string
param privateEndpointSubnetName string

output storageAccountId string
output blobEndpoint string
output privateEndpointId string
```

### Orchestration Pattern
```bicep
// bicep/storage/main.bicep
module storage '../modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    storageAccountName: parameters.storageAccountName
    location: parameters.location
    keyVaultName: parameters.keyVaultName
    // ... other params
  }
}

output storageAccountName string = storage.outputs.storageAccountId
```

### Alternatives Considered
- **Monolithic single template**: Simpler but not reusable
  - Rejected: Breaks established project pattern, harder to maintain
- **Inline module in orchestration**: No separation
  - Rejected: Module reusability lost

### References
- Project bicep/modules/acr.bicep: Reference pattern
- Project bicep/registry/main.bicep: Reference orchestration
- [Bicep modules documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/modules)

---

## Decision 7: Resource Group Strategy

### Decision
Deploy to **separate resource group** `rg-ai-storage` (not rg-ai-core)

### Rationale
- **User Specification**: Clarified in spec - separate RG required
- **Constitution Principle 6 (Modularity)**: Independent lifecycle, clean deletion
- **Blast Radius Containment**: Storage experiments don't affect core infrastructure
- **RBAC Granularity**: Can assign storage-specific permissions without core access
- **Deletion Safety**: `az group delete -n rg-ai-storage` removes all storage resources cleanly

### Resource Distribution
```
rg-ai-core:
  - Virtual WAN, VPN Gateway, DNS Resolver
  - Private DNS zones (shared by all labs)
  - Key Vault (shared secrets)
  - Shared services VNet

rg-ai-registry:
  - Azure Container Registry
  - ACR private endpoint

rg-ai-storage:  ← NEW
  - Storage account
  - User-assigned managed identity
  - Storage encryption key (in Key Vault - cross-RG reference)
  - Blob private endpoint
```

### Cross-Resource Group Dependencies
```bicep
// Reference core Key Vault from rg-ai-core
var keyVaultResourceId = resourceId('rg-ai-core', 'Microsoft.KeyVault/vaults', keyVaultName)

// Reference shared services VNet from rg-ai-core
var vnetResourceId = resourceId('rg-ai-core', 'Microsoft.Network/virtualNetworks', vnetName)
```

### Alternatives Considered
- **Deploy to rg-ai-core**: Simpler but violates modularity
  - Rejected: Per spec clarification, separate RG required
- **Deploy to new rg-ai-labs**: Generic lab RG
  - Rejected: Less clear ownership, harder to track costs per lab

### References
- [Azure resource group best practices](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/overview#resource-groups)
- Project spec.md: Clarification recorded - separate RG

---

## Decision 8: Diagnostic Logging Strategy

### Decision
Enable **comprehensive diagnostic logs** to Log Analytics workspace in rg-ai-core

### Rationale
- **Security Monitoring**: Track CMK operations, access patterns, unauthorized attempts
- **Troubleshooting**: Debug private endpoint connectivity, DNS resolution issues
- **Compliance**: Audit trail for encryption key access (required for many regulations)
- **Centralized**: Reuse existing Log Analytics workspace from core infrastructure

### Logs to Capture
```bicep
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'storage-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspaceId  // From rg-ai-core
    logs: [
      { category: 'StorageRead', enabled: true }
      { category: 'StorageWrite', enabled: true }
      { category: 'StorageDelete', enabled: true }
    ]
    metrics: [
      { category: 'Transaction', enabled: true }
      { category: 'Capacity', enabled: true }
    ]
  }
}

// Blob service-specific logs
resource blobDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'blob-diagnostics'
  scope: storageAccount::blobService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'StorageRead', enabled: true, retentionPolicy: { days: 30 }}
      { category: 'StorageWrite', enabled: true, retentionPolicy: { days: 30 }}
    ]
  }
}
```

### Key Queries for Monitoring
```kusto
// Track CMK operations
StorageAccountLogs
| where TimeGenerated > ago(24h)
| where OperationName contains "CustomerKey"
| project TimeGenerated, OperationName, StatusCode, CallerIpAddress

// Private endpoint access patterns
StorageAccountLogs  
| where TimeGenerated > ago(7d)
| where CallerIpAddress startswith "10.1."  // Private VNet range
| summarize count() by bin(TimeGenerated, 1h), OperationName
```

### Alternatives Considered
- **Storage Analytics Logs (classic)**: Legacy approach
  - Rejected: Diagnostic settings are modern replacement with better integration
- **No logging**: Simpler but blind to issues
  - Rejected: Logging is production best practice for security

### References
- [Azure Storage monitoring](https://learn.microsoft.com/en-us/azure/storage/blobs/monitor-blob-storage)
- [Diagnostic settings for Azure Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/monitor-blob-storage#creating-a-diagnostic-setting)

---

## Implementation Patterns from Existing Modules

### Pattern 1: Private Endpoint Creation (from acr.bicep)
```bicep
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${storageAccountName}-blob-pe'
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, privateEndpointSubnetName)
    }
    privateLinkServiceConnections: [{
      name: 'blob-connection'
      properties: {
        privateLinkServiceId: storageAccount.id
        groupIds: ['blob']  // blob/file/table/queue
      }
    }]
  }
}

// Auto-registration in DNS zone
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'blob-config'
      properties: {
        privateDnsZoneId: resourceId('rg-ai-core', 'Microsoft.Network/privateDnsZones', 
          'privatelink.blob.core.windows.net')
      }
    }]
  }
}
```

### Pattern 2: Managed Identity Creation (from vpn-server-configuration.bicep)
```bicep
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${storageAccountName}-identity'
  location: location
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}
```

### Pattern 3: RBAC Assignment (from key-vault.bicep)
```bicep
// Key Vault Crypto Service Encryption User role
var keyVaultCryptoUserId = 'e147488a-f6f5-4113-8e2d-b22465e65bf6'

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, keyVaultCryptoUserId)
  scope: keyVault  // or keyVault::encryptionKey for key-level scope
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultCryptoUserId)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
```

### Pattern 4: Parameter File Structure (from registry/main.parameters.json)
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "storageAccountName": {
      "value": "stailab001"  // 3-24 chars, lowercase/numbers only
    },
    "location": {
      "value": "eastus"
    },
    "keyVaultName": {
      "reference": {
        "keyVault": {
          "id": "/subscriptions/{sub-id}/resourceGroups/rg-ai-core/providers/Microsoft.KeyVault/vaults/kv-ai-core"
        },
        "secretName": "key-vault-name"
      }
    }
  }
}
```

---

## Unresolved Questions / Future Research

None - all technical context clarifications resolved.

---

## Next Steps (Phase 1)

1. **Create data-model.md**: Document storage entities, key properties, relationships
2. **Generate deployment contract**: `contracts/deployment-contract.md` with Bicep interface
3. **Create quickstart.md**: Step-by-step deployment guide for users
4. **Update Copilot context**: Run `.specify/scripts/bash/update-agent-context.sh copilot`

---

## References

### Official Documentation
- [Azure Storage overview](https://learn.microsoft.com/en-us/azure/storage/common/storage-introduction)
- [Customer-managed keys](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-overview)
- [Private endpoints](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)
- [Managed identities for Azure resources](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview)
- [Bicep modules](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/modules)

### Project References
- [specs/005-storage-cmk/spec.md](../spec.md) - Feature specification
- [bicep/modules/acr.bicep](../../bicep/modules/acr.bicep) - Private endpoint pattern
- [bicep/modules/key-vault.bicep](../../bicep/modules/key-vault.bicep) - RBAC pattern
- [docs/core-infrastructure/README.md](../../docs/core-infrastructure/README.md) - DNS infrastructure

