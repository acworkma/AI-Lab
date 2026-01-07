# Feature Specification: Private Azure Storage with Customer Managed Key

**Feature Branch**: `005-storage-cmk`  
**Created**: 2026-01-07  
**Status**: Draft  
**Input**: User description: "Deploy a Customer Managed Key stored in KeyVault on an Azure Storage account with a private endpoint on the previously built Azure network."

## Clarifications

### Session 2026-01-07
- Q: Storage Account tier preference → A: **Standard_LRS** (lab environment, cost-effective)
- Q: Include file share endpoints in MVP → A: **Blob only** (MVP focus, file shares deferred)
- Q: Resource group scope → A: **Separate `rg-ai-storage`** (dedicated RG, matches project pattern)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Private Storage Account with CMK (Priority: P1)

As an infrastructure engineer, I need to deploy an Azure Storage Account with customer-managed key (CMK) encryption using a key stored in the core Key Vault, integrated with a private endpoint on the existing vWAN infrastructure, so that sensitive data is encrypted with organizational control over encryption keys.

**Why this priority**: This is the foundation for secure data storage with customer-managed encryption. Without CMK, encryption keys are managed by Azure, limiting organizational control over data security. Private endpoint access ensures storage is only accessible via the VPN.

**Independent Test**: Can be fully tested by deploying the Storage Account Bicep module to a dedicated resource group, verifying CMK encryption is enabled with a Key Vault key, confirming private endpoint is created and connected to the shared services VNet, and validating public access is disabled. Delivers a complete, secure storage account.

**Acceptance Scenarios**:

1. **Given** Storage Account Bicep module exists, **When** deploying to Azure, **Then** Storage Account is created with appropriate SKU and type (StorageV2, etc.)
2. **Given** Storage Account is deployed, **When** checking encryption configuration, **Then** customer-managed key encryption is enabled and key references the core Key Vault
3. **Given** private endpoint is configured, **When** connecting from VPN client, **Then** Storage Account is accessible via private DNS resolution (privatelink.blob.core.windows.net)
4. **Given** Storage Account is operational, **When** attempting access from public internet, **Then** public network access is denied/blocked
5. **Given** Storage Account module is deployed, **When** reviewing configuration, **Then** RBAC roles are properly configured with no shared access keys enabled

---

### User Story 2 - Manage Storage Account Data (Priority: P2)

As a developer, I need to upload, download, and manage data in the private storage account using the Azure CLI or SDKs from a VPN-connected client, so that data operations work seamlessly over the private connection without requiring public internet access.

**Why this priority**: Enables the primary use case of storing and retrieving data securely. Essential for operational functionality but depends on Storage Account infrastructure being in place first.

**Independent Test**: Can be tested by connecting via VPN and running `az storage blob upload` to upload a file, then `az storage blob download` to verify retrieval. Validates end-to-end data operations.

**Acceptance Scenarios**:

1. **Given** VPN connection is established and user has Storage Account access rights, **When** uploading a file via Azure CLI, **Then** file is successfully stored in a blob container
2. **Given** file is stored in Storage Account, **When** listing blobs, **Then** uploaded file appears with correct metadata
3. **Given** file is in Storage Account, **When** downloading via Azure CLI, **Then** download succeeds and file contents match original
4. **Given** Storage Account operations complete, **When** checking audit logs, **Then** operations are logged with proper identity information

---

### User Story 3 - Integrate with Existing Infrastructure (Priority: P3)

As an infrastructure engineer, I need the Storage Account module to follow the same deployment patterns as the vWAN core infrastructure (parameterized Bicep, Key Vault references, RBAC, validation scripts), so that infrastructure management is consistent across all modules.

**Why this priority**: Ensures maintainability and consistency but doesn't block core Storage functionality. Can be added incrementally after basic deployment works.

**Independent Test**: Can be tested by reviewing Bicep module structure, parameter file patterns, and running validation scripts. Delivers consistent infrastructure-as-code patterns.

**Acceptance Scenarios**:

1. **Given** Storage Account Bicep module exists, **When** reviewing file structure, **Then** module follows same pattern as existing modules (e.g., `bicep/modules/storage.bicep`)
2. **Given** parameter files exist, **When** reviewing contents, **Then** no secrets are hardcoded and Key Vault references are used
3. **Given** Storage Account module is ready for deployment, **When** running what-if validation, **Then** expected resources are shown correctly
4. **Given** module is deployed, **When** running idempotency test (redeploy), **Then** no unexpected changes are made

---

### Edge Cases

