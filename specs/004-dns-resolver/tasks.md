# Implementation Tasks: Azure DNS Private Resolver for Core Infrastructure

**Feature**: 004-dns-resolver  
**Created**: 2026-01-04  
**Sprint Goal**: Deploy DNS Private Resolver to enable private DNS resolution from P2S/WSL clients

## Task Organization

Tasks are organized by **User Story** to enable independent implementation and testing. Each user story represents a complete, deployable increment.

**Story Dependencies**:
- User Story 1 (P0) → Foundational, no dependencies
- User Story 2 (P0) → Depends on User Story 1 completion
- User Story 3 (P0) → Depends on User Story 2 completion
- User Story 4 (P1) → Can proceed in parallel with User Story 2

**Parallel Execution**: Tasks marked with `[P]` can be executed in parallel with other `[P]` tasks in the same phase.

## Implementation Strategy

**MVP Scope**: User Story 1 + User Story 2
- Deploys resolver with inbound endpoint.
- Validates resolver answers DNS queries correctly.
- Sufficient for P2S clients to use resolver IP.

**Incremental Delivery**:
1. Sprint 1: User Story 1 (Resolver deployed)
2. Sprint 2: User Story 2 (Resolver validated)
3. Sprint 3: User Story 3 (WSL integration)
4. Sprint 4: User Story 4 (Documentation)

---

## Phase 1: Setup and Initialization

### Story: Project Setup

- [X] T001 Create feature branch 004-dns-resolver from main and verify clean state
- [X] T002 Create specs/004-dns-resolver directory structure (research.md, data-model.md, contracts/, checklists/ done; add remaining)
- [X] T003 Create test validation scripts directory (scripts/test-dns-resolver.sh placeholder)

**Story Goal**: Repository and branch structure ready for implementation  
**Test**: All directories exist, branch is clean, no uncommitted changes

---

## Phase 2: User Story 1 - Deploy DNS Private Resolver (P0)

### Story Goal
DevOps engineers can deploy an Azure DNS Private Resolver into the core shared services VNet with an inbound endpoint, providing infrastructure for P2S clients to resolve private Azure resources.

### Independent Test Criteria
- [ ] Resolver deployed successfully via Bicep.
- [ ] Inbound subnet created with service delegation.
- [ ] Inbound endpoint created with auto-assigned private IP.
- [ ] Resolver appears in Azure Portal under rg-ai-core.
- [ ] Deployment is idempotent (re-run produces no unexpected changes).

### Implementation Tasks

#### Bicep Module Review and Testing

- [X] T004 [P] Review dns-resolver.bicep module for correctness (syntax, param defaults, outputs).
- [X] T005 [P] Validate Bicep syntax using `az bicep build bicep/modules/dns-resolver.bicep`.
- [X] T006 [P] Review main.bicep integration of resolver module (dependency order, params passed).
- [X] T007 [P] Validate parameter schema (dnsResolverName, dnsInboundSubnetPrefix types and defaults).
- [X] T008 Validate parameter example file (main.parameters.example.json has resolver params).

#### Deployment Validation

- [X] T009 Deploy core infrastructure with resolver: `az deployment sub create -n dns-core -l eastus2 -f bicep/main.bicep -p @bicep/main.parameters.example.json`.
- [X] T010 Verify resolver resource created: `az resource show -g rg-ai-core --resource-type Microsoft.Network/dnsResolvers -n dnsr-ai-shared`.
- [X] T011 Extract inbound endpoint IP from deployment outputs (dnsResolverInboundIp).
- [X] T012 Verify inbound endpoint exists: `az rest --method get --uri "/subscriptions/{subId}/resourceGroups/rg-ai-core/providers/Microsoft.Network/dnsResolvers/dnsr-ai-shared/inboundEndpoints"`.
- [X] T013 Verify inbound subnet exists in shared VNet: `az network vnet subnet show -g rg-ai-core --vnet-name vnet-ai-shared -n DnsInboundSubnet`.
- [X] T014 Verify subnet has service delegation: Check delegation name is "Microsoft.Network/dnsResolvers".
- [X] T015 Verify resolver is operational (no error state in Azure Portal).

#### Deployment Documentation

