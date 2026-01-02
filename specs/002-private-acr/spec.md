# Feature Specification: Private Azure Container Registry Module

**Feature Branch**: `002-private-acr`  
**Created**: 2026-01-02  
**Status**: Draft  
**Input**: User description: "We are going to build our second module for our lab. It will be an Azure Container Registry. It needs to be private following the principals we built in core"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Private ACR Infrastructure (Priority: P1)

As an infrastructure engineer, I need to deploy a private Azure Container Registry as a reusable Bicep module that integrates with the existing vWAN hub infrastructure, so that container images can be stored and accessed privately within the Azure environment.

**Why this priority**: This is the foundation for container-based workloads in the lab environment. Without ACR, no container images can be stored privately, forcing reliance on public registries which violates the private infrastructure principles.

**Independent Test**: Can be fully tested by deploying the ACR Bicep module to the `rg-ai-core` resource group, verifying the ACR resource is created with private networking, and confirming it's accessible only through the vWAN/VPN infrastructure. Delivers a complete, functional private container registry ready for image storage.

**Acceptance Scenarios**:

1. **Given** ACR Bicep module exists, **When** deploying to Azure, **Then** ACR is created in `rg-ai-core` with appropriate SKU (Standard or Premium)
2. **Given** ACR is deployed, **When** checking networking configuration, **Then** public network access is disabled and private endpoint is configured
3. **Given** private endpoint is configured, **When** connecting from VPN client, **Then** ACR is accessible via private DNS resolution
4. **Given** ACR is operational, **When** attempting access from public internet, **Then** access is denied/blocked
5. **Given** ACR module is deployed, **When** reviewing configuration, **Then** RBAC roles are properly configured (no admin user enabled)

---

### User Story 2 - Import Container Images (Priority: P2)

As an infrastructure engineer, I need to import container images from public registries (like GitHub Container Registry) into the private ACR, so that downstream services can access images without requiring public internet access during runtime.

**Why this priority**: Enables the primary use case of copying images from public sources into the private environment. Essential for operational functionality but depends on ACR infrastructure being in place first.

**Independent Test**: Can be tested by connecting via VPN and running `az acr import` to pull an image from a public registry (e.g., `ghcr.io`) into the private ACR. Delivers functional image import capability.

**Acceptance Scenarios**:

1. **Given** VPN connection is established and user has ACR push permissions, **When** running `az acr import` with public source image, **Then** image is successfully imported into private ACR
2. **Given** image import is complete, **When** listing ACR repositories, **Then** imported image appears with correct tag
3. **Given** image is in ACR, **When** attempting to pull image via `docker pull` using ACR URL, **Then** image pull succeeds from VPN-connected client
4. **Given** ACR has imported images, **When** checking image metadata, **Then** image layers and manifests are intact and match source

---

### User Story 3 - Integrate with Existing Infrastructure (Priority: P3)

As an infrastructure engineer, I need the ACR module to follow the same deployment patterns as the vWAN core infrastructure (parameterized Bicep, Key Vault references, validation scripts), so that infrastructure management is consistent across all modules.

**Why this priority**: Ensures maintainability and consistency but doesn't block core ACR functionality. Can be added incrementally after basic ACR deployment works.

**Independent Test**: Can be tested by reviewing Bicep module structure, parameter file patterns, and running validation scripts. Delivers consistent infrastructure-as-code patterns.

**Acceptance Scenarios**:

1. **Given** ACR Bicep module exists, **When** reviewing file structure, **Then** module follows same pattern as existing modules (e.g., `bicep/modules/acr.bicep`)
2. **Given** parameter files exist, **When** reviewing contents, **Then** no secrets are hardcoded and Key Vault references are used where appropriate
3. **Given** ACR module is ready for deployment, **When** running what-if validation, **Then** expected resources are shown with no surprises
4. **Given** module is deployed, **When** running idempotency test (redeploy), **Then** no changes are made and deployment succeeds

---

### Edge Cases

