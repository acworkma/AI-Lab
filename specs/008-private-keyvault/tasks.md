# Tasks: Private Azure Key Vault Infrastructure

**Input**: Design documents from `/specs/008-private-keyvault/`  
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Tests**: No automated tests requested - validation via shell scripts and Azure CLI assertions.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Exact file paths included in descriptions

---

## Phase 1: Setup

**Purpose**: Project initialization and directory structure

- [X] T001 Create bicep/keyvault/ directory structure
- [X] T002 [P] Create bicep/keyvault/main.parameters.example.json with documented parameter examples
- [X] T003 [P] Create docs/keyvault/ directory for documentation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Reusable module that all user stories depend on

**⚠️ CRITICAL**: User story implementation cannot begin until this phase is complete

- [X] T004 Create bicep/modules/key-vault.bicep with Key Vault resource, private endpoint, and DNS zone group per data-model.md
- [X] T005 Add parameter validation decorators (minLength, maxLength, allowed values) in bicep/modules/key-vault.bicep
- [X] T006 Add module outputs (name, id, uri, privateEndpointIp) in bicep/modules/key-vault.bicep

**Checkpoint**: Reusable Key Vault module ready - orchestration and scripts can proceed

---

## Phase 3: User Story 1 - Deploy Private Key Vault (Priority: P1) 🎯 MVP

**Goal**: Deploy Key Vault with private endpoint, RBAC authorization, and DNS integration

**Independent Test**: Deploy to rg-ai-keyvault, verify private endpoint, confirm public access disabled, validate DNS resolution

### Implementation for User Story 1

- [X] T007 [US1] Create bicep/keyvault/main.bicep orchestration template (subscription scope, creates RG, references core infrastructure)
- [X] T008 [US1] Add existing resource references in main.bicep (vnet, subnet, privateDnsZone from rg-ai-core)
- [X] T009 [US1] Wire Key Vault module call in main.bicep with all required parameters
- [X] T010 [US1] Add deployment outputs in main.bicep (keyVaultName, keyVaultUri, keyVaultId, privateEndpointIp)
- [X] T011 [US1] Create bicep/keyvault/main.parameters.json with dev environment defaults
- [X] T012 [P] [US1] Create scripts/validate-keyvault.sh with pre-deployment checks (Azure login, core infrastructure, no soft-deleted vault collision)
- [X] T013 [US1] Create scripts/deploy-keyvault.sh following deploy-storage.sh pattern (what-if, confirmation, deployment, timing)
- [X] T014 [P] [US1] Create scripts/validate-keyvault-dns.sh for DNS resolution verification from VPN
- [X] T015 [P] [US1] Create scripts/cleanup-keyvault.sh for resource deletion

**Checkpoint**: Key Vault deployable and verifiable - foundational secret storage available

---

## Phase 4: User Story 2 - Manage Secrets via CLI (Priority: P2)

**Goal**: Enable CRUD operations on secrets from VPN-connected clients

**Independent Test**: Connect via VPN, run `az keyvault secret set/show/list`, verify operations succeed

### Implementation for User Story 2

- [X] T016 [US2] Add RBAC role assignment guidance to docs/keyvault/README.md (Key Vault Secrets Officer)
- [X] T017 [US2] Create scripts/grant-keyvault-roles.sh for assigning RBAC roles to users/service principals
- [X] T018 [US2] Add secret operations examples to quickstart.md (set, show, list, delete commands)
- [X] T019 [US2] Update validate-keyvault.sh to include post-deployment secret operation test
- [X] T019a [US2] Validate secret operation latency (<100ms per NFR-001) and document timing in deployment output

**Checkpoint**: Secrets can be managed via CLI from VPN-connected clients

---

## Phase 5: User Story 3 - Bicep Reference Integration (Priority: P3)

**Goal**: Other projects can reference secrets via Bicep parameter files

**Independent Test**: Create parameter file with Key Vault reference, deploy resource using referenced secret

### Implementation for User Story 3

- [X] T020 [P] [US3] Create bicep/keyvault/main.keyvault-ref.parameters.example.json showing Key Vault reference syntax
- [X] T021 [US3] Document Bicep parameter file reference patterns in docs/keyvault/README.md
- [X] T022 [US3] Add .bicepparam syntax examples to docs/keyvault/README.md