- [X] T016 Document resolver deployment output values (IP, resource IDs).
- [X] T017 Create deployment summary (timestamp, parameters used, resource counts).
- [X] T018 Record resolver configuration (subnet CIDR, endpoint IP, tags applied).

**Deliverables**:
- Resolver deployed and operational in core infrastructure.
- Inbound endpoint IP documented for client configuration.
- Deployment repeatability verified.

---

## Phase 3: User Story 2 - Validate Resolver Functionality (P0)

### Story Goal
Platform engineers can verify the resolver correctly answers DNS queries for private zones and public domains, ensuring clients can rely on it for all name resolution needs.

### Independent Test Criteria
- [ ] nslookup to resolver IP for private zone returns private endpoint IP.
- [ ] nslookup to resolver IP for public domain succeeds.
- [ ] HTTPS curl to private endpoint via resolved private IP succeeds (401/200, not 403).
- [ ] Resolver behaves consistently across multiple queries.
- [ ] Validation works from both P2S client (WSL) and shared VNet.

### Implementation Tasks

#### DNS Query Validation - Private Zones

- [X] T019 [P] Create validation script: `scripts/test-dns-resolver.sh` (basic structure).
- [X] T020 [P] Add Level 1 validation: Check resolver exists and inbound endpoint IP is set.
- [X] T021 [P] Add Level 2 validation: Query private ACR zone (acraihubk2lydtz5uba3q.azurecr.io).
- [X] T022 [P] Add Level 3 validation: Query private Key Vault zone (privatelink.vaultcore.azure.net).
- [X] T023 [P] Add Level 4 validation: Query private Storage zone (privatelink.blob.core.windows.net).
- [X] T024 [P] Add Level 5 validation: Query private SQL zone (privatelink.database.windows.net).
- [X] T025 Verify private ACR resolution returns 10.1.0.5 (or correct private endpoint IP).
- [X] T026 Verify private zone queries return private IPs (10.x.x.x pattern, not 20.x.x.x).

#### DNS Query Validation - Public Domains

- [X] T027 [P] Add public DNS validation: Query google.com via resolver IP.
- [X] T028 [P] Add public DNS validation: Query microsoft.com via resolver IP.
- [X] T029 Verify public domain queries succeed (return public IPs, not timeouts).
- [X] T030 Verify public DNS fallback works if primary (resolver) is unreachable (future; document approach).

#### Connectivity Validation

- [ ] T031 Test HTTPS curl to private ACR using resolved private IP: `curl -v https://acraihubk2lydtz5uba3q.azurecr.io/v2/`.
- [ ] T032 Verify curl connects to private IP (10.1.0.5), not public IP.
- [ ] T033 Verify HTTP response is 401 or 200 (not 403 Forbidden or timeout).
- [ ] T034 Test HTTPS connectivity to private Key Vault using resolved IP.
- [ ] T035 Test HTTPS connectivity to private Storage using resolved IP.

#### Validation Testing

- [ ] T036 Run validation script from WSL client (P2S connected): All tests pass.
- [ ] T037 Run validation script from jump box in shared VNet: All tests pass.
- [ ] T038 Test idempotency: Re-query resolver 5 times for same record; results consistent.
- [ ] T039 Test resolver under load: 100 rapid queries to same domain; all answer correctly.
- [ ] T040 Test resolver error handling: Query non-existent private record; resolver returns NXDOMAIN.
- [ ] T041 Document validation results (test dates, client types, pass/fail counts).

**Deliverables**:
- Automated validation script (`scripts/test-dns-resolver.sh`).
- Validation results documenting resolver functionality.
- Resolver confirmed working for private and public DNS.

---

## Phase 4: User Story 3 - Update Client Configuration (P0)

### Story Goal
Developers can configure WSL and other P2S clients to use the resolver inbound endpoint IP as primary DNS, enabling automatic private endpoint resolution without manual /etc/hosts entries.

### Independent Test Criteria
- [ ] WSL /etc/resolv.conf updated with resolver inbound IP as primary.
- [ ] WSL resolv.conf includes fallback public DNS server.
- [ ] WSL /etc/wsl.conf disables auto-generation (generateResolvConf = false).
- [ ] Private DNS resolution works from WSL after configuration.
- [ ] Configuration persists across WSL restart and Windows reboot.

### Implementation Tasks

