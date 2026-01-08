# Deployment Contract: Storage CMK Module

**Feature**: 005-storage-cmk  
**Module**: bicep/modules/storage.bicep  
**Version**: 1.0.0  
**Date**: 2025-01-22

## Overview

This contract defines the interface for the storage account with customer-managed keys (CMK) Bicep module. It specifies required parameters, outputs, and deployment behavior for consumers of this module.

---

## Module Interface

### Input Parameters

#### Required Parameters

| Parameter | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `storageAccountName` | string | Globally unique storage account name | 3-24 chars, lowercase + numbers only |
| `location` | string | Azure region for deployment | Valid Azure region (e.g., `eastus`) |
| `keyVaultName` | string | Name of Key Vault containing encryption key | Must exist in accessible resource group |
| `managedIdentityName` | string | Name for user-assigned managed identity | Will be created by module |
| `vnetName` | string | Shared services VNet name | Must exist in vnetResourceGroup |
| `vnetResourceGroup` | string | Resource group containing VNet | Must have private endpoint subnet |
| `privateEndpointSubnetName` | string | Subnet name for private endpoint | Must exist in vnetName |
| `privateDnsZoneName` | string | Private DNS zone for blob storage | Must be `privatelink.blob.core.windows.net` |
| `privateDnsZoneResourceGroup` | string | Resource group containing DNS zone | Typically `rg-ai-core` |

#### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `skuName` | string | `Standard_LRS` | Storage account SKU (LRS/ZRS/GRS) |
| `enableBlobSoftDelete` | bool | `true` | Enable soft delete for blobs |
| `blobSoftDeleteRetentionDays` | int | `7` | Blob soft delete retention (1-365 days) |
| `enableContainerSoftDelete` | bool | `true` | Enable soft delete for containers |
| `containerSoftDeleteRetentionDays` | int | `7` | Container soft delete retention (1-365 days) |
| `enableVersioning` | bool | `false` | Enable blob versioning |
| `encryptionKeyName` | string | `storage-encryption-key` | Key Vault key name for CMK |
| `keyRotationDays` | int | `90` | Days before automatic key rotation |
| `logAnalyticsWorkspaceId` | string | `''` | Log Analytics workspace for diagnostics (empty = no logs) |
| `tags` | object | `{}` | Resource tags |

---

### Output Values

| Output | Type | Description | Usage |
|--------|------|-------------|-------|
| `storageAccountName` | string | Storage account name | Reference in other deployments |
| `storageAccountId` | string | Full resource ID | RBAC assignments, linking |
| `blobEndpoint` | string | Blob service endpoint URL | SDK connection strings |
| `blobPrivateEndpointId` | string | Private endpoint resource ID | Verification, diagnostics |
| `blobPrivateIpAddress` | string | Private endpoint IP address | DNS verification, troubleshooting |
| `managedIdentityId` | string | User-assigned identity resource ID | RBAC assignments |
| `managedIdentityPrincipalId` | string | Identity principal ID | External RBAC (if needed) |
| `encryptionKeyId` | string | Key Vault key resource ID | Audit, key rotation verification |

---

## Deployment Behavior

### Resource Creation Order

1. **User-Assigned Managed Identity** (Microsoft.ManagedIdentity/userAssignedIdentities)
   - Created first (no dependencies)
   - Principal ID used for RBAC assignment

2. **Encryption Key** (Microsoft.KeyVault/vaults/keys)
   - Created in existing Key Vault (cross-resource-group reference)
   - Rotation policy configured

3. **RBAC Assignment** (Microsoft.Authorization/roleAssignments)
   - Grants managed identity `Key Vault Crypto Service Encryption User` role
   - Scoped to Key Vault resource
   - Must complete before storage account deployment

4. **Storage Account** (Microsoft.Storage/storageAccounts)
   - Depends on: managed identity, encryption key, RBAC assignment
   - Created with CMK configuration from start
   - Public access disabled

5. **Blob Service Configuration** (Microsoft.Storage/storageAccounts/blobServices)
   - Child resource of storage account
   - Configures soft delete, versioning

6. **Private Endpoint** (Microsoft.Network/privateEndpoints)
   - Depends on: storage account, VNet/subnet
   - Connects to blob sub-resource

