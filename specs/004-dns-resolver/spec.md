# Feature Specification: DNS Private Resolver for Azure Private DNS

**Feature ID**: 004-dns-resolver  
**Created**: 2026-01-04  
**Priority**: P0 (foundational; blocks private resource access from P2S/WSL)  
**Status**: Specification phase  
**Branch**: `004-dns-resolver` (to be created)

---

## Overview

Deploy Azure DNS Private Resolver with inbound endpoint into the core infrastructure shared services VNet. This enables P2S VPN clients (including WSL on Windows VMs) to query private DNS zones and resolve private Azure resources (ACR, Key Vault, Storage, App Service, etc.) to their private endpoint IPs without manual /etc/hosts entries.

**Problem solved**: 
- Azure DNS (168.63.129.16) returns public IPs for private resources when queried from P2S clients (not VNet-linked).
- DNS Private Resolver gives queries VNet context, so private zones linked to that VNet return private IPs.
- Single resolver inbound endpoint IP serves all P2S clients and future spokes.

**Impact**: 
- WSL and other P2S clients can access all private endpoints in core and spoke services.
- Foundation for scalable private DNS across all labs.
- Replaces temporary /etc/hosts workarounds permanently.

---

## User Stories

### User Story 1 - Deploy DNS Private Resolver (Priority: P0)
**As a** DevOps engineer,  
**I want to** deploy an Azure DNS Private Resolver into the core shared services VNet,  
**So that** all P2S VPN clients get private DNS resolution for private endpoints without manual hosts entries.

**Acceptance Criteria**:
- Resolver deployed with inbound endpoint in dedicated subnet.
- Inbound endpoint assigned a static private IP (e.g., 10.1.0.65).
- Existing private DNS zones remain linked to shared VNet (automatic resolution).
- P2S client routing can reach the inbound endpoint IP over VPN.
- Deployment is idempotent (re-run produces no unwanted changes).

### User Story 2 - Validate Resolver Functionality (Priority: P0)
**As a** platform engineer,  
**I want to** verify the resolver correctly answers queries for private zones,  
**So that** we can confidently direct all P2S clients to the resolver IP.

**Acceptance Criteria**:
- nslookup/dig from WSL using resolver IP returns private IPs for privatelink.azurecr.io entries.
- Resolver returns private IPs for ACR, Key Vault, Storage, SQL zones.
- Public DNS queries (google.com) also succeed via fallback.
- HTTPS connectivity tests confirm clients reach private endpoints.
- Validation works from both VPN-connected WSL and test jump boxes.

### User Story 3 - Update Client Configuration (Priority: P0)
**As a** DevOps engineer,  
**I want to** update WSL DNS configuration to use the resolver inbound IP,  
**So that** developers get automatic private DNS without workarounds.

**Acceptance Criteria**:
- WSL resolv.conf primary: resolver IP; fallback: public DNS.
- wsl.conf disables auto-generation so manual config persists.
- Configuration applied via template and script (both manual and automated).
- All subsequent private resource access resolves to private IPs.

### User Story 4 - Documentation and Runbooks (Priority: P1)
**As a** developer or operator,  
**I want to** understand why the resolver is needed and how to troubleshoot it,  
**So that** future modifications and issue diagnosis are straightforward.

**Acceptance Criteria**:
- Overview explains the private DNS problem and solution.
- Operational runbook documents deployment, validation, scaling, and common issues.
- Troubleshooting guide covers resolver DNS queries, routing, private zone link issues.
- Examples for all major services (ACR, Key Vault, Storage, App Service).

---

## Requirements

### Functional Requirements

- **FR-001**: Deploy DNS Private Resolver (Microsoft.Network/dnsResolvers) in rg-ai-core.
- **FR-002**: Create dedicated inbound endpoint subnet (10.1.0.64/27) with service delegation.
- **FR-003**: Configure inbound endpoint (Microsoft.Network/dnsResolvers/inboundEndpoints) with static private IP.
- **FR-004**: Inbound endpoint is reachable from P2S client address pool (172.16.0.0/24) via vHub routing.
- **FR-005**: Resolver inherits knowledge of private DNS zones linked to shared VNet (privatelink.azurecr.io, etc.).
- **FR-006**: Queries for private zone records return private endpoint IPs (10.x.x.x), not public IPs.
- **FR-007**: Queries for public domains are answered (either by resolver or forwarded/recursed).
- **FR-008**: Resolver can be deployed via Bicep template as module in core infrastructure.
- **FR-009**: Resolver deployment is idempotent and can be re-deployed safely.
- **FR-010**: Inbound endpoint IP is exposed in deployment outputs for client configuration.
- **FR-011**: VNet link rules for private zones remain unchanged (no zone modifications needed).
- **FR-012**: Resolver allows future outbound endpoint for on-prem/corp DNS forwarding (not in MVP).

### Key Entities

