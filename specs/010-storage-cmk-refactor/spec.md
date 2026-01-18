# Feature Specification: Refactor Storage Account CMK Integration

**Feature Branch**: `010-storage-cmk-refactor`  
**Created**: 2026-01-17  
**Status**: Draft  
**Input**: User description: "Refactor the Solution Projects private storage account with CMK. Storage account and key vault have been moved to their own infrastructure. Validate storage and keyvault are deployed, create the RG and managed identity, and tie everything together."

## Background

The original 005-storage-cmk feature deployed everything in a monolithic pattern: resource group, managed identity, Key Vault key, storage account, private endpoint, and CMK encryption all in one deployment. This created tight coupling and complexity.

The infrastructure has since been refactored:
- **008-private-keyvault**: Deploys standalone Key Vault with private endpoint (`rg-ai-keyvault`)
- **009-private-storage**: Deploys standalone Storage Account with private endpoint (`rg-ai-storage`)

This feature (010) completes the separation by:
1. Validating prerequisite infrastructure is deployed
2. Creating the CMK encryption key in the existing Key Vault
3. Creating a managed identity for key access
4. Enabling CMK encryption on the existing Storage Account

## Microsoft Documentation Validation

Key choices in this specification were validated against official Microsoft Learn documentation:

| Choice | Validated | Source |
|--------|-----------|--------|
| RSA key sizes 2048, 3072, 4096 | ✅ | "Azure storage encryption supports RSA and RSA-HSM keys of sizes 2048, 3072 and 4096" |
| Key Vault Crypto Service Encryption User role | ✅ | Official role for managed identity CMK access - provides wrap/unwrap permissions |
| User-assigned managed identity | ✅ | Required for new storage accounts with CMK; recommended for existing accounts |
| Key rotation every 18 months (P18M) | ✅ | Microsoft example policy; recommends "at least every two years" |
| Key expiry 2 years (P2Y) | ✅ | Default in Microsoft ARM template examples |
| Soft-delete and purge protection required | ✅ | "Key vault must have both soft delete and purge protection enabled" |
| Versionless key URI for auto-rotation | ✅ | "Target services should use versionless key uri to automatically refresh" |

**Sources**: 
- [Customer-managed keys for Azure Storage encryption](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-overview)
- [Configure key auto-rotation in Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/keys/how-to-configure-key-rotation)
- [Configure CMK for existing storage account](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-configure-existing-account)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enable CMK on Existing Storage Account (Priority: P1)

As an infrastructure engineer, I need to enable customer-managed key encryption on an existing private Storage Account using a key stored in the existing private Key Vault, so that data is encrypted with organizational control over encryption keys while leveraging pre-deployed infrastructure.

**Why this priority**: This is the core value of the feature - adding CMK encryption as a layer on top of existing infrastructure. It validates the separation of concerns architecture works and enables secure key management.

**Independent Test**: Can be fully tested by running the CMK deployment against existing storage and keyvault infrastructure, verifying the encryption key is created in Key Vault, confirming managed identity has crypto permissions, and validating the storage account's encryption configuration shows CMK is active.

**Acceptance Scenarios**:

1. **Given** Key Vault is deployed in `rg-ai-keyvault`, **When** running CMK deployment, **Then** encryption key `storage-encryption-key` is created in the Key Vault
2. **Given** Storage Account is deployed in `rg-ai-storage`, **When** running CMK deployment, **Then** Storage Account encryption is updated to use the Key Vault key
3. **Given** CMK deployment completes, **When** checking Storage Account encryption configuration, **Then** keySource shows "Microsoft.Keyvault" and key references the created key
4. **Given** CMK is enabled, **When** uploading a blob via VPN, **Then** operation succeeds and data is encrypted with the customer-managed key

---

### User Story 2 - Validate Prerequisites Before Deployment (Priority: P2)

As an infrastructure engineer, I need the CMK deployment to validate that the required Key Vault and Storage Account infrastructure are deployed before attempting to enable CMK, so that I get clear error messages if prerequisites are missing rather than cryptic deployment failures.

**Why this priority**: Improves the deployment experience and reduces troubleshooting time. Depends on having the CMK integration capability first.

**Independent Test**: Can be tested by running the deployment validation script against environments with and without prerequisites, verifying appropriate success/error messages.

**Acceptance Scenarios**:

1. **Given** Key Vault exists in `rg-ai-keyvault`, **When** running prerequisite validation, **Then** Key Vault check passes with name displayed
2. **Given** Storage Account exists in `rg-ai-storage`, **When** running prerequisite validation, **Then** Storage Account check passes with name displayed
3. **Given** Key Vault does NOT exist, **When** running prerequisite validation, **Then** clear error message instructs to deploy Key Vault first
4. **Given** Storage Account does NOT exist, **When** running prerequisite validation, **Then** clear error message instructs to deploy Storage Account first

---

### User Story 3 - Manage Encryption Key Lifecycle (Priority: P3)

As a security administrator, I need to be able to rotate the encryption key and verify CMK status, so that encryption keys follow organizational security policies without requiring redeployment of storage infrastructure.

**Why this priority**: Important for long-term security compliance but not required for initial CMK enablement.

**Independent Test**: Can be tested by triggering a key rotation via Azure CLI or portal and verifying the storage account continues to operate correctly.

