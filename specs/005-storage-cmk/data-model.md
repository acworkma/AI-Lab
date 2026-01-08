# Data Model: Storage Account with Customer Managed Keys

**Feature**: 005-storage-cmk  
**Phase**: 1 - Data Model Definition  
**Date**: 2025-01-22

## Overview

This document defines the Azure resources, their properties, relationships, and state transitions for the storage CMK implementation. Unlike application data models with databases, this infrastructure data model documents Azure resource entities and their configuration.

---

## Resource Entities

### Entity 1: Storage Account

**Purpose**: Blob storage container with customer-managed encryption keys

**Azure Resource Type**: `Microsoft.Storage/storageAccounts@2023-01-01`

**Properties**:
| Property | Type | Required | Constraints | Description |
|----------|------|----------|-------------|-------------|
| `name` | string | Yes | 3-24 chars, lowercase/numbers only, globally unique | Storage account name (e.g., `stailab001`) |
| `location` | string | Yes | Valid Azure region | Deployment region (e.g., `eastus`) |
| `kind` | string | Yes | Must be `StorageV2` | General-purpose v2 account type |
| `sku.name` | string | Yes | `Standard_LRS` | Storage redundancy tier |
| `publicNetworkAccess` | string | Yes | Must be `Disabled` | Block all public access |
| `allowBlobPublicAccess` | bool | Yes | Must be `false` | Disable anonymous blob access |
| `allowSharedKeyAccess` | bool | Yes | Must be `false` | Require Entra ID auth only |
| `minimumTlsVersion` | string | Yes | `TLS1_2` or `TLS1_3` | Minimum TLS version |
| `encryption.services.blob.enabled` | bool | Yes | Must be `true` | Enable blob encryption |
| `encryption.keySource` | string | Yes | Must be `Microsoft.Keyvault` | Use Key Vault keys |
| `encryption.keyvaultproperties.keyname` | string | Yes | Valid key name | Encryption key reference |
| `encryption.keyvaultproperties.keyvaulturi` | string | Yes | Valid Key Vault URI | Key Vault endpoint |
| `encryption.identity.userAssignedIdentity` | string | Yes | Valid managed identity ID | Identity for Key Vault access |

**Validation Rules**:
- Storage account name must be globally unique across Azure
- When `keySource = Microsoft.Keyvault`, managed identity must have Key Vault Crypto Service Encryption User role
- When `publicNetworkAccess = Disabled`, at least one private endpoint must exist for access
- When `allowSharedKeyAccess = false`, RBAC roles required for all access (e.g., Storage Blob Data Contributor)

**Outputs**:
- `id`: Full resource ID for reference
- `primaryBlobEndpoint`: Public blob endpoint (unused due to private access)
- `primaryBlobHost`: DNS hostname for blob service

**State Lifecycle**:
```
NOT EXISTS → CREATING → ACTIVE → UPDATING → DELETING → DELETED
                           ↓
                      KEY ROTATION (automatic every 90 days)
```

---

### Entity 2: Blob Service Configuration

**Purpose**: Blob-specific settings for the storage account

**Azure Resource Type**: `Microsoft.Storage/storageAccounts/blobServices@2023-01-01`

**Properties**:
| Property | Type | Required | Constraints | Description |
|----------|------|----------|-------------|-------------|
| `name` | string | Yes | Must be `default` | Default blob service |
| `containerDeleteRetentionPolicy.enabled` | bool | No | - | Enable soft delete for containers |
| `containerDeleteRetentionPolicy.days` | int | No | 1-365 | Retention days (default: 7) |
| `deleteRetentionPolicy.enabled` | bool | No | - | Enable soft delete for blobs |
| `deleteRetentionPolicy.days` | int | No | 1-365 | Retention days (default: 7) |
| `isVersioningEnabled` | bool | No | - | Enable blob versioning |
| `changeFeed.enabled` | bool | No | - | Enable change feed |

**Validation Rules**:
- Soft delete retention must be ≥ 1 day
- Versioning recommended for production, optional for lab

