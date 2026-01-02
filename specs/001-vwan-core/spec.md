# Feature Specification: Core Azure vWAN Infrastructure with Global Secure Access

**Feature Branch**: `001-vwan-core`  
**Created**: 2025-12-31  
**Updated**: 2025-12-31 (Refactored for Global Secure Access)
**Status**: Draft  
**Input**: User description: "Create core Azure infrastructure with vWAN hub, site-to-site VPN Gateway for Global Secure Access integration, and Key Vault in rg-ai-core resource group"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Foundation Infrastructure (Priority: P1)

As an infrastructure engineer, I need to deploy the core networking and security foundation (resource group, vWAN hub, site-to-site VPN Gateway for Global Secure Access, Key Vault) so that all future Azure labs have a centralized hub for connectivity, secure access, and secrets management.

**Why this priority**: This is the mandatory foundation for all spoke labs and Global Secure Access integration. Without this infrastructure, no other labs can be deployed, connected, or secured through Microsoft Entra's SSE solution. It establishes the hub-spoke architecture pattern with secure access edge capabilities.

**Independent Test**: Can be fully tested by deploying the Bicep templates to Azure, verifying resource creation in the Azure portal, confirming the vWAN hub is operational, and validating site-to-site VPN Gateway is ready for Global Secure Access integration. Delivers a complete, functional hub infrastructure ready for spoke connections and secure access policies.

**Acceptance Scenarios**:

1. **Given** Bicep templates and Azure CLI access, **When** deploying with `az deployment sub create`, **Then** resource group `rg-ai-core` is created with proper tags (environment, purpose, owner)
2. **Given** deployment completes successfully, **When** checking Azure portal, **Then** vWAN hub exists and is in "Succeeded" provisioning state
3. **Given** vWAN hub is deployed, **When** checking hub configuration, **Then** site-to-site VPN Gateway is attached with appropriate scale units for Global Secure Access connectivity
4. **Given** all resources are deployed, **When** checking `rg-ai-core`, **Then** Azure Key Vault exists with appropriate access policies configured
5. **Given** VPN Gateway is operational, **When** reviewing gateway configuration, **Then** site-to-site VPN settings are configured for Microsoft Entra Global Secure Access integration

---

### User Story 2 - Validate Deployment (Priority: P2)

As an infrastructure engineer, I need automated validation that confirms all core resources are properly configured and ready for spoke lab connections.

**Why this priority**: Ensures deployment quality and catches configuration errors before connecting spoke labs. Provides confidence that the hub infrastructure meets requirements.

**Independent Test**: Can be tested by running validation scripts post-deployment that check resource existence, configuration, and connectivity readiness. Delivers automated quality assurance for the foundation.

**Acceptance Scenarios**:

1. **Given** core infrastructure is deployed, **When** running what-if analysis on templates, **Then** no configuration drift is detected
2. **Given** resources exist in Azure, **When** checking resource properties, **Then** all naming conventions follow `rg-ai-core` pattern and tagging is complete
3. **Given** Key Vault is deployed, **When** testing access, **Then** RBAC permissions are correctly configured for secret management
4. **Given** vWAN hub is operational, **When** reviewing network configuration, **Then** hub is ready to accept spoke virtual network connections

---

### User Story 3 - Secure Parameter Management (Priority: P3)

As an infrastructure engineer, I need parameter files that reference Key Vault secrets (not hardcoded values) so that sensitive configuration is never exposed in source control.

**Why this priority**: Supports the constitution's security requirements. While important, the basic infrastructure can function without this if initial parameters are provided securely through other means.

**Independent Test**: Can be tested by reviewing parameter files to ensure no secrets are hardcoded, and validating that deployments successfully retrieve parameters from Key Vault references. Delivers secure configuration management.

**Acceptance Scenarios**:

1. **Given** Bicep parameter files, **When** reviewing file contents, **Then** no passwords, keys, or connection strings are hardcoded
2. **Given** deployment requires sensitive parameters, **When** using parameter files, **Then** values are retrieved from Key Vault references
3. **Given** parameter files exist in repository, **When** checking .gitignore, **Then** local parameter files with secrets are excluded from version control

---

### Edge Cases

- What happens when deployment fails partway through (e.g., vWAN deploys but VPN Gateway fails)?
- How does system handle region-specific resource limitations or quota issues?
- What if Key Vault soft-delete is enabled and a previous vault with same name exists?
- How to handle concurrent deployments if multiple engineers attempt to deploy simultaneously?
- What if RBAC permissions are insufficient for the deploying user?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST create Azure resource group named `rg-ai-core` with tags for environment, purpose, and owner
- **FR-002**: System MUST deploy Azure Virtual WAN (vWAN) hub within `rg-ai-core` resource group
- **FR-003**: System MUST attach site-to-site VPN Gateway to vWAN hub to enable Microsoft Entra Global Secure Access integration
- **FR-004**: System MUST deploy Azure Key Vault within `rg-ai-core` for centralized secrets management
- **FR-005**: All infrastructure MUST be defined as Bicep templates with parameterized values
- **FR-006**: Deployment MUST use Azure CLI (`az deployment`) with what-if validation before applying changes
- **FR-007**: Bicep templates MUST include inline comments explaining design decisions and configuration choices
- **FR-008**: Parameter files MUST use Key Vault references for any sensitive values (no hardcoded secrets)
- **FR-009**: All resources MUST follow naming conventions defined in constitution
- **FR-010**: Deployment MUST be idempotent (safe to run multiple times without creating duplicates)
- **FR-011**: System MUST include rollback documentation for each deployment step
- **FR-012**: vWAN hub MUST be configured to accept spoke virtual network connections from future labs
- **FR-013**: Key Vault MUST have RBAC access policies configured for secure secret access
- **FR-014**: All Bicep modules MUST be reusable and follow modular design patterns

### Key Entities

- **Resource Group**: Container for all core infrastructure resources, tagged with metadata (environment, purpose, owner), serves as boundary for RBAC and billing
- **Virtual WAN Hub**: Central networking hub in hub-spoke topology, provides routing and connectivity services, hosts VPN Gateway
- **VPN Gateway**: Site-to-site VPN endpoint attached to vWAN hub, enables Microsoft Entra Global Secure Access integration for Security Service Edge (SSE) capabilities
- **Key Vault**: Centralized secrets management service, stores sensitive configuration data, referenced by all lab deployments for secure parameter retrieval

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Infrastructure engineer can deploy complete core infrastructure from Bicep templates in under 30 minutes
- **SC-002**: Deployment validation (what-if analysis) completes successfully with zero configuration drift after initial deployment
- **SC-003**: All resources appear in Azure portal with correct names, tags, and "Succeeded" provisioning state within 30 minutes of deployment
- **SC-004**: vWAN hub successfully accepts test spoke virtual network connection (readiness for future labs)
- **SC-005**: Key Vault access is verified by storing and retrieving a test secret using Azure CLI
- **SC-006**: 100% of Bicep templates pass Azure validation checks before deployment
- **SC-007**: Zero secrets or sensitive values found in source control repository (verified by .gitignore and code review)
- **SC-008**: Infrastructure can be torn down and redeployed successfully without manual intervention (idempotent deployment validated)