7. **Private DNS Zone Group** (Microsoft.Network/privateEndpoints/privateDnsZoneGroups)
   - Child resource of private endpoint
   - Auto-registers DNS A record

8. **Diagnostic Settings** (Microsoft.Insights/diagnosticSettings)
   - Depends on: storage account, Log Analytics workspace (if provided)
   - Two settings: account-level and blob service-level

### Idempotency Guarantees

- ✅ Re-running deployment with same parameters = no changes
- ✅ RBAC assignment uses deterministic GUID (no duplicates)
- ✅ Encryption key supports updates (rotation policy changes)
- ✅ Private endpoint updates subnet if changed

### Error Handling

| Error Scenario | Module Behavior | User Action Required |
|----------------|-----------------|---------------------|
| Storage account name taken | Deployment fails with conflict error | Choose different `storageAccountName` |
| Key Vault not found | Deployment fails with not found error | Verify `keyVaultName` and permissions |
| VNet/subnet not found | Deployment fails with not found error | Deploy core infrastructure first |
| DNS zone not found | Deployment fails with not found error | Deploy core infrastructure first |
| Insufficient permissions | Deployment fails with authorization error | Grant Owner/Contributor on target RG and core RG |

---

## Usage Examples

### Example 1: Minimal Deployment (Default Settings)

```bicep
module storage '../modules/storage.bicep' = {
  name: 'storage-deployment'
  scope: resourceGroup('rg-ai-storage')
  params: {
    storageAccountName: 'stailab001'
    location: 'eastus'
    keyVaultName: 'kv-ai-core'
    managedIdentityName: 'id-storage-cmk-001'
    vnetName: 'vnet-ai-sharedservices'
    vnetResourceGroup: 'rg-ai-core'
    privateEndpointSubnetName: 'snet-private-endpoints'
    privateDnsZoneName: 'privatelink.blob.core.windows.net'
    privateDnsZoneResourceGroup: 'rg-ai-core'
  }
}

output storageAccountName string = storage.outputs.storageAccountName
```

**Resources Created**:
- Storage account with Standard_LRS
- Managed identity
- Encryption key (90-day rotation)
- Blob private endpoint
- Blob service with 7-day soft delete
- No diagnostic logs (Log Analytics not provided)

---

### Example 2: Production-Ready with Logging

```bicep
module storage '../modules/storage.bicep' = {
  name: 'storage-deployment-prod'
  scope: resourceGroup('rg-ai-storage')
  params: {
    storageAccountName: 'staiprod001'
    location: 'eastus'
    skuName: 'Standard_ZRS'  // Zone-redundant for higher availability
    
    // Encryption
    keyVaultName: 'kv-ai-core'
    managedIdentityName: 'id-storage-cmk-prod'
    encryptionKeyName: 'storage-prod-key'
    keyRotationDays: 60  // More frequent rotation
    
    // Networking
    vnetName: 'vnet-ai-sharedservices'
    vnetResourceGroup: 'rg-ai-core'
    privateEndpointSubnetName: 'snet-private-endpoints'
    privateDnsZoneName: 'privatelink.blob.core.windows.net'
    privateDnsZoneResourceGroup: 'rg-ai-core'
    
    // Data protection
    enableBlobSoftDelete: true
    blobSoftDeleteRetentionDays: 30  // Longer retention
    enableContainerSoftDelete: true
    containerSoftDeleteRetentionDays: 30
    enableVersioning: true  // Enable versioning for compliance
    
    // Monitoring
    logAnalyticsWorkspaceId: '/subscriptions/{sub}/resourceGroups/rg-ai-core/providers/Microsoft.OperationalInsights/workspaces/law-ai-core'
    
    // Tags
    tags: {
      environment: 'production'
      project: 'AI-Lab'
      feature: '005-storage-cmk'
      costCenter: 'engineering'
    }
  }
}
```

**Additional Resources**:
- Zone-redundant storage (ZRS)
- 60-day key rotation
- 30-day soft delete retention
- Blob versioning enabled
- Diagnostic logs to Log Analytics

---

### Example 3: Orchestration Template Pattern