**Parent Relationship**: Child of Storage Account entity

---

### Entity 3: Managed Identity

**Purpose**: Service identity for accessing Key Vault encryption keys

**Azure Resource Type**: `Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31`

**Properties**:
| Property | Type | Required | Constraints | Description |
|----------|------|----------|-------------|-------------|
| `name` | string | Yes | 3-128 chars | Identity name (e.g., `id-storage-cmk`) |
| `location` | string | Yes | Valid Azure region | Must match storage account region |

**Validation Rules**:
- Must exist before storage account deployment (dependency order)
- Must be in same region as storage account
- Requires RBAC assignment before storage encryption configuration

**Outputs**:
- `principalId`: Service principal ID for RBAC assignments
- `clientId`: Client ID (unused in this scenario)
- `id`: Resource ID for storage account identity reference

**State Lifecycle**:
```
NOT EXISTS → CREATING → ACTIVE → DELETING → DELETED
                          ↓
                    RBAC ASSIGNED (before storage creation)
```

---

### Entity 4: Encryption Key

**Purpose**: RSA key in Key Vault for storage encryption

**Azure Resource Type**: `Microsoft.KeyVault/vaults/keys@2023-07-01`

**Properties**:
| Property | Type | Required | Constraints | Description |
|----------|------|----------|-------------|-------------|
| `name` | string | Yes | Pattern: `^[a-zA-Z0-9-]+$` | Key name (e.g., `storage-encryption-key`) |
| `kty` | string | Yes | Must be `RSA` or `RSA-HSM` | Key type |
| `keySize` | int | Yes | 2048, 3072, or 4096 | Key size in bits (2048 for lab) |
| `keyOps` | array | Yes | Must include `[encrypt, decrypt, wrapKey, unwrapKey]` | Permitted operations |
| `rotationPolicy.lifetimeActions` | array | No | - | Auto-rotation trigger (90 days) |
| `rotationPolicy.attributes.expiryTime` | string | No | ISO 8601 duration | Key expiry (P2Y = 2 years) |

**Validation Rules**:
- Key operations must include all 4 required operations for storage encryption
- Rotation policy recommended (every 90 days per best practice)
- Key must be in same Key Vault as RBAC assignment

**Parent Relationship**: Child of Key Vault entity (in rg-ai-core)

**Outputs**:
- `keyUriWithVersion`: Versioned key URI for storage account configuration
- `keyUri`: Unversioned key URI (allows auto-rotation)

**State Lifecycle**:
```
NOT EXISTS → CREATING → ACTIVE → ROTATING → NEW VERSION ACTIVE
                          ↓                        ↓
                       USED BY STORAGE      OLD VERSION DEPRECATED (after expiry)
```

---

### Entity 5: Private Endpoint

**Purpose**: Private network interface for blob storage access

**Azure Resource Type**: `Microsoft.Network/privateEndpoints@2023-05-01`

**Properties**:
| Property | Type | Required | Constraints | Description |
|----------|------|----------|-------------|-------------|
| `name` | string | Yes | - | Endpoint name (e.g., `pe-storage-blob`) |
| `location` | string | Yes | Valid Azure region | Must match storage account region |
| `subnet.id` | string | Yes | Valid subnet resource ID | Target subnet in shared services VNet |
| `privateLinkServiceConnections[0].groupIds` | array | Yes | Must be `["blob"]` | Storage sub-resource type |
| `privateLinkServiceConnections[0].privateLinkServiceId` | string | Yes | Valid storage account ID | Target storage account |

**Validation Rules**:
- Subnet must allow private endpoints (no delegation required)
- Group ID must match storage service type (`blob`, not `file/table/queue`)
- Storage account must exist before private endpoint creation

**Outputs**:
- `id`: Private endpoint resource ID
- `networkInterfaces[0].ipConfigurations[0].privateIPAddress`: Allocated private IP (e.g., 10.1.4.5)