**Acceptance Scenarios**:

1. **Given** CMK is enabled on Storage Account, **When** rotating the Key Vault key, **Then** Storage Account automatically uses the new key version
2. **Given** CMK is enabled, **When** running validation script, **Then** current encryption key details are displayed including key version
3. **Given** Key Vault key is disabled, **When** attempting blob operations, **Then** operations are blocked (demonstrating key dependency)

---

### Edge Cases

- **Key Vault soft-deleted with same name**: Check for soft-deleted Key Vault with same name and provide clear guidance to purge or use different suffix
- **Storage Account already has CMK from different Key Vault**: Detect existing CMK configuration and warn before overwriting
- **Managed identity already exists**: Reuse existing managed identity if present rather than failing
- **Key Vault firewall blocks access**: Validate managed identity can access Key Vault before configuring CMK
- **Insufficient permissions on Key Vault**: Check deployer has permission to create keys and role assignments before proceeding

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a Bicep deployment at `bicep/storage/main.bicep` that enables CMK on an existing Storage Account
- **FR-002**: Deployment MUST validate that Key Vault exists in `rg-ai-keyvault` before proceeding
- **FR-003**: Deployment MUST validate that Storage Account exists in `rg-ai-storage` before proceeding
- **FR-004**: System MUST create a user-assigned managed identity in the storage resource group (`rg-ai-storage`) for Key Vault access
- **FR-005**: System MUST create an RSA encryption key named `storage-encryption-key` in the existing Key Vault (RSA 4096-bit recommended; 2048, 3072 also supported)
- **FR-006**: System MUST assign the **Key Vault Crypto Service Encryption User** role to the managed identity on the Key Vault
- **FR-007**: System MUST update the Storage Account encryption configuration to use the Key Vault key (keySource: Microsoft.Keyvault)
- **FR-008**: System MUST configure the Storage Account with the user-assigned managed identity for key access
- **FR-009**: Validation script `validate-storage.sh` MUST check CMK encryption status and key details
- **FR-010**: Deployment scripts MUST follow existing patterns (`deploy-storage.sh` with what-if, validation)

### Non-Functional Requirements

- **NFR-001**: CMK encryption MUST NOT add perceptible latency to blob operations (Azure caches decryption keys)
- **NFR-002**: Deployment time MUST be < 3 minutes (key creation and role assignment are fast operations)
- **NFR-003**: Documentation MUST be updated at `docs/storage/README.md` to reflect the refactored architecture

### Security Requirements

- **SR-001**: Encryption key MUST be RSA 2048, 3072, or 4096-bit stored in Key Vault (per Azure Storage CMK requirements)
- **SR-002**: Managed identity MUST have minimal permissions (**Key Vault Crypto Service Encryption User** role only)
- **SR-003**: Key MUST have auto-rotation policy configured (Microsoft recommends at least every 2 years; default: 18 months with 2-year expiry)
- **SR-004**: Existing storage security properties MUST be preserved (private endpoint, RBAC-only, TLS 1.2)
- **SR-005**: Key Vault MUST have soft-delete and purge protection enabled (required for CMK)

## Key Entities

### Managed Identity
- **Name**: `id-stailab<suffix>-cmk` (derived from storage account name)
- **Type**: User-assigned managed identity
- **Location**: Same resource group as Storage Account (`rg-ai-storage`)
- **Role**: Key Vault Crypto Service Encryption User on Key Vault

### Encryption Key
- **Name**: `storage-encryption-key`
- **Type**: RSA (2048, 3072, or 4096-bit - Azure Storage supports all three)
- **Location**: Existing Key Vault in `rg-ai-keyvault`
- **Rotation Policy**: Auto-rotation every 18 months (P18M) with 2-year expiry (P2Y), per Microsoft best practices
- **Access**: Limited to Storage Account managed identity via Key Vault Crypto Service Encryption User role

### Storage Account (existing)
- **Location**: `rg-ai-storage` (deployed by 009-private-storage)
- **Update Required**: Add user-assigned identity and update encryption configuration

### Key Vault (existing)
- **Location**: `rg-ai-keyvault` (deployed by 008-private-keyvault)
- **Update Required**: Add encryption key (no changes to Key Vault itself)

## Assumptions

1. Key Vault is deployed via `008-private-keyvault` and accessible from the shared VNet
2. Storage Account is deployed via `009-private-storage` with RBAC-only authentication
3. Both Key Vault and Storage Account are in the same subscription and region
4. Private DNS zones are properly configured for both services
5. Deployer has Contributor role on both resource groups and permissions to create role assignments
6. The storage account name follows the pattern `stailab<suffix>` established by 009-private-storage

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Storage Account encryption configuration shows `keySource: Microsoft.Keyvault` after deployment
- **SC-002**: Encryption key `storage-encryption-key` exists in Key Vault with correct properties (RSA 4096, rotation policy)
- **SC-003**: Managed identity has Key Vault Crypto Service Encryption User role assigned
- **SC-004**: Blob operations (upload/download) continue to work via VPN after CMK is enabled
- **SC-005**: Validation script outputs CMK status, key URI, and key version
- **SC-006**: Deployment is idempotent (rerunning produces no unexpected changes)
