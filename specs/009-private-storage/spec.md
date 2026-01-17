# Feature Specification: Private Azure Storage Account Infrastructure

**Feature Branch**: `009-private-storage`  
**Created**: 2026-01-17  
**Status**: Draft  
**Input**: User description: "Deploy a Private Azure Storage Account with private endpoint connectivity, RBAC authorization, and DNS integration for secure blob storage accessible only via VPN"

## Background

Storage accounts are currently deployed as part of solution projects (e.g., 005-storage-cmk combines storage with customer-managed key encryption). This creates unnecessary coupling and complexity. Following the Key Vault pattern, this specification creates a standalone foundational Storage Account infrastructure that other projects can consume.

This enables:
1. **Separation of concerns** - Base storage infrastructure vs encryption/CMK configuration
2. **Reusability** - Multiple solution projects can reference the same storage account
3. **Simplified testing** - Storage connectivity can be validated independently of CMK

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Private Storage Account (Priority: P1)

As an infrastructure engineer, I need to deploy an Azure Storage Account with private endpoint connectivity, RBAC authorization, and integration with the existing private DNS infrastructure, so that blob storage is centrally managed with no public network exposure.

**Why this priority**: This is the foundation for secure data storage. All AI lab projects that need blob storage (data files, backups, artifacts) depend on having a secure storage account available. Without private endpoint access, data is exposed over public network.

