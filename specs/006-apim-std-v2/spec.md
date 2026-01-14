# Feature Specification: Azure API Management Standard v2

**Feature Branch**: `006-apim-std-v2`  
**Created**: 2026-01-14  
**Status**: Draft  
**Type**: Infrastructure Project  
**Input**: User description: "Deploy Azure API Management Standard v2 with public frontend and VNet-integrated backend for exposing internal APIs externally"

## Overview

Deploy an Azure API Management (APIM) Standard v2 instance to serve as the centralized API gateway for the AI-Lab infrastructure. The gateway provides a public-facing frontend for external API consumers while using VNet integration to securely communicate with backend services hosted on private endpoints.

### Key Characteristics

- **SKU**: Standard v2 (cost-effective choice; Premium v2 reserved for future high-availability requirements)
- **Frontend**: Public gateway endpoint accessible from the internet
- **Backend**: VNet-integrated for outbound connectivity to private endpoints across the hub-spoke network
- **Authentication**: OAuth 2.0 with Microsoft Entra ID
- **Developer Portal**: Enabled for API documentation and testing

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy APIM with VNet Integration (Priority: P1)

As a platform engineer, I want to deploy an APIM Standard v2 instance integrated with the vWAN hub network so that the gateway can reach backend services on private endpoints.

**Why this priority**: Core deployment that enables all other functionality. Without APIM deployed and network-connected, no APIs can be exposed.

**Independent Test**: Deploy APIM, verify the instance is running, confirm VNet integration is active by checking network configuration in Azure Portal.

**Acceptance Scenarios**:

1. **Given** core infrastructure is deployed with vWAN hub and shared services VNet, **When** I run the APIM deployment script, **Then** an APIM Standard v2 instance is created in resource group `rg-ai-apim`
2. **Given** APIM is deployed, **When** I check the network configuration, **Then** VNet integration shows connected to a dedicated subnet in the shared services VNet
3. **Given** APIM is VNet-integrated, **When** I check outbound connectivity, **Then** APIM can resolve and reach private endpoints in spoke VNets via the vWAN hub

---

### User Story 2 - Access APIM from VPN Clients (Priority: P2)

As a developer connected via VPN, I want to access the APIM developer portal and management plane so that I can test APIs and manage configurations from my local machine.

**Why this priority**: VPN access enables developers to work with the full APIM experience including the developer portal, which is essential for API discovery and testing.

**Independent Test**: Connect via P2S VPN, navigate to APIM developer portal URL in browser, verify page loads and login works.

**Acceptance Scenarios**:

1. **Given** I am connected to the AI-Lab VPN, **When** I navigate to the APIM developer portal URL, **Then** the portal loads and I can browse available APIs
2. **Given** I am connected to the AI-Lab VPN, **When** I access the Azure Portal, **Then** I can manage APIM configuration (APIs, policies, subscriptions)
3. **Given** I am connected to the AI-Lab VPN, **When** I use the developer portal test console, **Then** I can send test requests to published APIs

---

### User Story 3 - Configure OAuth/Entra Authentication (Priority: P3)

As a platform engineer, I want APIM configured with OAuth 2.0 and Microsoft Entra ID authentication so that API consumers must authenticate before accessing protected APIs.

**Why this priority**: Security is essential but can be configured after the core gateway is operational. Initial deployment can proceed without auth while this is set up.

**Independent Test**: Configure an Entra app registration for APIM, apply OAuth policy to a test API, attempt unauthenticated request (should fail), authenticate and retry (should succeed).

**Acceptance Scenarios**:

1. **Given** APIM is deployed, **When** I configure an Entra app registration for OAuth, **Then** APIM can validate JWT tokens from Entra ID
2. **Given** OAuth is configured on an API, **When** an unauthenticated request is sent, **Then** APIM returns 401 Unauthorized
3. **Given** OAuth is configured on an API, **When** a request with valid Entra ID token is sent, **Then** APIM forwards the request to the backend

---

### User Story 4 - Publish an API to External Consumers (Priority: P4)

As a platform engineer, I want to publish an internal backend API through APIM so that external consumers can access it via the public gateway endpoint.

**Why this priority**: This validates the end-to-end flow but depends on having a backend service available (Solution Project).

