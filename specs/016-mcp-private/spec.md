# Feature Specification: Private MCP Server — Copilot Studio via VNet

**Feature Branch**: `feature/015-apim-private`  
**Created**: 2026-04-09  
**Status**: Draft  
**Project Type**: Solution  
**Input**: User description: "Build a new solution similar to MCP Server — ACA + APIM + Copilot Studio, but private. Use existing infrastructure projects."

## Overview

This Solution project connects a Copilot Studio agent to the existing MCP server (running in ACA) through the private APIM gateway — with zero public network exposure. It deploys the MCP API definition into the existing private APIM (015), configures Power Platform VNet delegation, and guides the user through custom connector and agent setup in Copilot Studio.

### Infrastructure Dependencies

| Resource | Name | Resource Group | Spec |
|----------|------|----------------|------|
| APIM (private) | apim-ai-lab-private | rg-ai-apim-private | 015-apim-private |
| ACA MCP Server | mcp-server | rg-ai-aca | 013-mcp-server |
| PP Subnet | PowerPlatformSubnet | rg-ai-core | 015-apim-private |
| Private DNS | privatelink.azure-api.net | rg-ai-core | 015-apim-private |
| Core Infra | vnet-ai-shared, DNS resolver | rg-ai-core | 001-vwan-core |

### What This Solution Deploys

- **MCP API definition** — API + operation + JWT validation + SSE passthrough policies into existing private APIM
- **PP enterprise policy** — Links PowerPlatformSubnet to Managed PP environment (PowerShell)
- **Custom connector guide** — Standard HTTP connector in Copilot Studio pointing to private APIM
- **Agent configuration** — Copilot Studio agent with MCP actions

## User Scenarios & Testing

### User Story 1 — Deploy MCP API to Private APIM (Priority: P1)

As an AI developer, I want to deploy the MCP API definition into the private APIM so that the MCP server is exposed through a private gateway with JWT authentication.

**Why this priority**: API must be deployed before Copilot Studio can connect.

**Independent Test**: Deploy API, verify it exists in APIM, send unauthenticated request and confirm 401.

**Acceptance Scenarios**:

1. **Given** private APIM is deployed, **When** I run `deploy-mcp-api-private.sh`, **Then** `mcp-api` is created in `apim-ai-lab-private`
2. **Given** MCP API is deployed, **When** an unauthenticated request hits `/mcp/`, **Then** APIM returns 401
3. **Given** a valid OAuth token, **When** I POST an MCP initialize request, **Then** the MCP server responds with server info

---

### User Story 2 — Link Power Platform to VNet (Priority: P2)

As a platform engineer, I want to create an enterprise policy and link my Managed PP environment to the PowerPlatformSubnet so that Copilot Studio connectors route through the VNet.

**Why this priority**: Without VNet linkage, Copilot Studio connector traffic goes through public internet and cannot reach the private APIM.

**Independent Test**: Run setup script, verify enterprise policy is created, verify PP admin center shows Active VNet linkage.

**Acceptance Scenarios**:

1. **Given** PowerPlatformSubnet exists with correct delegation, **When** I run `setup-pp-vnet.sh`, **Then** an enterprise policy is created and linked to the PP environment
2. **Given** VNet linkage is active, **When** a custom connector makes an HTTPS call, **Then** traffic egresses through the delegated subnet

---

### User Story 3 — Copilot Studio Agent Calls MCP Server Privately (Priority: P3)

As an AI developer, I want a Copilot Studio agent to call the MCP server through the private APIM so that no traffic traverses the public internet.

**Why this priority**: End-to-end validation of the complete solution.

**Independent Test**: Create custom connector, create agent, ask "What time is it?" — verify response comes from MCP server.

**Acceptance Scenarios**:

1. **Given** MCP API is deployed and PP VNet is linked, **When** a custom connector calls `apim-ai-lab-private.azure-api.net/mcp/`, **Then** APIM receives the request on its private endpoint
2. **Given** a Copilot Studio agent has the MCP action, **When** a user asks "What time is it?", **Then** the agent invokes `get_current_time` and returns the timestamp
3. **Given** the agent is running, **When** I check network traces, **Then** all traffic stays within the VNet

---

### Edge Cases

- What happens if VNet delegation is enabled on a non-Managed environment? Operation fails — Managed Environment is required
- What happens if the PP subnet runs out of IPs? Connector calls fail; /27 provides 27 usable IPs
- What happens if PP VNet linkage is removed? Connector traffic falls back to public internet, cannot reach private APIM
- What happens if ACA MCP server is not running? APIM returns 504 Gateway Timeout

## Requirements

### Functional Requirements

- **FR-001**: System MUST deploy MCP API definition with JWT validation into existing private APIM
- **FR-002**: System MUST deploy SSE passthrough policy (`buffer-response="false"`) for MCP streaming
- **FR-003**: System MUST provide a script to create PP enterprise policy and link to PP environment
- **FR-004**: System MUST document custom connector setup in Copilot Studio
- **FR-005**: System MUST document agent configuration with MCP actions
- **FR-006**: System MUST NOT create any new infrastructure resources (uses existing from 015, 013, 001)
- **FR-007**: System MUST use standard HTTP custom connector (not MCP connector) for GA VNet support
- **FR-008**: System MUST require a NEW Managed PP environment (not modify existing)

### Key Entities

- **MCP API**: API definition deployed to existing private APIM
- **JWT Policy**: Validates Entra ID tokens, restricts to authorized client apps
- **Enterprise Policy**: Links PP subnet to Managed PP environment
- **Standard Custom Connector**: HTTP connector routing through VNet to private APIM
- **Copilot Studio Agent**: AI agent with MCP tool actions

## Success Criteria

### Measurable Outcomes

- **SC-001**: MCP API exists in private APIM with path `/mcp`
- **SC-002**: Unauthenticated requests return 401
- **SC-003**: Authenticated requests from VPN return MCP server responses
- **SC-004**: PP admin center shows VNet linkage as **Active**
- **SC-005**: Custom connector test in PP succeeds
- **SC-006**: Copilot Studio agent can invoke `get_current_time` and `get_runtime_info`
- **SC-007**: No API traffic traverses the public internet

## Assumptions

- Private APIM (015) is already deployed with PP subnet
- ACA MCP server (013) is already deployed and reachable via VNet
- User has a Copilot Studio license (includes Managed Environment entitlement)
- User will create a NEW Managed PP environment

## Dependencies

- **015-apim-private**: Private APIM instance, PP subnet, DNS zone
- **013-mcp-server**: ACA-hosted MCP server (backend)
- **001-vwan-core**: VNet, DNS resolver, VPN

## Out of Scope

- Creating or modifying APIM infrastructure (015 handles that)
- Creating or modifying ACA/MCP server (013 handles that)
- MCP-specific connector in Copilot Studio (using standard HTTP connector)
- Native APIM MCP server feature
- Custom domain configuration
