# Data Model: Storage CMK Refactor

**Feature**: 010-storage-cmk-refactor  
**Date**: 2026-01-17  
**Purpose**: Document resource relationships and state transitions

## Resource Entities

### 1. User-Assigned Managed Identity

```yaml
Resource: Microsoft.ManagedIdentity/userAssignedIdentities
Name: id-stailab{suffix}-cmk
Location: eastus2
Resource Group: rg-ai-storage

Properties:
  - principalId: (auto-generated GUID)
  - clientId: (auto-generated GUID)
  - tenantId: (subscription tenant)

Tags:
  environment: dev
  purpose: CMK encryption identity for storage account
  owner: {deployer}
  deployedBy: bicep
  feature: 010-storage-cmk-refactor
```

**Relationships**:
- ASSIGNED_TO → Storage Account (via identity property)
- HAS_ROLE → Key Vault (Key Vault Crypto Service Encryption User)

---

### 2. Key Vault Key (Encryption Key)

```yaml
Resource: Microsoft.KeyVault/vaults/keys
Name: storage-encryption-key
Location: (inherited from Key Vault)
Resource Group: rg-ai-keyvault (cross-RG reference)

Properties:
  keyType: RSA
  keySize: 4096
  keyOps:
    - wrapKey
    - unwrapKey
  rotationPolicy:
    lifetimeActions:
      - trigger:
          timeAfterCreate: P18M  # 18 months
        action:
          type: Rotate
      - trigger:
          timeBeforeExpiry: P30D  # 30 days
        action:
          type: Notify
    attributes:
      expiryTime: P2Y  # 2 years
```

**Relationships**:
- STORED_IN → Key Vault (rg-ai-keyvault)
- USED_BY → Storage Account (encryption configuration)

---

### 3. Role Assignment (RBAC)

```yaml
Resource: Microsoft.Authorization/roleAssignments
Name: (auto-generated GUID based on scope + principal + role)
Scope: Key Vault resource ID
Resource Group: rg-ai-keyvault

Properties:
  roleDefinitionId: e147488a-f6f5-4113-8e2d-b22465e65bf6
    # Key Vault Crypto Service Encryption User
  principalId: {managed-identity-principal-id}
  principalType: ServicePrincipal
```

**Relationships**:
- GRANTS_ACCESS → Managed Identity
- SCOPED_TO → Key Vault

---

### 4. Storage Account (Update)

```yaml
Resource: Microsoft.Storage/storageAccounts
Name: stailab{suffix}
Location: eastus2
Resource Group: rg-ai-storage (existing)

# UPDATED Properties (CMK enablement):
identity:
  type: UserAssigned
  userAssignedIdentities:
    {managed-identity-resource-id}: {}

encryption:
  services:
    blob:
      enabled: true
      keyType: Account
  keySource: Microsoft.Keyvault  # Changed from Microsoft.Storage
  keyvaultproperties:
    keyname: storage-encryption-key
    keyvaulturi: https://{keyvault-name}.vault.azure.net
  identity:
    userAssignedIdentity: {managed-identity-resource-id}

# PRESERVED Properties (from 009-private-storage):
allowSharedKeyAccess: false
minimumTlsVersion: TLS1_2
publicNetworkAccess: Disabled
```

**Relationships**:
- USES_IDENTITY → Managed Identity
- ENCRYPTED_BY → Key Vault Key
- CONNECTED_VIA → Private Endpoint (existing)

---

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        rg-ai-keyvault                           │
│  ┌─────────────────┐         ┌──────────────────────────────┐  │
│  │   Key Vault     │ STORES  │  Encryption Key              │  │
│  │   (existing)    │─────────│  storage-encryption-key      │  │
│  │                 │         │  RSA-4096, P18M rotation     │  │
│  └────────┬────────┘         └──────────────────────────────┘  │
│           │                                                     │
│           │ ROLE: Key Vault Crypto Service Encryption User      │
│           ▼                                                     │
│  ┌─────────────────┐                                           │
│  │ Role Assignment │                                           │
│  │ (RBAC)          │                                           │
│  └────────┬────────┘                                           │
└───────────│─────────────────────────────────────────────────────┘
            │
            │ GRANTS ACCESS TO
            ▼
┌─────────────────────────────────────────────────────────────────┐
│                        rg-ai-storage                            │
│  ┌─────────────────┐                                           │
│  │ Managed Identity│                                           │
│  │ id-stailab*-cmk │                                           │
│  └────────┬────────┘                                           │
│           │                                                     │
│           │ ASSIGNED TO                                         │
│           ▼                                                     │
│  ┌─────────────────┐         ┌──────────────────────────────┐  │
│  │ Storage Account │ENCRYPTED│  Private Endpoint            │  │
│  │ stailab*        │   BY    │  (existing)                   │  │
│  │ (existing)      │◀────────│                              │  │
│  └─────────────────┘         └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## State Transitions

### Storage Account Encryption State

```
┌─────────────────┐     deploy-storage.sh     ┌──────────────────┐
│ Microsoft.Storage│ ──────────────────────▶  │ Microsoft.Keyvault│
│ (default)       │                           │ (CMK enabled)     │
└─────────────────┘                           └──────────────────┘
       │                                              │
       │ keySource: Microsoft.Storage                 │ keySource: Microsoft.Keyvault
       │ No managed identity                          │ userAssignedIdentity: set
       │ No key vault reference                       │ keyvaultproperties: set
       │                                              │
       ▼                                              ▼
  Platform-managed                              Customer-managed
  encryption keys                               encryption key
```

### Deployment Sequence

```
1. Validate Prerequisites
   ├── Check rg-ai-keyvault exists
   ├── Check Key Vault exists
   ├── Check rg-ai-storage exists
   └── Check Storage Account exists

2. Create Managed Identity
   └── id-stailab{suffix}-cmk in rg-ai-storage

3. Create Encryption Key
   └── storage-encryption-key in Key Vault (cross-RG)

4. Assign RBAC Role
   └── Key Vault Crypto Service Encryption User to managed identity

5. Update Storage Account
   ├── Add user-assigned identity
   └── Configure CMK encryption with key vault reference
```

---

## Validation Rules

| Entity | Rule | Validation Method |
|--------|------|-------------------|
| Key Vault | Soft-delete enabled | `az keyvault show --query properties.enableSoftDelete` |
| Key Vault | Purge protection enabled | `az keyvault show --query properties.enablePurgeProtection` |
| Encryption Key | RSA type | `az keyvault key show --query key.kty` |
| Encryption Key | 4096-bit | `az keyvault key show --query key.n` (length check) |
| Storage Account | CMK enabled | `az storage account show --query encryption.keySource` = "Microsoft.Keyvault" |
| Role Assignment | Exists | `az role assignment list --scope {kv-id} --assignee {mi-principal}` |
