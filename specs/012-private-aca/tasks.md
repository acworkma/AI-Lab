---

description: "Task list for Private Azure Container Apps infrastructure"
---

# Tasks: 012-private-aca

**Input**: Design documents from `/specs/012-private-aca/`
**Prerequisites**: plan.md (required), spec.md (user stories)

**Tests**: Tests are not explicitly requested; include validation tasks for deployments and DNS resolution.

**Organization**: Tasks grouped by phase to enable systematic implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 0: Core Infrastructure Changes (Blocking)

**Purpose**: Modify shared infrastructure to support ACA

- [X] T001 [US1] Expand shared services VNet from /24 to /22 in `bicep/modules/shared-services-vnet.bicep`
- [X] T002 [US1] Add ACA subnet (10.1.2.0/23) with Microsoft.App/environments delegation
- [X] T003 [US1] Add NSG for ACA subnet with VPN client inbound rules
- [X] T004 [P] [US1] Add `privatelink.azurecontainerapps.io` DNS zone to `bicep/modules/private-dns-zones.bicep`
- [X] T005 [P] [US1] Add DNS zone outputs (acaDnsZoneId, acaDnsZoneName)

---

## Phase 1: Bicep Modules

**Purpose**: Create reusable modules for ACA and Log Analytics

- [X] T006 [US1] Create `bicep/modules/aca-environment.bicep` with ACA environment resource
- [X] T007 [US1] Add VNet injection config (infrastructureSubnetId, internal: true)
- [X] T008 [US1] Add private endpoint with DNS zone group auto-registration
- [X] T009 [US1] Add Consumption workload profile configuration
- [X] T010 [US1] Add Log Analytics integration (customerId, sharedKey)
- [X] T011 [P] [US1] Create `bicep/modules/log-analytics.bicep` with workspace resource

---

## Phase 2: Orchestration Template

**Purpose**: Subscription-scoped deployment orchestration

- [X] T012 [US1] Create `bicep/aca/main.bicep` with subscription scope
- [X] T013 [US1] Add cross-RG references (VNet, subnets, DNS zone from rg-ai-core)
- [X] T014 [US1] Add conditional Log Analytics deployment (existingLogAnalyticsWorkspaceId)
- [X] T015 [US1] Wire up all module references and outputs
- [X] T016 [P] [US3] Create `bicep/aca/main.parameters.json` with dev defaults
- [X] T017 [P] [US3] Create `bicep/aca/main.parameters.example.json` with descriptions

---

## Phase 3: Deployment Scripts

**Purpose**: Shell script automation following repo patterns

- [X] T018 [US3] Create `scripts/deploy-aca.sh` with what-if → confirm → deploy flow
- [X] T019 [US3] Create `scripts/validate-aca.sh` with pre-deploy and deployed validation
- [X] T020 [P] [US3] Create `scripts/validate-aca-dns.sh` with DNS resolution testing
- [X] T021 [P] [US3] Create `scripts/cleanup-aca.sh` with confirm → delete flow
- [ ] T022 Make all scripts executable (chmod +x)

---

## Phase 4: Documentation & Specs

**Purpose**: Complete project documentation

- [X] T023 [US3] Create `docs/aca/README.md` following keyvault README pattern
- [X] T024 [US3] Create `specs/012-private-aca/spec.md` with feature specification
- [X] T025 [P] [US3] Create `specs/012-private-aca/plan.md` with implementation plan
- [X] T026 [P] [US3] Create `specs/012-private-aca/tasks.md` (this file)
- [ ] T027 [P] [US3] Create `specs/012-private-aca/checklists/requirements.md`
- [ ] T028 [US3] Update root `README.md` with ACA project entry

---

## Phase 5: Validation

**Purpose**: Verify all files are syntactically correct

- [ ] T029 Run `az bicep build` on `bicep/aca/main.bicep` to validate syntax
- [ ] T030 Verify all parameter files have valid JSON
- [ ] T031 Run shellcheck on all scripts (if available)