**State Lifecycle**:
```
NOT EXISTS → CREATING → ACTIVE → UPDATING → DELETING → DELETED
                          ↓
                    DNS RECORD AUTO-REGISTERED (in privatelink.blob.core.windows.net)
```

---

### Entity 6: Private DNS Zone Group

**Purpose**: Links private endpoint to private DNS zone for automatic registration

**Azure Resource Type**: `Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01`

**Properties**:
| Property | Type | Required | Constraints | Description |
|----------|------|----------|-------------|-------------|
| `name` | string | Yes | Typically `default` | Zone group name |
| `privateDnsZoneConfigs[0].name` | string | Yes | - | Config name (e.g., `blob-config`) |
| `privateDnsZoneConfigs[0].privateDnsZoneId` | string | Yes | Valid DNS zone ID | Must be `privatelink.blob.core.windows.net` zone |

**Validation Rules**:
- DNS zone must exist before zone group creation (deployed in rg-ai-core)
- DNS zone must be linked to shared services VNet

**Parent Relationship**: Child of Private Endpoint entity

**Outputs**:
- DNS A record automatically created: `stailab001.blob.core.windows.net` → `10.1.4.5`

**State Lifecycle**:
```
NOT EXISTS → CREATING → ACTIVE (auto-registers DNS) → DELETING → DELETED
                                                              ↓
                                                    DNS RECORD AUTO-REMOVED
```

---

### Entity 7: RBAC Assignment (Key Vault)

**Purpose**: Grant managed identity permission to access encryption key

**Azure Resource Type**: `Microsoft.Authorization/roleAssignments@2022-04-01`

**Properties**:
| Property | Type | Required | Constraints | Description |
|----------|------|----------|-------------|-------------|
| `name` | string | Yes | Must be GUID | Use `guid(storage.id, identity.id, roleId)` |
| `roleDefinitionId` | string | Yes | Must be `e147488a-...` | Key Vault Crypto Service Encryption User role ID |
| `principalId` | string | Yes | Valid service principal ID | Managed identity's principal ID |
| `principalType` | string | Yes | Must be `ServicePrincipal` | Principal type |
| `scope` | string | Yes | Key Vault or Key resource ID | RBAC scope (Key Vault level recommended) |

**Validation Rules**:
- Role assignment name must be unique (GUID ensures this)
- Principal ID must match managed identity's principal ID
- Role must be `Key Vault Crypto Service Encryption User` (not Key Vault Crypto User - different role!)

**Parent Relationship**: Associated with Managed Identity and Key Vault entities

**State Lifecycle**:
```
NOT EXISTS → CREATING → ACTIVE → DELETING → DELETED
                          ↓
                    PERMISSION GRANTED (identity can use key)
```

---

### Entity 8: Diagnostic Settings

**Purpose**: Send storage logs/metrics to Log Analytics workspace

**Azure Resource Type**: `Microsoft.Insights/diagnosticSettings@2021-05-01-preview`

**Properties**:
| Property | Type | Required | Constraints | Description |
|----------|------|----------|-------------|-------------|
| `name` | string | Yes | - | Settings name (e.g., `storage-diagnostics`) |
| `workspaceId` | string | Yes | Valid Log Analytics workspace ID | Target workspace (in rg-ai-core) |
| `logs[].category` | string | Yes | `StorageRead/Write/Delete` | Log categories to capture |
| `logs[].enabled` | bool | Yes | Must be `true` | Enable log capture |
| `metrics[].category` | string | Yes | `Transaction`, `Capacity` | Metric categories |
| `metrics[].enabled` | bool | Yes | Must be `true` | Enable metric capture |

**Validation Rules**:
- Log Analytics workspace must exist (deployed in rg-ai-core)
- At least one log category required for security monitoring

**Parent Relationship**: Child of Storage Account entity (separate diagnostic settings for blob service)

---

## Resource Relationships