```bicep
// bicep/storage/main.bicep
targetScope = 'subscription'

param storageAccountName string
param location string

// Core infrastructure references
var coreResourceGroupName = 'rg-ai-core'
var storageResourceGroupName = 'rg-ai-storage'

// Existing core resources
resource coreRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: coreResourceGroupName
}

// Create storage resource group
resource storageRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: storageResourceGroupName
  location: location
}

// Deploy storage module
module storage '../modules/storage.bicep' = {
  name: 'storage-deployment-${uniqueString(storageRg.id)}'
  scope: storageRg
  params: {
    storageAccountName: storageAccountName
    location: location
    keyVaultName: 'kv-ai-core'
    managedIdentityName: 'id-storage-cmk-${uniqueString(storageRg.id)}'
    vnetName: 'vnet-ai-sharedservices'
    vnetResourceGroup: coreResourceGroupName
    privateEndpointSubnetName: 'snet-private-endpoints'
    privateDnsZoneName: 'privatelink.blob.core.windows.net'
    privateDnsZoneResourceGroup: coreResourceGroupName
    logAnalyticsWorkspaceId: '${coreRg.id}/providers/Microsoft.OperationalInsights/workspaces/law-ai-core'
  }
}

output storageAccountName string = storage.outputs.storageAccountName
output blobPrivateIpAddress string = storage.outputs.blobPrivateIpAddress
```

**Deployment Command**:
```bash
az deployment sub create \
  --location eastus \
  --template-file bicep/storage/main.bicep \
  --parameters storageAccountName=stailab001 location=eastus
```

---

## Parameter Validation Contract

### Pre-Deployment Validation

The module performs these validations (deployment fails if violated):

```bicep
// Storage account name validation
@minLength(3)
@maxLength(24)
@description('Storage account name (3-24 lowercase chars/numbers)')
param storageAccountName string

// SKU validation
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Premium_LRS'
])
param skuName string = 'Standard_LRS'

// Retention validation
@minValue(1)
@maxValue(365)
@description('Soft delete retention days (1-365)')
param blobSoftDeleteRetentionDays int = 7

// Key rotation validation
@minValue(30)
@maxValue(730)
@description('Key rotation interval in days (30-730)')
param keyRotationDays int = 90

// DNS zone validation (compile-time check)
var validDnsZone = privateDnsZoneName == 'privatelink.blob.core.windows.net'
var _ = validDnsZone ? '' : error('DNS zone must be privatelink.blob.core.windows.net')
```

### Runtime Validation

These checks happen during deployment:

1. **Storage account name availability**
   - Azure checks global uniqueness
   - Fails with: `StorageAccountAlreadyTaken`

2. **Key Vault access**
   - Module must have `Key Vault Administrator` or `Owner` role on Key Vault
   - Fails with: `AuthorizationFailed`

3. **VNet/subnet existence**
   - References must resolve to actual resources
   - Fails with: `ResourceNotFound`

4. **RBAC assignment**
   - Managed identity must acquire role before storage uses key
   - Fails with: `Forbidden` if RBAC incomplete

---

## Dependencies Contract

### Required Pre-Existing Resources

| Resource | Resource Group | Deployment | Purpose |
|----------|----------------|------------|---------|
| Key Vault | rg-ai-core | bicep/main.bicep | Stores encryption keys |
| Virtual Network | rg-ai-core | bicep/main.bicep | Private endpoint connectivity |
| Private DNS Zone | rg-ai-core | bicep/main.bicep | DNS resolution for private endpoint |
| Log Analytics Workspace (optional) | rg-ai-core | bicep/main.bicep | Diagnostic logging |

**Deployment Sequence**:
```
1. Core Infrastructure (bicep/main.bicep)
   ↓
2. Storage CMK (bicep/storage/main.bicep)
```

### Cross-Resource-Group References

The module creates resources in `rg-ai-storage` but references resources in `rg-ai-core`:

```bicep
// Key Vault reference (cross-RG)
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(subscription().subscriptionId, privateDnsZoneResourceGroup)  // rg-ai-core
}

// VNet reference (cross-RG)
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: vnetName
  scope: resourceGroup(subscription().subscriptionId, vnetResourceGroup)  // rg-ai-core
}

// DNS Zone reference (cross-RG)
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: privateDnsZoneName
  scope: resourceGroup(subscription().subscriptionId, privateDnsZoneResourceGroup)  // rg-ai-core
}
```

