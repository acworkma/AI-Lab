# Feature Specification: Private Azure Container Apps Environment

**Feature Branch**: `012-private-aca`  
**Created**: 2026-02-20  
**Status**: Implementing  
**Input**: User description: "Deploy a Private Azure Container Apps environment with VNet injection, private endpoint connectivity, internal-only ingress, and DNS integration for secure serverless container hosting accessible only via VPN"

## Background

This specification creates a private Azure Container Apps (ACA) environment as a foundational infrastructure project, following the same patterns established by Key Vault, Storage, ACR, and AKS infrastructure projects. The environment provides a secure, serverless container runtime that is only accessible via the private network.

This enables:
1. **Serverless container hosting** - Run containerized applications without managing infrastructure
2. **Private-only access** - Environment management and app ingress are inaccessible from public internet
3. **ACR integration** - Pull container images from the private ACR via managed identity
4. **VPN-based management** - All access requires VPN connection through the vWAN hub

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Private ACA Environment (Priority: P1)

As an infrastructure engineer, I need to deploy a private Azure Container Apps environment with VNet injection and private endpoint, integrated with the existing private DNS infrastructure and shared services VNet, so that serverless container workloads can run securely within the Azure environment.

**Why this priority**: This is the foundation for running serverless containers. Without the environment, no container apps can be deployed. VNet injection and private endpoint ensure the environment is never exposed to the public internet.

**Independent Test**: Can be fully tested by deploying the ACA Bicep module, verifying the environment is created with VNet injection and private endpoint, confirming internal-only ingress, and validating DNS resolution returns a private IP address.

**Acceptance Scenarios**:

1. **Given** ACA Bicep module exists, **When** deploying to Azure, **Then** ACA environment is created in resource group `rg-ai-aca` with VNet injection enabled
2. **Given** ACA is deployed, **When** checking network configuration, **Then** environment has internal-only ingress and no public endpoint
3. **Given** private endpoint is configured, **When** resolving the default domain, **Then** DNS returns a private IP address
4. **Given** ACA is operational, **When** attempting access from public internet (not VPN-connected), **Then** connection fails
5. **Given** ACA module is deployed, **When** reviewing configuration, **Then** Log Analytics workspace is connected for diagnostics

---

### User Story 2 - Deploy Container Apps to Environment (Priority: P2)

As a developer, I need to deploy container apps to the ACA environment with internal ingress, so that applications are accessible within the private network.

**Why this priority**: Enables the primary workload deployment use case. After the environment exists, developers can deploy serverless apps.

**Independent Test**: Can be tested by deploying a sample container app with internal ingress and verifying it starts and is accessible via VPN.

**Acceptance Scenarios**:

1. **Given** ACA environment exists, **When** deploying a container app with internal ingress, **Then** app is created and accessible via private FQDN
2. **Given** container app is deployed, **When** checking ingress type, **Then** ingress is internal-only
3. **Given** app is running, **When** connecting via VPN, **Then** HTTPS requests succeed
4. **Given** app is running, **When** checking from public internet, **Then** FQDN does not resolve

---

### User Story 3 - Integrate with Existing Infrastructure Patterns (Priority: P3)

As an infrastructure engineer, I need the ACA module to follow the same deployment patterns as Key Vault, Storage, ACR, and AKS (parameterized Bicep, deployment scripts, validation scripts, documentation), so that infrastructure management is consistent across all modules.

**Why this priority**: Ensures maintainability and consistency. Important for long-term management.

**Independent Test**: Can be tested by reviewing Bicep module structure, parameter file patterns, and running deployment/validation scripts.

**Acceptance Scenarios**:

1. **Given** ACA Bicep module exists, **When** reviewing file structure, **Then** module follows `bicep/aca/main.bicep` pattern with supporting modules in `bicep/modules/`
2. **Given** parameter files exist, **When** reviewing contents, **Then** no secrets are hardcoded
3. **Given** ACA deployment script exists, **When** running `./scripts/deploy-aca.sh`, **Then** script performs what-if, prompts for confirmation, and deploys with validation
4. **Given** module is deployed, **When** running idempotent redeployment, **Then** no unexpected changes are made

---

### Edge Cases