#### WSL Template Updates

- [ ] T042 [P] Update specs/003-wsl-dns-config/templates/resolv.conf.template to use resolver IP.
- [ ] T043 [P] Document resolver IP placeholder in template comments.
- [ ] T044 [P] Update specs/003-wsl-dns-config/quickstart.md with resolver IP instead of 168.63.129.16.
- [ ] T045 [P] Add instruction: "Get resolver IP from core deployment outputs (dnsResolverInboundIp)".

#### Configuration Validation

- [ ] T046 Test WSL with resolver IP as primary nameserver: `nslookup acraihubk2lydtz5uba3q.azurecr.io`.
- [ ] T047 Verify resolved IP is private (10.1.0.5).
- [ ] T048 Test ACR curl via resolved private IP: `curl -v https://acraihubk2lydtz5uba3q.azurecr.io/v2/`.
- [ ] T049 Verify HTTP 401/200, not 403 or timeout.
- [ ] T050 Test other private resources (Key Vault, Storage) via resolver from WSL.
- [ ] T051 Test public DNS still works: `nslookup google.com` (fallback to 8.8.8.8 or similar).

#### Persistence Testing

- [ ] T052 Document current WSL /etc/resolv.conf (save backup).
- [ ] T053 Apply resolver IP configuration to /etc/resolv.conf.
- [ ] T054 Shut down WSL: `wsl --shutdown` from PowerShell.
- [ ] T055 Restart WSL; verify /etc/resolv.conf unchanged.
- [ ] T056 Re-test private DNS resolution after restart: `nslookup acraihubk2lydtz5uba3q.azurecr.io`.
- [ ] T057 Verify IP still 10.1.0.5 after restart.
- [ ] T058 Reboot Windows host; restart WSL.
- [ ] T059 Re-test private DNS resolution after Windows reboot.
- [ ] T060 Verify configuration persisted across reboot.

#### Documentation Updates

- [ ] T061 Add note to specs/003-wsl-dns-config/quickstart.md: "Prerequisites: Core infrastructure deployed with DNS resolver (feature 004)".
- [ ] T062 [P] Update specs/003-wsl-dns-config/data-model.md to reference resolver IP (not hardcoded 168.63.129.16).
- [ ] T063 [P] Update specs/003-wsl-dns-config/contracts/validation-contract.md to test resolver IP.

**Deliverables**:
- WSL templates updated to use resolver IP.
- WSL configuration tested and persistence verified.
- Cross-references to resolver feature (004) documented.

---

## Phase 5: User Story 4 - Documentation and Runbooks (P1)

### Story Goal
Operators and developers can understand resolver architecture, deploy it independently, and troubleshoot issues using comprehensive documentation.

### Independent Test Criteria
- [ ] Overview explains private DNS problem and resolver solution.
- [ ] Operational runbook documents deployment, parameter choices, validation.
- [ ] Troubleshooting guide covers common issues (resolver unreachable, zones not linked, etc.).
- [ ] Examples provided for ACR, Key Vault, Storage, App Service private endpoints.
- [ ] All documentation reviewed and tested for accuracy.

### Implementation Tasks

#### Core Documentation

- [ ] T064 [P] Create docs/core-infrastructure/dns-resolver-setup.md with overview section.
- [ ] T065 [P] Document resolver architecture (VNet, inbound subnet, endpoint, zone links).
- [ ] T066 [P] Document why resolver is needed (P2S client routing gap to private DNS zones).
- [ ] T067 [P] Document resolver scope (core shared services VNet, private zones linked).

#### Deployment Documentation

- [ ] T068 [P] Document prerequisites (core infrastructure deployed, private DNS zones exist).
- [ ] T069 [P] Document parameter choices (dnsResolverName, dnsInboundSubnetPrefix defaults).
- [ ] T070 [P] Document how to obtain resolver inbound IP from deployment outputs.
- [ ] T071 [P] Document idempotency and safe re-deployment.
- [ ] T072 [P] Provide example deployment command with parameters filled in.

#### Validation Documentation

- [ ] T073 [P] Document DNS validation steps (nslookup private zones, public domains).
- [ ] T074 [P] Document connectivity validation (curl to private endpoints).
- [ ] T075 [P] Document how to run validation script (scripts/test-dns-resolver.sh).
- [ ] T076 [P] Add expected outputs for each validation check.

