# Feature Specification: Azure API Management Standard v2 — Private

**Feature Branch**: `feature/015-apim-private`  
**Created**: 2026-04-09  
**Status**: Draft  
**Type**: Infrastructure Project  
**Input**: User description: "Deploy APIM Standard v2 on a private endpoint with public access disabled. Private counterpart to the public APIM (006)."

## Overview

Deploy a private Azure API Management Standard v2 instance — the counterpart to the public APIM in spec 006. The gateway is accessible only via an inbound private endpoint; `publicNetworkAccess` is disabled. The deployment also provisions a Power Platform–delegated subnet for use by solution projects that connect Copilot Studio.

### Key Characteristics

- **SKU**: Standard v2 with `publicNetworkAccess: Disabled`
- **Inbound**: Private endpoint (Gateway group) in PrivateEndpointSubnet
- **Outbound**: VNet integration subnet for backend connectivity
- **DNS**: `privatelink.azure-api.net` zone linked to shared services VNet
- **PP Subnet**: Delegated to `Microsoft.PowerPlatform/enterprisePolicies` (ready for solution projects)
- **Isolation**: Separate resource group (`rg-ai-apim-private`), does not modify existing public APIM

## User Scenarios & Testing

### User Story 1 — Deploy Private APIM Infrastructure (Priority: P1)

As a platform engineer, I want to deploy APIM with a private endpoint and public access disabled so that the gateway is only reachable from within the VNet.

**Why this priority**: Core deployment that enables all other functionality.

**Independent Test**: Deploy APIM, verify private endpoint is in Approved/Succeeded state, confirm `publicNetworkAccess` is Disabled, verify public gateway URL times out from the internet.

**Acceptance Scenarios**:

1. **Given** core infrastructure is deployed, **When** I run `deploy-apim-private.sh`, **Then** APIM Standard v2 is created in `rg-ai-apim-private` with a private endpoint
2. **Given** APIM is deployed, **When** I check `publicNetworkAccess`, **Then** it is `Disabled`
3. **Given** APIM is deployed, **When** I curl the gateway URL from the public internet, **Then** the request times out or is refused
4. **Given** APIM is deployed and I am on VPN, **When** I resolve the gateway URL via DNS, **Then** it resolves to a private IP in PrivateEndpointSubnet

---

### User Story 2 — Access Private APIM from VPN (Priority: P2)

As a developer connected via VPN, I want to access the private APIM gateway and management plane so that I can test APIs and manage configurations.

**Why this priority**: VPN access enables developers to interact with the private APIM during development and testing.

**Independent Test**: Connect via P2S VPN, resolve APIM hostname, verify it returns private IP, access Azure Portal management for the APIM instance.

**Acceptance Scenarios**:

1. **Given** I am connected to the AI-Lab VPN, **When** I resolve `apim-ai-lab-private.azure-api.net`, **Then** it returns a private IP (10.1.0.x)
2. **Given** I am on VPN, **When** I access the Azure Portal, **Then** I can manage the private APIM instance
3. **Given** I am NOT on VPN, **When** I try to reach the gateway URL, **Then** the connection fails

---

### User Story 3 — Power Platform Subnet Ready for Solution Projects (Priority: P3)

As a platform engineer, I want the deployment to include a Power Platform–delegated subnet so that solution projects can connect Copilot Studio without additional infrastructure work.

**Why this priority**: Enables solution projects that use PP VNet delegation.

**Independent Test**: Check subnet exists with correct delegation.

**Acceptance Scenarios**:

1. **Given** the deployment completes, **When** I check `PowerPlatformSubnet`, **Then** it exists with delegation to `Microsoft.PowerPlatform/enterprisePolicies`
2. **Given** the subnet is delegated, **When** a solution project creates an enterprise policy, **Then** it can link to this subnet

---

### Edge Cases

- What happens if the private DNS zone link is missing? APIM hostname resolves to public IP, private endpoint is bypassed, request blocked by `publicNetworkAccess: Disabled`
- What happens if the integration subnet runs out of IPs? APIM scaling fails; /27 provides 27 usable IPs
- What happens if the PE subnet has no available IPs? Private endpoint creation fails

## Requirements

### Functional Requirements

- **FR-001**: System MUST deploy APIM Standard v2 with `publicNetworkAccess: Disabled`
- **FR-002**: System MUST create an inbound private endpoint for the APIM Gateway group
- **FR-003**: System MUST create a `privatelink.azure-api.net` private DNS zone linked to the shared services VNet
- **FR-004**: System MUST deploy to a dedicated resource group `rg-ai-apim-private`
- **FR-005**: System MUST create a Power Platform delegated subnet (`Microsoft.PowerPlatform/enterprisePolicies`)
- **FR-006**: System MUST configure VNet integration with a dedicated /27 subnet for outbound backend connectivity
- **FR-007**: System MUST configure NSG on the integration subnet
- **FR-008**: System MUST enable system-assigned managed identity on the APIM instance
- **FR-009**: System MUST NOT modify any resources in the existing `rg-ai-apim` resource group
- **FR-010**: System MUST follow Bicep-only IaC practices per AI-Lab conventions
- **FR-011**: System MUST tag all resources with environment, purpose, and owner tags

### Non-Functional Requirements

- **NFR-001**: Gateway MUST NOT be reachable from the public internet
- **NFR-002**: DNS resolution of the APIM hostname from within the VNet MUST return the private endpoint IP

### Key Entities

- **APIM Instance**: Private gateway with no public exposure
- **Private Endpoint**: Inbound entry point in PrivateEndpointSubnet (Gateway group)
- **Private DNS Zone**: `privatelink.azure-api.net` for name resolution
- **VNet Integration Subnet**: Outbound connectivity to backends
- **Power Platform Subnet**: Delegated, ready for solution project use
- **NSG**: Traffic control on APIM integration subnet

## Success Criteria

### Measurable Outcomes

- **SC-001**: APIM `publicNetworkAccess` property is `Disabled`
- **SC-002**: Private endpoint connection state is `Approved` with provisioning state `Succeeded`
- **SC-003**: `nslookup apim-ai-lab-private.azure-api.net` from VPN returns a private IP (10.1.0.x)
- **SC-004**: `curl` to the public gateway URL from the internet fails (timeout or refused)
- **SC-005**: Power Platform subnet shows delegation to `Microsoft.PowerPlatform/enterprisePolicies`
- **SC-006**: All resources deployed to `rg-ai-apim-private` (existing `rg-ai-apim` unchanged)
- **SC-007**: Deployment completes via single script execution following AI-Lab patterns

## Assumptions

- Core infrastructure (vWAN hub, shared services VNet, DNS resolver, PE subnet) is already deployed
- Standard v2 tier supports inbound private endpoint (GA feature)
- User will provide a globally unique APIM name

## Dependencies

- **001-vwan-core**: vWAN hub, shared services VNet, DNS resolver, P2S VPN
- **004-dns-resolver**: DNS resolution for private endpoints

## Out of Scope

- API definitions and policies (handled by solution projects like 016-mcp-private)
- Power Platform enterprise policy creation and environment linkage (solution project)
- Custom connector and Copilot Studio configuration (solution project)
- Custom domain configuration (use default `*.azure-api.net`)
- Multi-region deployment
- Application Insights integration