```
┌─────────────────────────────────────────────────────────────────┐
│                        rg-ai-core (Core RG)                     │
│  ┌──────────────────┐      ┌─────────────────────────────────┐ │
│  │   Key Vault      │      │  Private DNS Zone               │ │
│  │                  │      │  privatelink.blob.core.windows.net │
│  │  ┌────────────┐  │      └──────────────┬──────────────────┘ │
│  │  │ Encryption │  │                     │ VNet Link         │
│  │  │    Key     │  │                     ▼                    │
│  │  └────────────┘  │      ┌─────────────────────────────────┐ │
│  └────────┬─────────┘      │  Shared Services VNet            │ │
│           │                │  ┌──────────────────────────┐    │ │
│           │ RBAC           │  │  Private Endpoint Subnet │    │ │
│           │                │  └─────────────┬────────────┘    │ │
│           │                └────────────────┼─────────────────┘ │
└───────────┼─────────────────────────────────┼───────────────────┘
            │                                 │
            ▼                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                    rg-ai-storage (Storage RG)                   │
│  ┌──────────────────┐      ┌──────────────────────────────────┐ │
│  │ Managed Identity │─────▶│     Storage Account              │ │
│  │                  │      │  ┌────────────────────────────┐  │ │
│  │ (for Key Vault)  │      │  │   Blob Service             │  │ │
│  └──────────────────┘      │  │   - CMK encrypted          │  │ │
│                            │  │   - Private access only    │  │ │
│                            │  └────────────────────────────┘  │ │
│                            └───────────────┬──────────────────┘ │
│                                            │                    │
│                            ┌───────────────▼──────────────────┐ │
│                            │    Private Endpoint (Blob)       │ │
│                            │    - IP: 10.1.4.x                │ │
│                            │    - DNS: auto-registered        │ │
│                            └──────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘

Access Path:
User → VPN Client → P2S Gateway → Hub VNet → Shared Services VNet 
     → Private Endpoint → Storage Account (encrypted with CMK)
```

### Dependency Graph (Deployment Order)

```
1. Core Infrastructure (already deployed)
   ├── Virtual WAN + Hub
   ├── Shared Services VNet
   ├── Private DNS Zone (privatelink.blob.core.windows.net)
   ├── DNS Resolver
   └── Key Vault

2. Phase 1: Identity + Key
   ├── Managed Identity
   ├── Encryption Key (in Key Vault)
   └── RBAC Assignment (identity → key)

3. Phase 2: Storage Account
   ├── Storage Account (depends on: managed identity, encryption key)
   └── Blob Service Configuration

4. Phase 3: Private Networking
   ├── Private Endpoint (depends on: storage account, subnet)
   └── Private DNS Zone Group (depends on: private endpoint, DNS zone)

5. Phase 4: Monitoring
   └── Diagnostic Settings (depends on: storage account, Log Analytics)
```

**Critical Dependencies**:
- Managed identity must be created BEFORE storage account
- RBAC assignment must succeed BEFORE configuring storage encryption
- Encryption key must exist BEFORE storage account deployment
- Private endpoint must exist for access (since public access disabled)

---

## Resource Configuration Matrix

| Component | Resource Group | Deployment Template | Parameters From |
|-----------|----------------|---------------------|-----------------|
| Managed Identity | rg-ai-storage | bicep/modules/storage.bicep | main.parameters.json |
| Encryption Key | rg-ai-core | bicep/modules/storage.bicep (cross-RG) | Key Vault name param |
| RBAC Assignment | rg-ai-core (scope) | bicep/modules/storage.bicep | Managed identity output |
| Storage Account | rg-ai-storage | bicep/modules/storage.bicep | main.parameters.json |
| Private Endpoint | rg-ai-storage | bicep/modules/storage.bicep | VNet/subnet params |
| DNS Zone Group | rg-ai-storage | bicep/modules/storage.bicep | DNS zone ID param |
| Diagnostic Settings | rg-ai-storage | bicep/modules/storage.bicep | Log Analytics ID param |

---

## State Transitions

### Storage Account Encryption State Machine