- What happens if the Key Vault key is deleted or rotated while Storage Account is in use?
- How does the system handle failures during private endpoint creation?
- What if user lacks sufficient RBAC permissions for Storage operations (Storage Blob Data Contributor)?
- How to handle network isolation issues if private endpoint fails to resolve DNS?
- What if the managed identity used for CMK doesn't have proper Key Vault access?
- How does CMK encryption impact backup and disaster recovery operations?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a reusable Bicep module at `bicep/modules/storage.bicep` for Azure Storage Account deployment
- **FR-002**: Storage Account MUST be deployed to a dedicated resource group (e.g., `rg-ai-storage`) to maintain separation of concerns
- **FR-003**: Storage Account MUST use StorageV2 SKU with Standard_LRS tier (cost-effective for lab environment)
- **FR-004**: Storage Account MUST have public network access disabled to enforce private-only access
- **FR-005**: Storage Account MUST use customer-managed key (CMK) encryption with key stored in the core Key Vault (`kv-ai-core-*`)
- **FR-006**: Storage Account MUST use managed identity for accessing the encryption key (no shared keys)
- **FR-007**: Storage Account MUST be accessible via private endpoint integrated with the shared services VNet (10.1.0.0/24)
- **FR-008**: Storage Account MUST use RBAC authorization (shared access signatures disabled, if possible)
- **FR-009**: Private endpoint MUST resolve to private IP via the existing `privatelink.blob.core.windows.net` DNS zone
- **FR-010**: Module MUST support blob storage private endpoint; file share endpoints deferred to future iteration

### Non-Functional Requirements

- **NFR-001**: Storage Account encryption must not impact performance (CMK lookups should be cached by Azure)
- **NFR-002**: Module deployment time must be < 5 minutes
- **NFR-003**: Private endpoint DNS resolution must complete within 100ms from VPN clients
- **NFR-004**: Documentation must clearly specify RBAC permissions required for deployment and operations

### Security Requirements

- **SR-001**: All encryption keys MUST be stored in the core Key Vault with proper access controls
- **SR-002**: Managed identity used for CMK access MUST have minimal required permissions (Key Vault Crypto User role)
- **SR-003**: Public network access MUST be explicitly disabled and documented
- **SR-004**: Shared access keys (connection strings) MUST NOT appear in deployment outputs
- **SR-005**: All access to storage must be audited via Azure Monitor/Log Analytics

## Key Entities

### Storage Account Resource
- **Name**: `stai<environment><unique>` (globally unique, 3-24 characters)
- **Type**: Microsoft.Storage/storageAccounts
- **Properties**:
  - Kind: StorageV2 (supports blob, file, queue, table)
  - SKU: Standard_LRS (or Premium_LRS for performance)
  - Encryption: Customer-managed key from Key Vault
  - Public network access: Disabled
  - RBAC: Enabled
  - Shared access keys: Disabled (if possible per requirements)

### Managed Identity
- **Purpose**: Service principal for Storage Account to access encryption key
- **Type**: User-assigned or system-assigned
- **Role**: Key Vault Crypto User (minimal required for CMK)

### Private Endpoint
- **Name**: `pe-storage-blob`
- **Target**: Storage Account (blob service)
- **Subnet**: PrivateEndpointSubnet in shared services VNet
- **DNS Integration**: privatelink.blob.core.windows.net zone

### Key Vault Key (from core infrastructure)
- **Name**: `storage-encryption-key`
- **Type**: RSA 4096
- **Rotation**: Annual or per organizational policy
- **Access**: Limited to Storage Account managed identity

## Assumptions

1. Core infrastructure (vWAN hub, shared services VNet, Key Vault, DNS zones) is already deployed
2. User has Contributor or Owner role on the subscription
3. Key Vault is in the same subscription and region as Storage Account
4. Private endpoint subnet has available IP addresses
5. DNS zones for privatelink.blob.core.windows.net are already created and linked to shared VNet
6. Deployment is into the same subscription as core infrastructure (no cross-subscription scenarios initially)

## Success Criteria

1. **SC-001**: Storage Account created with CMK encryption enabled
2. **SC-002**: Encryption key is stored in core Key Vault
3. **SC-003**: Managed identity has proper permissions to access encryption key
4. **SC-004**: Private endpoint created and connected to shared services VNet
5. **SC-005**: Private endpoint resolves to private IP (10.x.x.x) via DNS
6. **SC-006**: Public network access is disabled (403 Forbidden from internet)
7. **SC-007**: VPN-connected client can upload and download files without issues
8. **SC-008**: All operations are audited in Azure Monitor
9. **SC-009**: Idempotent redeployment succeeds without unexpected changes
