---

description: "Task list for storage account with CMK feature"
---

# Tasks: 005-storage-cmk

**Input**: Design documents from `/specs/005-storage-cmk/`
**Prerequisites**: plan.md (required), spec.md (user stories), research.md, data-model.md, contracts/

**Tests**: Tests are not explicitly requested; include validation tasks for deployments and ops.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [ ] T001 Create Bicep module scaffold `bicep/modules/storage.bicep`
- [ ] T002 Create orchestration scaffold `bicep/storage/main.bicep`
- [ ] T003 Create parameter template `bicep/storage/main.parameters.example.json`
- [ ] T004 Create script stubs `scripts/deploy-storage.sh` and `scripts/validate-storage.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core prerequisites before any user story

- [ ] T005 Populate `bicep/storage/main.parameters.json` with required parameters (name, location, kv, vnet, dns)
- [ ] T006 Implement prerequisite checks in `scripts/validate-storage.sh` (rg-ai-core, kv-ai-core, vnet, dns zone)
- [ ] T007 Align `docs/storage/README.md` prerequisites with validate script outputs

**Checkpoint**: Foundation ready - user story implementation can begin

---

## Phase 3: User Story 1 - Deploy Private Storage Account with CMK (Priority: P1) 🎯 MVP

**Goal**: Deploy storage account with CMK, private endpoint, diagnostics
**Independent Test**: Deploy module to `rg-ai-storage`, verify CMK, private endpoint, DNS, public access disabled

- [ ] T008 [US1] Implement managed identity resource in `bicep/modules/storage.bicep`
- [ ] T009 [P] [US1] Implement Key Vault key + rotation policy (cross-RG reference) in `bicep/modules/storage.bicep`
- [ ] T010 [US1] Implement RBAC assignment (Key Vault Crypto Service Encryption User) in `bicep/modules/storage.bicep`
- [ ] T011 [US1] Implement storage account (CMK, publicNetworkAccess Disabled, shared keys off, TLS1_2) in `bicep/modules/storage.bicep`
- [ ] T012 [US1] Implement blob service config (soft delete, versioning toggle) in `bicep/modules/storage.bicep`
- [ ] T013 [US1] Implement private endpoint + DNS zone group in `bicep/modules/storage.bicep`
- [ ] T014 [US1] Implement diagnostic settings (account + blob) in `bicep/modules/storage.bicep`
- [ ] T015 [US1] Add outputs (ids, endpoints, private IP, principalId) in `bicep/modules/storage.bicep`
- [ ] T016 [US1] Wire orchestration to module with RG creation and core references in `bicep/storage/main.bicep`
- [ ] T017 [P] [US1] Fill `bicep/storage/main.parameters.json` with sample values (stailab001, eastus, kv-ai-core, vnet-ai-sharedservices)
- [ ] T018 [US1] Implement `scripts/deploy-storage.sh` (subscription deployment, parameters, tags)
- [ ] T019 [US1] Implement `scripts/validate-storage.sh` (what-if, CMK, public access, private endpoint status)
- [ ] T020 [P] [US1] Implement `scripts/validate-storage-dns.sh` (DNS zone link, A record existence)
- [ ] T021 [US1] Align `docs/storage/README.md` deployment steps with module params and scripts

---

## Phase 4: User Story 2 - Manage Storage Account Data (Priority: P2)

**Goal**: Data operations via CLI/SDK over VPN
**Independent Test**: Upload/download via CLI with `--auth-mode login`, verify audit logs

- [ ] T022 [US2] Add `scripts/grant-storage-roles.sh` (assign Storage Blob Data Contributor to user)
- [ ] T023 [P] [US2] Add `scripts/storage-ops.sh` (create container, upload, list, download with `--auth-mode login`)
- [ ] T024 [US2] Update `specs/005-storage-cmk/quickstart.md` with ops script references and audit log query
- [ ] T025 [US2] Update `docs/storage/README.md` with Log Analytics queries for storage ops
- [ ] T026 [US2] Add `scripts/validate-storage-ops.sh` to run ops and assert exit codes

---

## Phase 5: User Story 3 - Integrate with Existing Infrastructure (Priority: P3)

**Goal**: Consistent patterns, idempotency, documentation
**Independent Test**: Structure matches existing modules; what-if/idempotency clean; docs cross-linked

- [ ] T027 [US3] Ensure module pattern matches `bicep/modules/acr.bicep` (naming, params, outputs)
- [ ] T028 [P] [US3] Extend validate script (or add `scripts/what-if-storage.sh`) to include idempotency redeploy check
- [ ] T029 [US3] Update root `README.md` Projects section with storage link
- [ ] T030 [US3] Update `docs/core-infrastructure/README.md` with reference to storage module
- [ ] T031 [US3] Add `tests/storage/README.md` (validation suite: what-if, validate-storage, storage-ops)

---

## Final Phase: Polish & Cross-Cutting

- [ ] T032 [P] Add `scripts/lint-bicep.sh` to run `bicep build` and `bicep lint` on storage modules
- [ ] T033 [P] Add `.github/workflows/bicep.yml` to lint storage modules
- [ ] T034 Review `specs/005-storage-cmk/plan.md` for alignment with implemented module

---

## Dependencies

- **Story order**: US1 → US2 → US3
- **Phase order**: Setup → Foundational → US1 → US2 → US3 → Polish

## Parallel Execution Examples

- **Within US1**: T009 (Key Vault key) can run in parallel with T017 (parameters) and T020 (DNS validation script)
- **Within US2**: T023 (ops script) can run in parallel with T025 (docs updates)
- **Cross-story**: US2 tasks must wait for US1 deployment; US3 tasks can start after module structure lands (post T016)

## Implementation Strategy

- **MVP Scope**: Complete US1 (P1) — deploy CMK-enabled storage with private endpoint and validations
- **Incremental Delivery**: US2 adds data ops scripts; US3 aligns patterns and docs; Polish adds linting/CI