- What happens when ACR private endpoint fails to create but ACR resource succeeds?
- How does system handle DNS resolution failures from VPN clients trying to access ACR?
- What if image import fails partway through (network interruption, authentication timeout)?
- How to handle ACR name conflicts (globally unique namespace)?
- What if user lacks sufficient RBAC permissions for ACR operations (AcrPush, AcrPull)?
- How does ACR integration work if private endpoint is in a different VNet than the vWAN hub?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a reusable Bicep module at `bicep/modules/acr.bicep` for Azure Container Registry deployment
- **FR-002**: ACR MUST be deployed to `rg-ai-core` resource group (same as vWAN core infrastructure)
- **FR-003**: ACR MUST use Standard or Premium SKU (required for import functionality and private endpoints)
- **FR-004**: ACR MUST have public network access disabled to enforce private-only access
- **FR-005**: ACR MUST be accessible via private endpoint integrated with the vWAN infrastructure
- **FR-006**: ACR MUST use RBAC authorization (admin user disabled)
- **FR-007**: ACR MUST have private DNS zone configured for name resolution from VPN clients
- **FR-008**: System MUST support importing container images from public registries (GitHub Container Registry, Docker Hub, etc.)
- **FR-009**: ACR configuration MUST follow the same Bicep parameterization pattern as vWAN core modules
- **FR-010**: Deployment MUST be idempotent and safe to run multiple times
- **FR-011**: ACR name MUST follow naming conventions and be globally unique across Azure
- **FR-012**: ACR MUST have appropriate Azure tags (environment, purpose, owner) consistent with core infrastructure
- **FR-013**: System MUST integrate with existing Key Vault for storing any ACR-related credentials or secrets
- **FR-014**: ACR MUST support image retention policies to manage storage costs

### Key Entities

- **Azure Container Registry**: Private container image registry, stores Docker/OCI images and artifacts, accessible only via private endpoint from vWAN-connected clients
- **Private Endpoint**: Network interface that connects ACR to the private virtual network, enables private IP access within Azure backbone
- **Private DNS Zone**: DNS configuration for `privatelink.azurecr.io` that resolves ACR FQDN to private endpoint IP address
- **Container Image**: OCI-compliant container image stored in ACR repositories, imported from public registries for private use
- **RBAC Roles**: Azure role assignments (AcrPush for import operations, AcrPull for image consumption) that control access to ACR operations

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Infrastructure engineer can deploy private ACR from Bicep module in under 15 minutes
- **SC-002**: VPN-connected users can successfully import container images from public registries using `az acr import` in under 5 minutes per image
- **SC-003**: ACR is completely inaccessible from public internet (0% success rate on public access attempts)
- **SC-004**: Private DNS resolution for ACR hostname resolves to private IP address from VPN clients 100% of the time
- **SC-005**: Container image pulls from private ACR succeed for authenticated users with 99.9% reliability
- **SC-006**: ACR deployment follows same infrastructure patterns as core modules with 100% consistency (parameterization, validation, documentation)
- **SC-007**: Image import operations complete without data loss or corruption (image digest verification passes 100% of the time)

## Assumptions

- ACR will be deployed in the same Azure region as the vWAN hub to minimize latency and simplify private endpoint configuration
- Private endpoint will use a dedicated subnet within the vWAN hub's address space or connect to the hub via virtual network peering
- Image imports will be infrequent and manually triggered (not automated scheduled imports)
- Storage requirements are modest enough that Standard or Premium SKU geo-replication is not initially required
- Users performing ACR operations will connect via VPN and have appropriate Azure RBAC permissions assigned
- DNS resolution for private endpoint will leverage Azure Private DNS zones with automatic registration
- Initial image imports will be from public registries only (no authentication required at source)
- ACR will use the default content trust and vulnerability scanning settings without immediate customization
- Bandwidth for image imports is sufficient over VPN connection for typical container image sizes (< 5 GB per image)

## Dependencies

- **Virtual WAN Core Infrastructure**: ACR private endpoint requires vWAN hub and VPN connectivity to be operational (depends on feature 001-vwan-core)
- **Key Vault**: Required for storing any ACR service principal credentials if needed for automation (already available from feature 001-vwan-core)
- **Azure RBAC Permissions**: Deploying user must have permissions to create ACR, private endpoints, and DNS zones
- **VPN Client Connectivity**: Users must establish VPN connection to access private ACR
- **Azure Private DNS Integration**: Requires private DNS zone creation and linking to virtual network for name resolution

## Out of Scope

- Automated scheduled image synchronization from public registries (manual import only)
- Geo-replication of ACR across multiple Azure regions
- Advanced content trust and image signing workflows
- Container image vulnerability scanning and security policies (beyond default ACR settings)
- Custom webhook integrations for CI/CD pipelines
- ACR tasks for automated builds within the registry
- Integration with specific container orchestrators (AKS, Container Instances) - this is for future features
- Multi-tenancy or isolated repository access patterns (single team/project assumed)
- Advanced networking scenarios like service endpoints or VNet service tags (private endpoint only)
- Image retention policies beyond basic tag cleanup (advanced lifecycle management)