#### Troubleshooting Guide

- [ ] T077 [P] Document "Resolver not found" troubleshooting.
- [ ] T078 [P] Document "Private DNS queries timeout" troubleshooting (routing, zone links).
- [ ] T079 [P] Document "Queries return public IP instead of private" troubleshooting (zone link missing).
- [ ] T080 [P] Document "Public DNS queries fail" troubleshooting (recursive query issue).
- [ ] T081 [P] Document "Resolver IP changes after re-deployment" (document stability expectations).

#### Examples and Integration

- [ ] T082 [P] Add example: Configuring WSL to use resolver IP.
- [ ] T083 [P] Add example: ACR authentication via resolver-resolved private endpoint.
- [ ] T084 [P] Add example: Key Vault access via resolver.
- [ ] T085 [P] Add example: Storage account access via resolver.
- [ ] T086 [P] Add example: App Service private endpoint resolution via resolver.
- [ ] T087 [P] Add FAQ: "Do I need to change my DNS if resolver is deployed?" (Answer: Yes, for P2S clients; other VNet resources auto-detect).

#### Integration with Existing Docs

- [ ] T088 Update docs/core-infrastructure/README.md with resolver section.
- [ ] T089 Update docs/core-infrastructure/troubleshooting.md with resolver DNS troubleshooting.
- [ ] T090 Add cross-references between resolver docs and WSL feature (003) docs.
- [ ] T091 Update docs/registry/README.md prerequisites to mention resolver (for WSL users).
- [ ] T092 Create DNS resolver deployment reference architecture diagram (ASCII or Markdown table).

#### Testing and Validation

- [ ] T093 [P] Test all documentation commands on fresh WSL instance.
- [ ] T094 [P] Verify all example outputs match actual resolver responses.
- [ ] T095 [P] Review documentation for grammar, clarity, and completeness.
- [ ] T096 [P] Validate all cross-references and links work.

**Deliverables**:
- Complete DNS resolver documentation (setup, validation, troubleshooting).
- Integrated with core infrastructure docs.
- All examples tested and validated.

---

## Phase 6: Polish and Cross-Cutting Concerns

### Story Goal
Code quality, consistency, and professional polish across all deliverables.

### Implementation Tasks

#### Code Quality

- [ ] T097 [P] Review dns-resolver.bicep for style consistency (naming, comments, formatting).
- [ ] T098 [P] Add header comment to dns-resolver.bicep (purpose, inputs, outputs).
- [ ] T099 [P] Verify all parameter descriptions are clear and complete.
- [ ] T100 [P] Add inline comments explaining inbound subnet delegation and endpoint IP allocation.

#### Script Enhancement

- [ ] T101 [P] Add header comment to scripts/test-dns-resolver.sh (purpose, usage, author, date).
- [ ] T102 [P] Add colored output to validation script (✅ PASS, ❌ FAIL, ⚠️ WARNING).
- [ ] T103 [P] Add progress messages for each validation step.
- [ ] T104 [P] Add summary output (X passed, Y failed, overall status).
- [ ] T105 [P] Make script executable: `chmod +x scripts/test-dns-resolver.sh`.

#### Testing and Validation

- [ ] T106 End-to-end test: Deploy core, validate resolver, configure WSL, test private endpoint access.
- [ ] T107 Test resolver re-deployment (idempotency): Apply Bicep twice, verify no unwanted changes.
- [ ] T108 Test resolver with multiple P2S clients (jump box + WSL): Both resolve private endpoints.
- [ ] T109 Test resolver failover behavior (unplug VPN): Resolver IP unreachable, fallback DNS works.
- [ ] T110 Test resolver scaling (100+ concurrent queries): Performance remains <100ms per query.

#### Documentation Polish

- [ ] T111 [P] Spell-check and grammar-check all documentation.
- [ ] T112 [P] Ensure consistent terminology across all docs (resolver, inbound endpoint, zone, etc.).
- [ ] T113 [P] Validate all code blocks have proper syntax highlighting hints (```bash, ```json, etc.).
- [ ] T114 [P] Ensure all links and cross-references are formatted correctly (Markdown links).
- [ ] T115 [P] Review and update timestamps/dates in all documents.