**Independent Test**: Can be fully tested by deploying the Storage Account Bicep module to a dedicated resource group (\`rg-ai-storage\`), verifying private endpoint is created and connected to the shared services VNet, confirming public access is disabled, and validating DNS resolution from VPN clients. Delivers a complete, secure storage account.

**Acceptance Scenarios**:

1. **Given** Storage Account Bicep module exists, **When** deploying to Azure, **Then** Storage Account is created in resource group \`rg-ai-storage\` with RBAC authorization (shared key access disabled)
2. **Given** Storage Account is deployed, **When** checking network configuration, **Then** public network access is disabled and private endpoint exists
3. **Given** private endpoint is configured, **When** connecting from VPN client, **Then** Storage Account is accessible via private DNS resolution (privatelink.blob.core.windows.net)
4. **Given** Storage Account is operational, **When** attempting access from public internet, **Then** access is denied/blocked
5. **Given** Storage Account module is deployed, **When** reviewing configuration, **Then** TLS 1.2 minimum is enforced and secure transfer required

---

### User Story 2 - Manage Blob Data via CLI (Priority: P2)

As a developer, I need to create containers and upload/download blobs in the private Storage Account using Azure CLI from a VPN-connected client, so that data can be managed securely for lab projects.

**Why this priority**: Enables the primary use case of data storage. Essential for operational functionality but depends on Storage Account infrastructure being in place first.

**Independent Test**: Can be tested by connecting via VPN and running \`az storage container create\` and \`az storage blob upload\` to store data, then \`az storage blob download\` to verify retrieval. Validates end-to-end data operations.

**Acceptance Scenarios**:

1. **Given** VPN connection is established and user has Storage Blob Data Contributor role, **When** creating a container via Azure CLI, **Then** container is successfully created
2. **Given** container exists, **When** uploading a blob via Azure CLI with \`--auth-mode login\`, **Then** blob is successfully stored
3. **Given** blob is stored, **When** listing blobs, **Then** uploaded blob appears with correct metadata
4. **Given** blob is in storage, **When** downloading via Azure CLI, **Then** download succeeds and file contents match original

---

### User Story 3 - Integrate with Existing Infrastructure (Priority: P3)

As an infrastructure engineer, I need the Storage Account module to follow the same deployment patterns as Key Vault and other infrastructure projects (parameterized Bicep, RBAC scripts, validation scripts), so that infrastructure management is consistent across all modules.

**Why this priority**: Ensures maintainability and consistency. Important for long-term management but can be validated after storage is operational.

**Independent Test**: Can be tested by reviewing Bicep module structure, parameter file patterns, and running validation scripts. Validates consistent infrastructure-as-code patterns.

**Acceptance Scenarios**:

1. **Given** Storage Account Bicep module exists, **When** reviewing file structure, **Then** module follows same pattern as key-vault.bicep (bicep/modules/storage-account.bicep)
2. **Given** parameter files exist, **When** reviewing contents, **Then** no secrets are hardcoded
3. **Given** Storage Account module is ready for deployment, **When** running what-if validation, **Then** expected resources are shown correctly
4. **Given** module is deployed, **When** running idempotency test (redeploy), **Then** no unexpected changes are made

---

### Edge Cases

- **Storage account name collision**: Storage account names are globally unique; use naming pattern with unique suffix to avoid collision
- **RBAC permission errors during deployment**: Deployment script checks permissions pre-flight and fails fast with clear error message
- **Private DNS zone link failure**: Validation script checks DNS zone existence in rg-ai-core; deployment fails with actionable error if zone missing
- **Private endpoint creation timeout**: Azure default timeout (10 min); script reports provisioning status and suggests retry
- **Shared key access attempts**: Shared key access is disabled; only Azure AD authentication works

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a Bicep deployment at \`bicep/storage-infra/main.bicep\` for orchestrating Storage Account deployment
- **FR-002**: System MUST provide a reusable module at \`bicep/modules/storage-account.bicep\` for Storage Account resource
- **FR-003**: Storage Account MUST be deployed to a dedicated resource group \`rg-ai-storage\` (following project separation pattern)
- **FR-004**: Storage Account MUST have public network access disabled to enforce private-only access
- **FR-005**: Storage Account MUST have shared key access disabled (RBAC-only authentication)
- **FR-006**: Storage Account MUST use TLS 1.2 minimum and require secure transfer
- **FR-007**: Storage Account MUST be accessible via private endpoint integrated with the shared services VNet (\`PrivateEndpointSubnet\` in \`vnet-ai-shared\`)
- **FR-008**: Private endpoint MUST resolve to private IP via the existing \`privatelink.blob.core.windows.net\` DNS zone in \`rg-ai-core\`
- **FR-009**: Module MUST use Standard_LRS tier (cost-effective for lab; configurable for production)
- **FR-010**: Deployment scripts MUST follow patterns from \`deploy-keyvault.sh\` (what-if, validation, outputs)
- **FR-011**: Documentation MUST be provided at \`docs/storage-infra/README.md\` following existing doc patterns

### Non-Functional Requirements

- **NFR-001**: Blob operations MUST complete within standard Azure SLA (validated via client-side timing)
- **NFR-002**: Module deployment time MUST be < 3 minutes (validated via deploy script timing)
- **NFR-003**: Private endpoint DNS resolution MUST complete within 100ms from VPN clients
- **NFR-004**: Documentation MUST clearly specify RBAC permissions required for deployment and operations

### Security Requirements

- **SR-001**: Public network access MUST be disabled and documented
- **SR-002**: Shared key access MUST be disabled (Azure AD authentication only)
- **SR-003**: TLS 1.2 minimum MUST be enforced
- **SR-004**: Secure transfer (HTTPS) MUST be required
- **SR-005**: Blob soft-delete SHOULD be configurable (enabled by default, 7-day retention)
- **SR-006**: All access MUST be audited via Azure activity logs

## Key Entities

### Storage Account Resource
- **Name**: \`stailab<suffix>\` (globally unique, 3-24 characters, lowercase alphanumeric only; suffix ensures uniqueness)
- **Type**: Microsoft.Storage/storageAccounts
- **Naming Strategy**: Include unique suffix (e.g., MMDD or 4-character) to ensure global uniqueness
- **Properties**:
  - SKU: Standard_LRS (configurable)
  - Kind: StorageV2
  - Access Tier: Hot
  - Shared key access: Disabled
  - Public network access: Disabled
  - Minimum TLS: 1.2
  - Secure transfer: Required

### Private Endpoint Resource
- **Name**: \`stailab<suffix>-pe\`
- **Type**: Microsoft.Network/privateEndpoints
- **Properties**:
  - Target: Storage Account blob subresource
  - Subnet: PrivateEndpointSubnet (10.1.0.0/26)
  - DNS zone group: privatelink.blob.core.windows.net

### Resource Group
- **Name**: \`rg-ai-storage\`
- **Location**: Same as core infrastructure (eastus2)
- **Tags**: Standard project tags (environment, owner, purpose, deployedBy)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Storage Account is accessible only via private endpoint (public access returns connection refused)
- **SC-002**: DNS query for \`<account>.blob.core.windows.net\` from VPN client resolves to private IP (10.1.0.x)
- **SC-003**: Blob CRUD operations complete successfully via Azure CLI from VPN-connected client
- **SC-004**: Deployment completes in under 3 minutes with idempotent redeployment
- **SC-005**: Storage Account appears as infrastructure project in main README (after Key Vault)

## Assumptions

- Core infrastructure (vWAN, VPN, shared services VNet, private DNS zones) is already deployed
- Private DNS zone \`privatelink.blob.core.windows.net\` exists in \`rg-ai-core\` (created by core deployment)
- Deploying user has Contributor role on subscription and Network Contributor on shared VNet
- This is base storage infrastructure; CMK encryption is a separate concern (005-storage-cmk will be refactored)

## Clarifications

### Session 2026-01-17

- **Q1: Resource Group Naming** → A: Use `rg-ai-storage` (same name as 005-storage-cmk). This becomes the base infrastructure; 005-storage-cmk will be refactored later to add CMK on top.
- **Q2: Storage Account Naming Pattern** → A: Use `stailab<MMDD>` (date-based, e.g., `stailab0117`). Matches Key Vault pattern, human-readable.
- **Q3: Module Approach** → C: Replace existing `storage.bicep` entirely with new clean base module. Breaks existing CMK functionality - CMK is not part of base install and will be refactored separately later.