**Required Permissions**:
- Deployment identity needs `Reader` role on `rg-ai-core` (to reference resources)
- Deployment identity needs `Contributor` role on `rg-ai-storage` (to create resources)
- Deployment identity needs `Key Vault Administrator` role on Key Vault (to create key + RBAC)

---

## Security Contract

### Enforced Security Controls

These security settings are **hard-coded** (not parameterized) to enforce security standards:

```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  properties: {
    // Security controls (not parameterized)
    publicNetworkAccess: 'Disabled'         // ALWAYS disabled
    allowBlobPublicAccess: false            // ALWAYS false
    allowSharedKeyAccess: false             // ALWAYS false (Entra ID only)
    minimumTlsVersion: 'TLS1_2'             // ALWAYS TLS 1.2+
    supportsHttpsTrafficOnly: true          // ALWAYS HTTPS only
    
    // Encryption controls (not parameterized)
    encryption: {
      services: {
        blob: { enabled: true }             // ALWAYS encrypted
      }
      keySource: 'Microsoft.Keyvault'       // ALWAYS CMK (never Microsoft.Storage)
      requireInfrastructureEncryption: true // ALWAYS double encryption
    }
  }
}
```

**Rationale**: These settings align with constitution principles and production security standards. Users cannot accidentally deploy insecure configurations.

---

## Testing Contract

### Module Validation

Before using this module, validate with:

```bash
# 1. Template validation
az deployment group validate \
  --resource-group rg-ai-storage \
  --template-file bicep/modules/storage.bicep \
  --parameters @bicep/storage/main.parameters.json

# 2. What-if analysis
az deployment group what-if \
  --resource-group rg-ai-storage \
  --template-file bicep/storage/main.bicep \
  --parameters @bicep/storage/main.parameters.json
```

### Post-Deployment Verification

After successful deployment, verify:

```bash
# 1. CMK encryption enabled
az storage account show -n stailab001 -g rg-ai-storage \
  --query "encryption.keySource" -o tsv
# Expected: Microsoft.Keyvault

# 2. Public access disabled
az storage account show -n stailab001 -g rg-ai-storage \
  --query "publicNetworkAccess" -o tsv
# Expected: Disabled

# 3. Private endpoint connected
az network private-endpoint show -n pe-storage-blob-* -g rg-ai-storage \
  --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv
# Expected: Approved

# 4. DNS resolution (from VPN client)
nslookup stailab001.blob.core.windows.net 10.1.0.68
# Expected: Address: 10.1.x.x (private IP)
```

---

## Upgrade/Modification Contract

### Supported In-Place Updates

These parameters can be changed in subsequent deployments:

- ✅ `blobSoftDeleteRetentionDays` (1-365)
- ✅ `containerSoftDeleteRetentionDays` (1-365)
- ✅ `enableVersioning` (false → true, but not true → false without data loss)
- ✅ `keyRotationDays` (30-730)
- ✅ `tags` (add/remove/modify)
- ✅ `logAnalyticsWorkspaceId` (add/remove logging)

### Unsupported Changes (Require Redeployment)

These changes will fail or cause data loss:

- ❌ `storageAccountName` (immutable - requires new storage account)
- ❌ `location` (immutable)
- ❌ `skuName` (some SKU changes allowed, but LRS → Premium requires migration)
- ❌ Disabling CMK encryption (not supported - always encrypted)
- ❌ Enabling public access (hard-coded to disabled)

### Deletion Behavior

```bash
# Delete storage resource group
az group delete -n rg-ai-storage --yes --no-wait

# Resources deleted:
# - Storage account (data permanently deleted)
# - Private endpoint (DNS record auto-removed)
# - Managed identity
# - Diagnostic settings

# Resources NOT deleted (in rg-ai-core):
# - Encryption key (remains in Key Vault)
# - RBAC assignment on Key Vault (orphaned - clean up manually if desired)
# - Private DNS zone, VNet, Log Analytics (shared by other labs)
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-01-22 | Initial contract definition |

---

## References

- [Azure Storage Bicep reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.storage/storageaccounts)
- [Private endpoint Bicep reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.network/privateendpoints)
- [Customer-managed keys overview](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-overview)
- Project: [data-model.md](../data-model.md) - Resource entities and relationships
- Project: [spec.md](../spec.md) - Feature requirements