**Independent Test**: Import an API definition, configure backend to point to a private endpoint (e.g., storage API), call the API from the public internet.

**Acceptance Scenarios**:

1. **Given** APIM is deployed with VNet integration, **When** I import an API pointing to a backend on a private endpoint, **Then** the API is published and visible in the developer portal
2. **Given** an API is published, **When** an external consumer calls the public gateway URL, **Then** APIM routes the request to the private backend and returns the response
3. **Given** an API is published with a private backend, **When** I check the backend request, **Then** it originates from the APIM VNet-integrated subnet IP range

---

### Edge Cases

- What happens when the backend private endpoint is unreachable? APIM should return 502 Bad Gateway with appropriate error details
- How does APIM handle DNS resolution for private endpoints? Must use Azure DNS or custom DNS that resolves private endpoint FQDNs
- What happens when VNet integration subnet runs out of IP addresses? Deployment/scaling fails; monitor subnet capacity

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST deploy Azure API Management in the Standard v2 pricing tier
- **FR-002**: System MUST deploy APIM to a dedicated resource group `rg-ai-apim`
- **FR-003**: System MUST configure VNet integration with a dedicated /27 subnet (`10.1.0.96/27`) in the shared services VNet
- **FR-004**: The VNet integration subnet MUST be delegated to `Microsoft.Web/serverFarms`
- **FR-005**: System MUST configure NSG on the integration subnet allowing outbound HTTPS to Storage and AzureKeyVault service tags
- **FR-006**: System MUST enable the developer portal for API documentation and testing
- **FR-007**: System MUST use default Azure-provided domain (`*.azure-api.net`) for gateway and portal endpoints
- **FR-008**: VPN clients MUST be able to access the developer portal and management plane
- **FR-009**: System MUST support OAuth 2.0 with Microsoft Entra ID for API authentication
- **FR-010**: APIM backend requests MUST route through the vWAN hub to reach private endpoints in spoke VNets
- **FR-011**: System MUST follow Bicep-only IaC practices per AI-Lab constitution
- **FR-012**: System MUST tag all resources with environment, purpose, and owner tags per constitution

### Key Entities

- **API Management Instance**: The core gateway resource; contains APIs, products, subscriptions, policies
- **VNet Integration Subnet**: Dedicated subnet for APIM outbound traffic; delegated to Microsoft.Web/serverFarms
- **Developer Portal**: Public-facing documentation and testing interface for API consumers
- **Entra App Registration**: OAuth 2.0 identity configuration for API authentication
- **API**: Individual API definition with operations, policies, and backend configuration
- **Backend**: Connection configuration pointing to private endpoint URLs

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: APIM instance is accessible via public gateway URL from the internet
- **SC-002**: Developer portal loads and displays published APIs for authenticated users
- **SC-003**: APIM can successfully route requests to backend services on private endpoints (verified with storage API)
- **SC-004**: VPN-connected developers can access both the developer portal and Azure Portal management
- **SC-005**: API requests without valid OAuth token receive 401 Unauthorized response
- **SC-006**: API requests with valid OAuth token successfully reach the backend and return expected response
- **SC-007**: Deployment completes via single script execution following AI-Lab patterns
- **SC-008**: All resources are properly tagged and deployed to `rg-ai-apim` resource group

## Assumptions

- Core infrastructure (vWAN hub, shared services VNet, Key Vault) is already deployed
- Private DNS zones are configured in the hub for private endpoint resolution
- VPN client connectivity is operational
- Standard v2 tier is sufficient for current workload (no multi-region or advanced isolation requirements)
- Microsoft.Web resource provider is registered in the subscription for subnet delegation

## Dependencies

- **001-vwan-core**: vWAN hub, shared services VNet, Key Vault, P2S VPN Gateway
- **004-dns-resolver**: Private DNS resolution for backend private endpoints

## Out of Scope

- Custom domain configuration (use default `*.azure-api.net`)
- Multi-region deployment (Standard v2 limitation)
- Premium v2 features (VNet injection, full isolation)
- Specific API implementations (handled by Solution Projects)
- Rate limiting and advanced policies (can be added incrementally)
- Application Insights integration (future enhancement)
