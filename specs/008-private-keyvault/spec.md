# Feature Specification: Private Azure Key Vault Infrastructure

**Feature Branch**: `008-private-keyvault`  
**Created**: 2025-01-17  
**Status**: Draft  
**Input**: User description: "Deploy Azure Key Vault with private endpoint, RBAC authorization, and proper DNS integration for secure secrets management across all AI lab projects"

## Background

Key Vault was previously included in the core infrastructure deployment but had two critical issues:
1. **No private endpoint** - Key Vault was deployed with public network access
2. **Deployed in core** - Violated separation of concerns; other resources (storage, ACR, APIM) have dedicated resource groups

This specification creates Key Vault as a standalone infrastructure project following the established patterns from storage, ACR, and APIM deployments.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Private Key Vault (Priority: P1)

As an infrastructure engineer, I need to deploy an Azure Key Vault with private endpoint connectivity, RBAC authorization, and integration with the existing private DNS infrastructure, so that secrets are centrally managed with no public network exposure.

**Why this priority**: This is the foundation for secure secrets management. All other AI lab projects that need secrets (storage CMK keys, connection strings, certificates) depend on having a secure Key Vault available. Without private endpoint access, secrets are exposed over public network.

**Independent Test**: Can be fully tested by deploying the Key Vault Bicep module to a dedicated resource group (\`rg-ai-keyvault\`), verifying private endpoint is created and connected to the shared services VNet, confirming public access is disabled, and validating DNS resolution from VPN clients. Delivers a complete, secure Key Vault.

**Acceptance Scenarios**:

1. **Given** Key Vault Bicep module exists, **When** deploying to Azure, **Then** Key Vault is created in resource group \`rg-ai-keyvault\` with RBAC authorization enabled
2. **Given** Key Vault is deployed, **When** checking network configuration, **Then** public network access is disabled and private endpoint exists
3. **Given** private endpoint is configured, **When** connecting from VPN client, **Then** Key Vault is accessible via private DNS resolution (privatelink.vaultcore.azure.net)
4. **Given** Key Vault is operational, **When** attempting access from public internet, **Then** access is denied/blocked
5. **Given** Key Vault module is deployed, **When** reviewing configuration, **Then** RBAC authorization is enabled (not access policies) and soft-delete is enabled

---

### User Story 2 - Manage Secrets via CLI (Priority: P2)

As a developer, I need to create, read, update, and delete secrets in the private Key Vault using Azure CLI from a VPN-connected client, so that secrets can be managed securely for lab projects.

**Why this priority**: Enables the primary use case of secrets management. Essential for operational functionality but depends on Key Vault infrastructure being in place first.

**Independent Test**: Can be tested by connecting via VPN and running \`az keyvault secret set\` to store a secret, then \`az keyvault secret show\` to verify retrieval. Validates end-to-end secrets operations.

**Acceptance Scenarios**:

1. **Given** VPN connection is established and user has Key Vault Secrets Officer role, **When** creating a secret via Azure CLI, **Then** secret is successfully stored
2. **Given** secret is stored in Key Vault, **When** listing secrets, **Then** secret name appears (value is not exposed)
3. **Given** secret is in Key Vault, **When** retrieving via Azure CLI, **Then** secret value is returned
4. **Given** secret operations complete, **When** checking Azure activity logs, **Then** operations are logged with proper identity information

---

### User Story 3 - Bicep Reference Integration (Priority: P3)

As an infrastructure engineer, I need other Bicep deployments (storage, APIM, etc.) to reference secrets from this Key Vault using parameter file Key Vault references, so that sensitive configuration values are never stored in source control.

**Why this priority**: Ensures integration with other lab projects. Important for security but can be validated after Key Vault is operational.

**Independent Test**: Can be tested by creating a parameter file with Key Vault reference syntax and deploying a resource that uses the referenced secret. Validates Bicep integration.

**Acceptance Scenarios**:

1. **Given** Key Vault contains a secret, **When** referencing it in a Bicep parameter file using Key Vault reference syntax, **Then** deployment successfully retrieves the secret value
2. **Given** Key Vault reference is used in deployment, **When** reviewing deployment logs, **Then** actual secret value is never logged
3. **Given** documentation exists, **When** reviewing parameter file patterns, **Then** clear examples of Key Vault reference syntax are provided

---

### Edge Cases

- **Soft-deleted vault collision**: Avoided by using unique suffix in vault name (see Clarifications)
- **RBAC permission errors during deployment**: Deployment script checks permissions pre-flight and fails fast with clear error message listing required roles (Contributor on subscription, Network Contributor on VNet)
- **Private DNS zone link failure**: Validation script checks DNS zone existence in rg-ai-core; deployment fails with actionable error if zone missing
- **Private endpoint creation timeout**: Azure default timeout (10 min); script reports provisioning status and suggests retry or manual investigation via Azure Portal
- **Missing Network Contributor role**: Pre-deployment validation checks subnet access; fails with required role assignment command example
- **Soft-delete redeployment collision**: Date-based suffix (MMDD) ensures unique names; for same-day redeploy, manually specify different suffix via parameter

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a Bicep deployment at \`bicep/keyvault/main.bicep\` for orchestrating Key Vault deployment
- **FR-002**: System MUST provide a reusable module at \`bicep/modules/key-vault.bicep\` for Key Vault resource
- **FR-003**: Key Vault MUST be deployed to a dedicated resource group \`rg-ai-keyvault\` (following project separation pattern)
- **FR-004**: Key Vault MUST have public network access disabled to enforce private-only access
- **FR-005**: Key Vault MUST use RBAC authorization (not legacy access policies)
- **FR-006**: Key Vault MUST have soft-delete enabled with 90-day retention
- **FR-007**: Key Vault MUST be accessible via private endpoint integrated with the shared services VNet (\`snet-private-endpoints\` in \`vnet-ai-shared\`)
- **FR-008**: Private endpoint MUST resolve to private IP via the existing \`privatelink.vaultcore.azure.net\` DNS zone in \`rg-ai-core\`
- **FR-009**: Module MUST use Standard SKU (Premium deferred unless HSM-backed keys required)
- **FR-010**: Deployment scripts MUST follow patterns from \`deploy-storage.sh\` (what-if, validation, outputs)
- **FR-011**: Documentation MUST be provided at \`docs/keyvault/README.md\` following existing doc patterns

### Non-Functional Requirements

- **NFR-001**: Key Vault operations MUST complete within 100ms (standard Azure SLA; validated via client-side timing)
- **NFR-002**: Module deployment time MUST be < 3 minutes (validated via deploy script timing)
- **NFR-003**: Private endpoint DNS resolution MUST complete within 100ms from VPN clients
- **NFR-004**: Documentation MUST clearly specify RBAC permissions required for deployment and operations

### Security Requirements

- **SR-001**: Public network access MUST be disabled and documented
- **SR-002**: RBAC authorization MUST be used instead of legacy access policies
- **SR-003**: Soft-delete MUST be enabled to protect against accidental deletion
- **SR-004**: Purge protection SHOULD be configurable (disabled for dev/lab, enabled for prod)
- **SR-005**: Key Vault URI and name MUST NOT expose internal naming conventions
- **SR-006**: All access MUST be audited via Azure diagnostic logs
  - *Lab scope*: Diagnostic settings deferred to future iteration; Azure activity logs provide basic audit trail

## Key Entities

### Key Vault Resource
- **Name**: `kv-ai-lab-<suffix>` (globally unique, 3-24 characters, alphanumeric and hyphens; suffix ensures no collision with soft-deleted vaults)
- **Type**: Microsoft.KeyVault/vaults
- **Naming Strategy**: Include unique suffix (e.g., 4-character hash or deployment date) to avoid collision with soft-deleted vaults that cannot be purged
- **Properties**:
  - SKU: Standard (Premium if HSM required)
  - RBAC authorization: Enabled
  - Soft-delete: Enabled (90 days)
  - Purge protection: Configurable (default: disabled for lab)
  - Public network access: Disabled
  - Private endpoint: Connected to snet-private-endpoints

### Private Endpoint Resource
- **Name**: \`kv-ai-<unique>-pe\`
- **Type**: Microsoft.Network/privateEndpoints
- **Properties**:
  - Target: Key Vault resource
  - Subnet: snet-private-endpoints (10.1.0.0/26)
  - DNS zone group: privatelink.vaultcore.azure.net

### Resource Group
- **Name**: \`rg-ai-keyvault\`
- **Location**: Same as core infrastructure (eastus2)
- **Tags**: Standard project tags (environment, owner, purpose, deployedBy)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Key Vault is accessible only via private endpoint (public access returns connection refused)
- **SC-002**: DNS query for \`<vault-name>.vault.azure.net\` from VPN client resolves to private IP (10.1.0.x)
- **SC-003**: Secret CRUD operations complete successfully via Azure CLI from VPN-connected client
- **SC-004**: Deployment completes in under 3 minutes with idempotent redeployment
- **SC-005**: Other projects (storage CMK, APIM) can reference secrets via Bicep Key Vault references
- **SC-006**: Key Vault appears as first infrastructure project in main README

## Assumptions

- Core infrastructure (vWAN, VPN, shared services VNet, private DNS zones) is already deployed
- Private DNS zone \`privatelink.vaultcore.azure.net\` exists in \`rg-ai-core\` (created by core deployment)
- Deploying user has Contributor role on subscription and Network Contributor on shared VNet
- Lab environment uses Standard SKU; Premium/HSM deferred to future iteration
## Clarifications

### Session 2025-01-17

- Q: How should deployment handle soft-deleted vault name collisions? → A: Use unique suffix in vault name (e.g., `kv-ai-lab-<hash>`) to avoid collision