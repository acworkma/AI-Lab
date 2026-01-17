# Tasks: APIM Storage OAuth Demo

**Input**: Design documents from `/specs/007-apim-storage-oauth/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Exact file paths included in descriptions

## Path Conventions

Based on plan.md structure:
- **Bicep/IaC**: `bicep/apim/apis/`, `bicep/apim/policies/`
- **Scripts**: `scripts/`
- **Docs**: `docs/apim/`

---

## Phase 1: Setup (Project Structure)

**Purpose**: Create directory structure and grant RBAC permissions

- [X] T001 Create directory structure: `bicep/apim/apis/` and `bicep/apim/policies/`
- [X] T002 Create RBAC script: `scripts/grant-apim-storage-role.sh` to assign Storage Blob Data Contributor to APIM MI
- [X] T003 Run RBAC script to grant APIM managed identity access to stailab001 storage account

---

## Phase 2: Foundational (Core APIM Infrastructure)

**Purpose**: Create shared APIM policies and API definition that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create JWT validation policy in `bicep/apim/policies/jwt-validation.xml` with Entra ID OIDC config
- [X] T005 [P] Create base storage operations policy in `bicep/apim/policies/storage-operations.xml` with managed identity auth
- [X] T006 Create Storage API Bicep module in `bicep/apim/apis/storage-api.bicep` with all 4 operations
- [X] T007 [P] Create deployment script `scripts/deploy-storage-api.sh` for API deployment

**Checkpoint**: API structure deployed to APIM ✅ - user story implementation can now begin

---

## Phase 3: User Story 1 - Upload File (Priority: P1) 🎯 MVP

**Goal**: Authenticated clients can upload files to blob storage via APIM

**Independent Test**: `curl -X PUT .../storage/files/test.txt` with valid token returns 201 and file appears in storage

### Implementation for User Story 1

- [X] T008 [US1] Implement upload operation policy in `bicep/apim/policies/storage-operations.xml` (PUT /files/{filename})
- [X] T009 [US1] Add x-ms-blob-type and x-ms-version headers for BlockBlob upload
- [X] T010 [US1] Implement 201 response transformation with blob metadata (name, etag, contentLength)
- [X] T011 [US1] Add error handling for 400/401/413 responses in upload operation
- [X] T012 [US1] Deploy and test upload operation with curl command

**Checkpoint**: User Story 1 complete ✅ - can upload files via OAuth-protected API

---

## Phase 4: User Story 2 - List Files (Priority: P1)

**Goal**: Authenticated clients can list all files in the storage container

**Independent Test**: `curl -X GET .../storage/files` with valid token returns JSON array of files

### Implementation for User Story 2

- [X] T013 [US2] Implement list operation policy in `bicep/apim/policies/storage-operations.xml` (GET /files)
- [X] T014 [US2] Add Storage List Blobs URL construction with restype=container&comp=list
- [X] T015 [US2] Implement XML to JSON transformation for blob list response
- [X] T016 [US2] Add count field to response JSON
- [X] T017 [US2] Deploy and test list operation with curl command

**Checkpoint**: User Stories 1 AND 2 complete ✅ - can upload and list files

---

## Phase 5: User Story 3 - Download File (Priority: P2)

**Goal**: Authenticated clients can download specific files from storage

**Independent Test**: `curl -X GET .../storage/files/test.txt` returns file content with correct Content-Type

### Implementation for User Story 3

- [X] T018 [US3] Implement download operation policy in `bicep/apim/policies/storage-operations.xml` (GET /files/{filename})
- [X] T019 [US3] Pass through Content-Type and Content-Length headers from storage response
- [X] T020 [US3] Implement 404 error handling for missing blobs
- [X] T021 [US3] Deploy and test download operation with curl command

**Checkpoint**: User Stories 1, 2, AND 3 complete ✅ - can upload, list, and download files

---

## Phase 6: User Story 4 - Delete File (Priority: P3)

**Goal**: Authenticated clients can delete files from storage

**Independent Test**: `curl -X DELETE .../storage/files/test.txt` returns 204 and file is removed

### Implementation for User Story 4

- [X] T022 [US4] Implement delete operation policy in `bicep/apim/policies/storage-operations.xml` (DELETE /files/{filename})
- [X] T023 [US4] Return 204 No Content on successful deletion
- [X] T024 [US4] Implement 404 error handling for missing blobs
- [X] T025 [US4] Deploy and test delete operation with curl command

**Checkpoint**: All 4 CRUD operations complete ✅

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, testing script, and validation

- [X] T026 [P] Create end-to-end test script `scripts/test-storage-api.sh` covering all operations
- [X] T027 [P] Create usage documentation in `docs/apim/storage-api-guide.md`
- [X] T028 [P] Update `bicep/apim/main.bicep` to include storage-api module reference
- [X] T029 Run quickstart.md validation to verify all steps work
- [X] T030 Update README.md with storage API information

**All phases complete! ✅**

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately ✅
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories ✅
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion ✅
- **Polish (Phase 7)**: Depends on all user stories being complete ✅

### User Story Dependencies

| Story | Can Start After | Dependencies on Other Stories |
|-------|-----------------|-------------------------------|
| US1 (Upload) | Phase 2 | None - fully independent |
| US2 (List) | Phase 2 | None - fully independent |
| US3 (Download) | Phase 2 | None - fully independent |
| US4 (Delete) | Phase 2 | None - fully independent |

### Within Each User Story

- Policy implementation before response transformation
- Error handling after core implementation
- Deploy and test as final step

### Parallel Opportunities

**Phase 2 (Foundational)**:
```
T004 (JWT policy) ─────────┐
                           ├─→ T006 (API Bicep) → T007 (Deploy script)
T005 (Storage policy) ─────┘
```

**After Foundational Complete - All Stories Can Run in Parallel**:
```
US1 (T008-T012) ──→ MVP Complete!
US2 (T013-T017) ──→ List working
US3 (T018-T021) ──→ Download working
US4 (T022-T025) ──→ Delete working
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T007)
3. Complete Phase 3: User Story 1 - Upload (T008-T012)
4. Complete Phase 4: User Story 2 - List (T013-T017)
5. **STOP and VALIDATE**: Test upload + list end-to-end
6. Deploy/demo if ready - MVP achieved!

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add US1 (Upload) → Test → Can upload files!
3. Add US2 (List) → Test → Can see uploaded files!
4. Add US3 (Download) → Test → Can retrieve files!
5. Add US4 (Delete) → Test → Full CRUD complete!
6. Polish → Production ready

---

## Summary

| Phase | Tasks | Key Deliverable |
|-------|-------|-----------------|
| Setup | T001-T003 | RBAC permissions granted |
| Foundational | T004-T007 | API definition + core policies |
| US1 Upload | T008-T012 | Upload working (MVP!) |
| US2 List | T013-T017 | List working |
| US3 Download | T018-T021 | Download working |
| US4 Delete | T022-T025 | Delete working |
| Polish | T026-T030 | Docs + tests complete |

**Total Tasks**: 30
- **Setup**: 3 tasks
- **Foundational**: 4 tasks  
- **User Stories**: 18 tasks (US1: 5, US2: 5, US3: 4, US4: 4)
- **Polish**: 5 tasks

**Parallel Opportunities**: 8 tasks marked [P]
**MVP Scope**: T001-T017 (17 tasks for upload + list functionality)
