# Tasks: Storage CMK Refactor

**Input**: Design documents from `/specs/010-storage-cmk-refactor/`
**Prerequisites**: plan.md (✅), spec.md (✅), research.md (✅), data-model.md (✅), contracts/ (✅)

**Tests**: No automated tests requested - validation via Azure CLI scripts

**Organization**: Tasks grouped by user story to enable independent implementation

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3)
- Paths based on plan.md project structure

---

## Phase 1: Setup

**Purpose**: Project initialization and parameter files

- [X] T001 Create parameter file bicep/storage/main.parameters.example.json with documented defaults
- [X] T002 [P] Create parameter file bicep/storage/main.parameters.json for deployment (gitignored secrets)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core Bicep orchestration that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until main.bicep structure is complete

- [X] T003 Refactor bicep/storage/main.bicep to reference existing storage account and key vault (remove resource creation)
- [X] T004 Add existing resource references for Key Vault in rg-ai-keyvault (cross-RG scope)
- [X] T005 [P] Add existing resource references for Storage Account in rg-ai-storage
- [X] T006 Define all parameters per contracts/bicep-interface.md in bicep/storage/main.bicep
- [X] T007 Define all outputs per contracts/bicep-interface.md in bicep/storage/main.bicep

**Checkpoint**: Foundation ready - Bicep can reference existing infrastructure

---

## Phase 3: User Story 1 - Enable CMK on Existing Storage Account (Priority: P1) 🎯 MVP

**Goal**: Enable CMK encryption using Key Vault key on existing Storage Account

**Independent Test**: Run `./scripts/deploy-storage.sh` and verify CMK is active via `az storage account show --query encryption.keySource`

### Implementation for User Story 1

- [X] T008 [US1] Create user-assigned managed identity resource in bicep/storage/main.bicep
- [X] T009 [US1] Create encryption key `storage-encryption-key` (RSA 4096) with P18M rotation policy using bicep/modules/storage-key.bicep (cross-RG module call)
- [X] T010 [US1] Create RBAC role assignment using bicep/modules/storage-rbac.bicep for Key Vault Crypto Service Encryption User
- [X] T011 [US1] Update Storage Account encryption configuration to use CMK (keySource: Microsoft.Keyvault) — handle edge case: detect existing CMK config before overwriting
- [X] T012 [US1] Add user-assigned identity to Storage Account identity property
- [X] T013 [US1] Create scripts/deploy-storage.sh with what-if and deployment modes
- [X] T014 [US1] Update scripts/validate-storage.sh to check CMK status, key name, key version

**Checkpoint**: User Story 1 complete - CMK encryption is functional

---

## Phase 4: User Story 2 - Validate Prerequisites Before Deployment (Priority: P2)

**Goal**: Pre-flight checks ensure Key Vault and Storage Account exist before CMK deployment

**Independent Test**: Run `./scripts/deploy-storage.sh --what-if` against environment without Key Vault, verify clear error message

### Implementation for User Story 2

- [X] T015 [US2] Add prerequisite validation function to scripts/deploy-storage.sh (check rg-ai-keyvault exists)
- [X] T016 [US2] Add prerequisite validation function to scripts/deploy-storage.sh (check Key Vault exists in RG)
- [X] T017 [US2] Add prerequisite validation function to scripts/deploy-storage.sh (check rg-ai-storage exists)
- [X] T018 [US2] Add prerequisite validation function to scripts/deploy-storage.sh (check Storage Account exists in RG)
- [X] T019 [US2] Add prerequisite validation for Key Vault soft-delete and purge protection enabled
- [X] T020 [US2] Display clear error messages with remediation steps when prerequisites fail

**Checkpoint**: User Story 2 complete - Deployment fails gracefully with clear guidance

---

## Phase 5: User Story 3 - Manage Encryption Key Lifecycle (Priority: P3)

**Goal**: Display key details in validation script for lifecycle management

