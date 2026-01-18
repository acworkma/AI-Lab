# Research: Storage CMK Refactor

**Feature**: 010-storage-cmk-refactor  
**Date**: 2026-01-17  
**Purpose**: Resolve all technical unknowns before Phase 1 design

## Research Tasks

### 1. Azure Storage CMK Requirements

**Task**: Determine exact requirements for CMK encryption on existing storage accounts

**Findings**:
- **Key Types**: Azure Storage encryption supports RSA and RSA-HSM keys of sizes 2048, 3072, and 4096
- **Key Vault Requirements**: Must have soft-delete and purge protection enabled
- **Identity Options**: User-assigned or system-assigned managed identity supported for existing accounts
- **Key URI**: Use versionless key URI for automatic rotation support

**Decision**: Use RSA 4096-bit key with user-assigned managed identity for explicit control  
**Rationale**: 4096-bit provides strongest security; user-assigned identity allows pre-configuration of RBAC  
**Alternatives Considered**: RSA-HSM (rejected - adds cost for lab environment), system-assigned identity (rejected - less flexible for cross-resource-group scenarios)

**Source**: [Customer-managed keys for Azure Storage encryption](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-overview)

---

### 2. Key Vault RBAC Role for CMK

**Task**: Identify the correct Azure RBAC role for managed identity to access encryption key

**Findings**:
- **Key Vault Crypto Service Encryption User** is the official role for CMK access
- Role ID: `e147488a-f6f5-4113-8e2d-b22465e65bf6`
- Provides: wrap key, unwrap key, get key permissions
- Minimum required permissions for storage CMK

**Decision**: Use Key Vault Crypto Service Encryption User role  
**Rationale**: Microsoft-recommended role with minimum required permissions (least privilege)  
**Alternatives Considered**: Key Vault Crypto Officer (rejected - too broad), access policies (rejected - RBAC preferred)

**Source**: [Configure CMK for existing storage account](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-configure-existing-account)

---

### 3. Key Rotation Policy Best Practices

**Task**: Determine appropriate key rotation interval and configuration

**Findings**:
- Microsoft recommends rotating encryption keys "at least every two years"
- Default example in ARM templates: 18 months rotation (P18M), 2-year expiry (P2Y)
- Azure services automatically detect new key version within 1-24 hours
- Versionless key URI required for automatic rotation

**Decision**: Configure 18-month rotation (P18M) with 2-year expiry (P2Y)  
**Rationale**: Aligns with Microsoft examples and exceeds minimum 2-year recommendation  
**Alternatives Considered**: 90-day rotation (rejected - too aggressive, not recommended), manual rotation (rejected - operational burden)

**Source**: [Configure key auto-rotation in Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/keys/how-to-configure-key-rotation)

---

### 4. Bicep Pattern for Cross-Resource-Group References

**Task**: Determine how to reference existing Key Vault and Storage Account from different resource groups in Bicep

**Findings**:
- Use `existing` keyword with `scope` parameter for cross-RG references
- Pattern: `resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = { name: kvName, scope: resourceGroup(kvRgName) }`
- Module deployments can scope to different resource groups
- Existing modules (`storage-key.bicep`, `storage-rbac.bicep`) already implement this pattern

**Decision**: Reuse existing cross-RG module pattern from `bicep/modules/storage.bicep`  
**Rationale**: Pattern already tested and working in codebase  
**Alternatives Considered**: Inline resources (rejected - less maintainable), separate deployments (rejected - more complex orchestration)

**Source**: Existing codebase at `bicep/modules/storage.bicep`

---

### 5. Enabling CMK on Existing Storage Account

**Task**: Determine if CMK can be enabled on existing storage account or requires recreation

**Findings**:
- CMK can be enabled on existing storage accounts (no recreation needed)
- Use `Microsoft.Storage/storageAccounts@2023-01-01` with encryption properties
- Must first assign managed identity to storage account
- Then update encryption configuration with key vault reference

**Decision**: Update existing storage account in-place via Bicep  
**Rationale**: Avoids data migration and downtime; supported by Azure  
**Alternatives Considered**: Recreate storage account (rejected - unnecessary, causes data loss)

**Source**: [Configure CMK for existing storage account](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-configure-existing-account)

---

## Summary of Decisions

| Topic | Decision | Key Rationale |
|-------|----------|---------------|
| Key Type | RSA 4096-bit | Strongest security, fully supported |
| RBAC Role | Key Vault Crypto Service Encryption User | Least privilege, Microsoft-recommended |
| Identity Type | User-assigned managed identity | Explicit control, pre-configurable RBAC |
| Rotation Policy | 18 months (P18M), 2-year expiry | Exceeds Microsoft minimum recommendation |
| Update Pattern | In-place CMK enablement | No data migration needed |
| Bicep Pattern | Cross-RG existing resources | Reuses proven codebase patterns |

## Outstanding Questions

None - all technical unknowns resolved.