- **DNS Resolver**: Azure managed DNS service providing inbound/outbound endpoints for name resolution.
- **Inbound Endpoint**: Public-facing DNS listener on a specific subnet IP; clients query this to resolve private zones.
- **Inbound Subnet**: Dedicated subnet (10.1.0.64/27) for inbound endpoint with Microsoft.Network/dnsResolvers delegation.
- **Private DNS Zones**: Already linked to shared VNet; resolver automatically queries them when queried for names in those zones.
- **P2S Address Pool**: VPN client pool (172.16.0.0/24); routing must allow traffic from this pool to inbound endpoint IP.
- **VNet Hub Connection**: Already established between shared VNet and vHub; ensures routing from P2S clients to shared VNet resources.

### Non-Functional Requirements

- **Performance**: Resolver should respond to DNS queries in <100ms (typical for Azure).
- **Availability**: Single inbound endpoint (no HA configured for MVP; can add outbound failover in future).
- **Cost**: Minimal monthly cost for inbound endpoint (~$0.10–1.00 per 1M queries, low volume in dev).
- **Scalability**: Single endpoint supports thousands of concurrent clients; outbound endpoint can be added for high volume.
- **Manageability**: Resolver managed by Azure; no agents or manual configuration needed on resolver itself.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: Bicep deployment completes successfully with no errors; resolver and inbound endpoint created.
- **SC-002**: Inbound endpoint IP is statically assigned and reachable via nslookup from P2S client address pool.
- **SC-003**: Queries for acraihubk2lydtz5uba3q.azurecr.io via resolver IP return 10.1.0.5 (or correct private IP).
- **SC-004**: Queries for acraihubk2lydtz5uba3q.privatelink.azurecr.io via resolver IP return private endpoint IP.
- **SC-005**: Queries for public domains (google.com) via resolver IP succeed with public IPs (not timeouts).
- **SC-006**: HTTPS curl to ACR using resolver-resolved private IP connects successfully with HTTP 200 or 401.
- **SC-007**: Resolver queries work from both WSL (P2S) and any spoke VNet connected to vHub.
- **SC-008**: Resolver redeploy (Bicep reapply) produces no unwanted resource recreations (idempotency).

---

## Technical Context

**Bicep Modules**:
- `modules/dns-resolver.bicep`: ~50 lines. Creates resolver, inbound endpoint, inbound subnet.

**Dependencies**:
- Core infrastructure (001-vwan-core): vHub, shared services VNet, private DNS zones.
- No external APIs or third-party tools.

**Integration Points**:
- Shared services VNet: New inbound subnet added to existing VNet (non-breaking).
- Private DNS zones: No modifications; resolver auto-queries zones linked to its VNet.
- VPN gateway and P2S: Existing routing already supports traffic from P2S to shared VNet (via vHub connection).

**Testing**:
- Manual: nslookup, dig, curl via WSL or jump box.
- Validation script: Bicep deployment outputs inbound IP; test script queries resolver for known private zones.

**Constraints**:
- Inbound subnet requires Microsoft.Network/dnsResolvers service delegation (must be specified in Bicep).
- Inbound endpoint IP is assigned by Azure (not user-specified) but is stable once created.
- No outbound endpoint in MVP (resolving only; no forwarding to on-prem DNS yet).

---

## Edge Cases

- What if P2S client cannot reach inbound endpoint IP (routing broken)? Fallback DNS should still work; troubleshooting guide covers this.
- What if private DNS zone is unlinked from shared VNet? Resolver won't answer; PR in docs to verify zone links.
- What if inbound endpoint is deleted? Clients lose private DNS; monitoring/alerts (future enhancement).
- What if spoke VNet is not connected to vHub? Spoke won't route to resolver; docs clarify prerequisite.
- What if client uses a different primary DNS (e.g., corporate)? Clients can override; docs show both manual and scripted configuration.

---

## Dependencies and Assumptions

**Dependencies**:
- Feature 001-vwan-core: vHub, shared services VNet, private DNS zones (already deployed).

**Assumptions**:
- Shared VNet has available address space (10.1.0.0/24 has room for 10.1.0.64/27 inbound subnet).
- P2S clients can route to shared VNet via vHub connection (already set up in 001).
- No outbound endpoint or forwarding rules needed for MVP (only private zones, not on-prem DNS).

---

## Out of Scope (Future)

- Outbound endpoint for on-prem/corporate DNS forwarding.
- Failover or HA (multiple inbound endpoints).
- Private resolver DNS monitoring/alerting.
- Integration with Azure Firewall for DNS security policies.

---

## Checklist

- [ ] Spec reviewed and approved.
- [ ] Bicep modules reviewed for correctness.
- [ ] Parameter schema and example parameters validated.
- [ ] Deployment tested manually in dev environment.
- [ ] Validation procedures confirmed working.
- [ ] WSL configuration updated to use resolver IP.
- [ ] Documentation complete and tested.