**Independent Test**: Run `./scripts/validate-storage.sh` and verify key version, rotation policy displayed

### Implementation for User Story 3

- [X] T021 [US3] Extend scripts/validate-storage.sh to display encryption key URI (versionless)
- [X] T022 [US3] Extend scripts/validate-storage.sh to display current key version
- [X] T023 [US3] Extend scripts/validate-storage.sh to display key rotation policy (P18M interval, P2Y expiry)
- [X] T024 [US3] Extend scripts/validate-storage.sh to display managed identity name and principal ID

**Checkpoint**: User Story 3 complete - Key lifecycle information visible

---

## Phase 6: Polish & Documentation

**Purpose**: Documentation updates and final validation

- [X] T025 [P] Update docs/storage/README.md with refactored CMK architecture
- [X] T026 [P] Add CMK deployment section to docs/storage/README.md (deployment order, prerequisites)
- [X] T027 [P] Add troubleshooting section to docs/storage/README.md per quickstart.md edge cases
- [ ] T028 Run specs/010-storage-cmk-refactor/quickstart.md end-to-end validation
- [ ] T029 Verify deployment idempotency (redeploy produces no changes)

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)           → No dependencies
Phase 2 (Foundational)    → Depends on Phase 1, BLOCKS Phase 3-5
Phase 3 (US1 - CMK)       → Depends on Phase 2 ← MVP STOP POINT
Phase 4 (US2 - Validate)  → Depends on Phase 2 (can parallel with Phase 3)
Phase 5 (US3 - Lifecycle) → Depends on Phase 2 (can parallel with Phase 3-4)
Phase 6 (Polish)          → Depends on Phase 3-5
```

### User Story Dependencies

| Story | Can Start After | Independent Test |
|-------|----------------|------------------|
| US1 (P1) | Phase 2 complete | Deploy CMK, verify `keySource: Microsoft.Keyvault` |
| US2 (P2) | Phase 2 complete | Run without prerequisites, verify error messages |
| US3 (P3) | Phase 2 complete | Run validation, verify key details displayed |

### Within Each User Story

1. Bicep resources/updates before scripts
2. Deploy script before validate script
3. Core functionality before extended features

### Parallel Opportunities

**Phase 1**:
```
T001 (example params) || T002 (actual params)
```

**Phase 2**:
```
T004 (KV reference) || T005 (Storage reference)
```

**Phase 3+ (After Phase 2)**:
```
Phase 3 (US1) || Phase 4 (US2) || Phase 5 (US3)  # Different files, no conflicts
```

**Phase 6**:
```
T025 || T026 || T027  # All docs updates
```

---

## Parallel Example: User Stories

After Phase 2 (Foundational) completes, all three user stories can proceed in parallel:

```bash
# Parallel execution possible:
Developer A: T008-T014 (US1 - CMK Implementation)
Developer B: T015-T020 (US2 - Prerequisites)
Developer C: T021-T024 (US3 - Key Lifecycle)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. ✅ Complete Phase 1: Setup (T001-T002)
2. ✅ Complete Phase 2: Foundational (T003-T007)
3. ✅ Complete Phase 3: User Story 1 (T008-T014)
4. **STOP and VALIDATE**: Run `./scripts/deploy-storage.sh` and verify CMK active
5. Deploy if ready - MVP complete!

### Incremental Delivery

1. Setup + Foundational → Infrastructure references ready
2. Add US1 (CMK) → Test independently → **MVP Deployed** ✅
3. Add US2 (Validation) → Improves deployment experience
4. Add US3 (Lifecycle) → Enables key management visibility
5. Polish → Documentation complete

---

## Notes

- All Bicep changes are in bicep/storage/main.bicep (refactored, not new)
- Existing modules (storage-key.bicep, storage-rbac.bicep) are reused via cross-RG calls
- No automated tests - validation via Azure CLI scripts
- Each checkpoint allows deployment validation before continuing
- Commit after each task or logical group (e.g., T008-T012 together)