```
┌──────────────────┐
│  No Encryption   │ (Initial - never exists in this project)
└────────┬─────────┘
         │
         │ Deploy with CMK
         ▼
┌──────────────────┐
│ CMK Encrypted    │◀──────────┐
│ (Active)         │           │
└────────┬─────────┘           │
         │                     │
         │ 90 days elapsed     │ Key rotation complete
         ▼                     │
┌──────────────────┐           │
│ Key Rotation     │───────────┘
│ (Automatic)      │
└──────────────────┘
```

**Triggers**:
- Key rotation: Time-based (every 90 days per rotation policy)
- Encryption disabled → enabled: Requires redeployment (not allowed - always encrypted)

**Error States**:
- Key Vault unreachable: Storage operations fail (data encrypted, cannot decrypt)
- Managed identity RBAC missing: Deployment fails with "Forbidden" error
- Private endpoint missing: No access (public disabled)

### Private Endpoint Connection State

```
┌──────────────────┐
│   Pending        │
└────────┬─────────┘
         │
         │ Auto-approved (same tenant)
         ▼
┌──────────────────┐
│   Approved       │
│   (Active)       │
└────────┬─────────┘
         │
         │ DNS registration complete
         ▼
┌──────────────────┐
│   Connected      │ (Fully operational)
└──────────────────┘
```

---

## Data Validation Rules Summary

### Naming Conventions
- Storage Account: `st[project][sequence]` (e.g., `stailab001`)
  - Constraint: 3-24 chars, lowercase + numbers only, globally unique
- Managed Identity: `id-storage-cmk-[sequence]` (e.g., `id-storage-cmk-001`)
- Private Endpoint: `pe-[resource]-[service]` (e.g., `pe-storage-blob`)
- Encryption Key: `storage-encryption-key-[sequence]`

### Security Validation
- ✅ Public network access must be `Disabled`
- ✅ Shared key access must be `false`
- ✅ Minimum TLS version must be `TLS1_2` or higher
- ✅ Encryption key source must be `Microsoft.Keyvault` (not Microsoft.Storage)
- ✅ Managed identity must have RBAC assignment before storage deployment

### Network Validation
- ✅ Private endpoint must exist in shared services VNet
- ✅ DNS zone group must reference `privatelink.blob.core.windows.net`
- ✅ Subnet must not have conflicting delegations
- ✅ VNet must be linked to private DNS zone

---

## Outputs for Dependent Systems

### Bicep Module Outputs
```bicep
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output privateEndpointIp string = privateEndpoint.properties.networkInterfaces[0].ipConfigurations[0].privateIPAddress
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
```

### Documentation Outputs
- Storage account connection string (for Azure CLI/SDK - requires RBAC role assignment)
- Private IP address for verification (e.g., 10.1.4.5)
- DNS name for blob access: `<storage-name>.blob.core.windows.net` (resolves to private IP)

---

## Testing Validation

### Resource Validation Checks
```bash
# 1. Verify CMK encryption
az storage account show -n stailab001 -g rg-ai-storage \
  --query "encryption.keySource" -o tsv
# Expected: Microsoft.Keyvault

# 2. Verify public access disabled
az storage account show -n stailab001 -g rg-ai-storage \
  --query "publicNetworkAccess" -o tsv
# Expected: Disabled

# 3. Verify private endpoint IP
az network private-endpoint show -n pe-storage-blob -g rg-ai-storage \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv
# Expected: 10.1.4.x

# 4. Verify DNS resolution from VPN client
nslookup stailab001.blob.core.windows.net 10.1.0.68
# Expected: Address: 10.1.4.x (private IP)

# 5. Verify managed identity RBAC
az role assignment list --assignee <principal-id> \
  --scope /subscriptions/{sub}/resourceGroups/rg-ai-core/providers/Microsoft.KeyVault/vaults/kv-ai-core
# Expected: Role "Key Vault Crypto Service Encryption User"
```

---

## References

- [Azure Storage resource provider schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.storage/storageaccounts)
- [Customer-managed keys properties](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-configure-existing-account)
- [Private endpoint schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.network/privateendpoints)
- [Managed identity schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.managedidentity/userassignedidentities)