#### Integration and Compliance

- [ ] T116 Verify Bicep modules follow constitution standards (naming, tagging, organization).
- [ ] T117 Verify feature doesn't violate security principles (no secrets, no hardcoded IPs beyond defaults).
- [ ] T118 Verify feature integrates properly with existing core infrastructure (no breaking changes).
- [ ] T119 Verify feature enables future expansion (spokes, outbound endpoint for forwarding).
- [ ] T120 Create summary document: Feature 004 completeness checklist, integration status, next steps.

**Deliverables**:
- Production-ready Bicep, scripts, and documentation.
- Integration and compliance verified.
- Feature ready for merge to main branch.

---

## Dependencies Between User Stories

```
User Story 1 (P0): Deploy Resolver
    ↓ (resolver must exist)
User Story 2 (P0): Validate Resolver
    ↓ (validation must pass)
User Story 3 (P0): Update Client Config
    ↓ (clients must be configured)
User Story 4 (P1): Documentation
    (Can proceed in parallel with US2 once initial docs exist)
```

**Critical Path**: US1 → US2 → US3  
**Parallel Work**: US4 documentation can begin once US1 is complete (has content to document).

---

## Parallel Execution Opportunities

### Within User Story 1 (P0)
- T004, T005, T006, T007 (Bicep review) can be done in parallel.
- T010, T011, T012, T013, T014 (Deployment verification) can be partially parallelized (after T009 deployment).

### Within User Story 2 (P0)
- T020–T024 (Zone validation tasks) can be done in parallel.
- T027–T029 (Public DNS validation) can be done in parallel.
- T031–T035 (Connectivity tests) can be done in parallel (different zones).

### Within User Story 3 (P0)
- T042, T043, T044, T045 (Template updates) can be done in parallel.
- T052–T060 (WSL restart testing) must be sequential (depends on previous steps).

### Within User Story 4 (P1)
- T064–T067 (Overview docs) can be written in parallel.
- T068–T072 (Deployment docs) can be written in parallel.
- T073–T076 (Validation docs) can be written in parallel.
- T077–T086 (Troubleshooting & examples) can be written in parallel.
- T088–T092 (Integration) can be done in parallel.
- T093–T096 (Testing) can be done in parallel.

### Within User Story 6 (Polish)
- T097–T105 (Code quality & scripts) can be done in parallel.
- T111–T115 (Documentation polish) can be done in parallel.

---

## Task Summary

**Total Tasks**: 120
- Phase 1 (Setup): 3 tasks
- Phase 2 (US1 - Deploy Resolver): 15 tasks
- Phase 3 (US2 - Validate Resolver): 23 tasks
- Phase 4 (US3 - Client Config): 19 tasks
- Phase 5 (US4 - Documentation): 29 tasks
- Phase 6 (Polish): 31 tasks

**Parallelizable Tasks**: 68 tasks marked with [P]

**Estimated Effort**:
- User Story 1 (P0): 4–6 hours (deployment + verification)
- User Story 2 (P0): 6–8 hours (validation + testing)
- User Story 3 (P0): 3–4 hours (configuration + integration)
- User Story 4 (P1): 8–12 hours (comprehensive documentation)
- Polish: 4–6 hours (code quality, integration tests)
- **Total**: 25–36 hours

**Recommended Approach**: Implement in story order (US1 → US2 → US3) for incremental delivery. US4 can begin once US1 is complete.

---

## Success Validation

After all tasks complete, the feature is successful if:

- ✅ **SC-001**: Bicep deployment completes; resolver and inbound endpoint created and operational.
- ✅ **SC-002**: Inbound endpoint IP reachable via nslookup from P2S client address pool.
- ✅ **SC-003**: Queries for private zones return private endpoint IPs (10.x.x.x).
- ✅ **SC-004**: Public domain queries work via resolver.
- ✅ **SC-005**: HTTPS to private endpoints via resolver-resolved IPs works.
- ✅ **SC-006**: Resolver resolves correctly from WSL when configured with inbound IP.
- ✅ **SC-007**: Re-deployment is safe (idempotent, no unwanted changes).
- ✅ **SC-008**: Documentation enables independent deployment and troubleshooting.

All success criteria from spec.md must be validated before marking feature complete.