**Checkpoint**: Integration pattern documented for other projects to consume secrets

---

## Phase 6: Polish & Documentation

**Purpose**: Complete documentation and cross-cutting concerns

- [X] T023 [P] Create docs/keyvault/README.md with all required sections (Overview, Prerequisites, Architecture, Deployment, Configuration, Testing, Cleanup, Troubleshooting)
- [X] T024 [P] Add inline Bicep comments explaining security decisions in bicep/modules/key-vault.bicep
- [X] T025 Update main README.md to add Key Vault as infrastructure project in the hub-spoke diagram
- [X] T026 Run quickstart.md validation steps end-to-end
- [X] T027 Validate Bicep templates with `az bicep build` and `az deployment sub what-if`

---

## Dependencies & Execution Order

### Phase Dependencies

```text
Phase 1 (Setup)
    │
    ▼
Phase 2 (Foundational) ─── BLOCKS ALL USER STORIES
    │
    ├──────────────┬──────────────┐
    ▼              ▼              ▼
Phase 3 (US1)   Phase 4 (US2)  Phase 5 (US3)
   P1              P2             P3
    │              │              │
    └──────────────┴──────────────┘
                   │
                   ▼
            Phase 6 (Polish)
```

### User Story Dependencies

- **US1 (Deploy Key Vault)**: Depends only on Foundational phase - can proceed immediately after Phase 2
- **US2 (Manage Secrets)**: Depends on US1 completion (needs deployed Key Vault to manage secrets)
- **US3 (Bicep References)**: Depends on US1 completion (needs Key Vault for reference examples)

### Within Each Phase

- Tasks marked [P] can run in parallel
- Sequential tasks must complete in order
- All tasks in a phase should complete before moving to next phase

### Parallel Opportunities

**Phase 1**: T002 and T003 can run in parallel  
**Phase 2**: T004 blocks T005 and T006 (module must exist first)  
**Phase 3**: T012, T014, T015 can run in parallel after T011  
**Phase 5**: T020 can start immediately, T021/T022 can run in parallel  
**Phase 6**: T023 and T024 can run in parallel

---

## Parallel Example: User Story 1

```bash
# After T011 completes, these can run in parallel:
# Terminal 1: T012 - validate-keyvault.sh
# Terminal 2: T014 - validate-keyvault-dns.sh
# Terminal 3: T015 - cleanup-keyvault.sh

# Then sequentially:
# T013 - deploy-keyvault.sh (may use validate script)
```

---

## Task Summary

| Phase | Tasks | Parallel | Description |
|-------|-------|----------|-------------|
| 1 - Setup | T001-T003 | 2 | Directory structure |
| 2 - Foundational | T004-T006 | 0 | Key Vault module |
| 3 - US1 (P1) | T007-T015 | 3 | Deploy infrastructure |
| 4 - US2 (P2) | T016-T019 | 0 | Secret management |
| 5 - US3 (P3) | T020-T022 | 1 | Bicep integration |
| 6 - Polish | T023-T027 | 2 | Documentation |
| **Total** | **27** | **8** | |

---

## Implementation Strategy

### MVP Scope (User Story 1 Only)
Complete Phases 1-3 for a functional, secure Key Vault:
- ✅ Bicep module with private endpoint
- ✅ Deployment and validation scripts
- ✅ DNS resolution verification

### Full Implementation
Complete all phases for production-ready feature:
- ✅ MVP (Phases 1-3)
- ✅ Secret management workflows (Phase 4)
- ✅ Integration patterns (Phase 5)
- ✅ Complete documentation (Phase 6)

### Suggested Execution Order
1. **Day 1**: Phases 1-2 (Setup + Module) - ~1 hour
2. **Day 1**: Phase 3 (US1 - Deploy) - ~2 hours
3. **Day 2**: Phases 4-5 (US2 + US3) - ~1 hour
4. **Day 2**: Phase 6 (Polish) - ~1 hour

**Estimated Total**: ~5 hours for full implementation