- **VNet address space exhaustion**: ACA requires /23 subnet; VNet expanded from /24 to /22 to accommodate
- **Subnet delegation conflicts**: ACA subnet requires Microsoft.App/environments delegation; cannot share with other delegations
- **Log Analytics workspace reference**: Support both creating new LA workspace and referencing existing one via parameter
- **DNS zone link missing**: If DNS zone is not linked to VNet, private resolution fails; validation checks zone link status
- **Environment provisioning delays**: ACA environment creation can take several minutes; deployment script monitors progress
- **Consumption plan limits**: Azure region quota limits apply; validation provides actionable error messages

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a Bicep deployment at `bicep/aca/main.bicep` for orchestrating ACA environment deployment
- **FR-002**: System MUST provide a reusable module at `bicep/modules/aca-environment.bicep` for ACA environment resource
- **FR-003**: ACA environment MUST be deployed to a dedicated resource group `rg-ai-aca` (following project separation pattern)
- **FR-004**: ACA environment MUST be VNet-injected using dedicated subnet with `/23` prefix
- **FR-005**: ACA environment MUST use internal-only ingress (`internal: true`)
- **FR-006**: ACA environment MUST have public network access disabled
- **FR-007**: Private endpoint MUST be deployed for the management plane with DNS zone group auto-registration
- **FR-008**: Private DNS zone `privatelink.azurecontainerapps.io` MUST be added to core infrastructure
- **FR-009**: Log Analytics workspace MUST be created (or referenced) for environment diagnostics
- **FR-010**: ACA environment MUST use Consumption workload profile
- **FR-011**: Shared services VNet MUST be expanded from `/24` to `/22` to accommodate ACA subnet
- **FR-012**: ACA subnet MUST have `Microsoft.App/environments` delegation
- **FR-013**: Deployment scripts MUST follow patterns from `deploy-keyvault.sh` (what-if, validation, outputs)
- **FR-014**: Documentation MUST be provided at `docs/aca/README.md` following existing doc patterns
- **FR-015**: ACA environment MUST have appropriate Azure tags consistent with core infrastructure

### Key Entities

- **Container Apps Environment**: Managed hosting environment providing serverless container runtime, VNet-injected for network isolation
- **Private Endpoint**: Network interface connecting to ACA management plane via private IP for secure management operations
- **Log Analytics Workspace**: Monitoring workspace collecting environment diagnostics, metrics, and logs
- **ACA Subnet**: Dedicated `/23` subnet (`10.1.2.0/23`) with Microsoft.App/environments delegation
- **Private DNS Zone**: DNS configuration for `privatelink.azurecontainerapps.io` resolving environment FQDN to private endpoint IP

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Infrastructure engineer can deploy private ACA environment from Bicep module in under 10 minutes
- **SC-002**: ACA environment default domain resolves to private IP address from VPN clients
- **SC-003**: ACA environment is completely inaccessible from public internet
- **SC-004**: Container apps deployed to environment use internal-only ingress
- **SC-005**: Log Analytics workspace receives environment diagnostics
- **SC-006**: ACA deployment follows same infrastructure patterns as other modules

## Clarifications

### Session 2026-02-20

- Q: What workload profile should be used? → A: Consumption-only (no dedicated plan needed for lab)
- Q: Should the environment be zone redundant? → A: No for dev, parameterized for prod
- Q: Where should Log Analytics workspace be created? → A: In rg-ai-aca; provide existingLogAnalyticsWorkspaceId param for shared workspace
- Q: What about initial container apps? → A: None - environment only; apps deployed separately
- Q: How should ACR integration work? → A: Via managed identity with AcrPull role (future enhancement)
- Q: What about ingress type? → A: Internal-only; no external/public access
- Q: What VNet changes are needed? → A: Expand from /24 to /22; add ACA subnet at 10.1.2.0/23
- Q: Should both VNet injection AND private endpoint be used? → A: Yes, both for full isolation
- Q: What DNS zone is needed? → A: privatelink.azurecontainerapps.io added to core private-dns-zones.bicep

## Assumptions

- ACA environment will be deployed in East US 2 (same as vWAN hub)
- The existing private ACR is deployed and accessible for future ACR integration
- VNet expansion from /24 to /22 does not affect existing deployments (address space only grows)
- Users accessing the environment will connect via VPN
- Consumption workload profile is sufficient for lab/dev workloads
- Container app deployment is separate from environment infrastructure

## Dependencies

- **Core Infrastructure (001-vwan-core)**: ACA private endpoint requires vWAN hub, VPN connectivity, and private DNS zones
- **Shared Services VNet**: ACA requires VNet expansion and new subnet with delegation
- **Azure RBAC Permissions**: Deploying user must have permissions to create ACA environments and role assignments
- **VPN Client Connectivity**: Users must establish VPN connection to access private ACA environment

## Out of Scope

- Container app deployment and configuration (apps are separate from environment infrastructure)
- Dapr integration or sidecar configuration
- Custom domain and TLS certificate management
- Azure Front Door or Application Gateway integration
- Azure Container Registry integration (documented as future enhancement)
- KEDA scaling rules and custom autoscaling
- Managed certificates for custom domains
- Service-to-service authentication patterns
- GPU workload profiles
- Production sizing and high-availability configurations
