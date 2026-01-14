# Tasks: Azure API Management Standard v2

**Input**: Design documents from `/specs/006-apim-std-v2/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/deployment-contract.md

**Tests**: Not explicitly requested in spec - minimal validation scripts included.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Project initialization and Bicep module structure

- [ ] T001 Create APIM Bicep folder structure at bicep/apim/
- [ ] T002 [P] Create parameter example file at bicep/apim/main.parameters.example.json
- [ ] T003 [P] Create docs folder structure at docs/apim/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Network infrastructure that MUST be complete before APIM can be deployed

**⚠️ CRITICAL**: APIM deployment cannot proceed until subnet and NSG are ready

- [ ] T004 Create NSG module for APIM integration subnet at bicep/modules/apim-nsg.bicep
- [ ] T005 Create APIM integration subnet module at bicep/modules/apim-subnet.bicep
- [ ] T006 Update shared-services-vnet.bicep to accept optional APIM subnet parameter in bicep/modules/shared-services-vnet.bicep

**Checkpoint**: Network infrastructure ready for APIM VNet integration

---

## Phase 3: User Story 1 - Deploy APIM with VNet Integration (Priority: P1) 🎯 MVP

**Goal**: Deploy APIM Standard v2 instance with VNet integration to shared services subnet

**Independent Test**: Run deploy script, verify APIM instance running with VNet integration active in Azure Portal

### Implementation for User Story 1

- [ ] T007 [US1] Create APIM Bicep module at bicep/modules/apim.bicep
- [ ] T008 [US1] Create main deployment orchestration at bicep/apim/main.bicep
- [ ] T009 [US1] Create deployment script at scripts/deploy-apim.sh
- [ ] T010 [US1] Create validation script at scripts/validate-apim.sh
- [ ] T011 [US1] Create cleanup script at scripts/cleanup-apim.sh
- [ ] T012 [US1] Create README documentation at docs/apim/README.md

**Checkpoint**: APIM deployed and VNet-integrated - core infrastructure complete

---

## Phase 4: User Story 2 - Access APIM from VPN Clients (Priority: P2)

**Goal**: VPN clients can access developer portal and management plane

**Independent Test**: Connect via VPN, navigate to developer portal URL, verify page loads

### Implementation for User Story 2

- [ ] T013 [US2] Verify NSG allows VPN client access in bicep/modules/apim-nsg.bicep
- [ ] T014 [US2] Add VPN access verification to validation script in scripts/validate-apim.sh
- [ ] T015 [US2] Document VPN access instructions in docs/apim/README.md

**Checkpoint**: VPN clients can access APIM developer portal and Azure Portal management

---

## Phase 5: User Story 3 - Configure OAuth/Entra Authentication (Priority: P3)

**Goal**: APIM configured with OAuth 2.0/Entra ID for API authentication

**Independent Test**: Apply JWT validation policy to test API, verify unauthenticated requests return 401

### Implementation for User Story 3

- [ ] T016 [US3] Create OAuth configuration guide at docs/apim/oauth-setup.md
- [ ] T017 [US3] Create sample JWT validation policy template at bicep/apim/policies/jwt-validation.xml
- [ ] T018 [US3] Add OAuth configuration section to README in docs/apim/README.md

**Checkpoint**: OAuth documentation and templates ready for API protection

---

## Phase 6: User Story 4 - Publish an API to External Consumers (Priority: P4)

**Goal**: Import and publish an API pointing to private backend

**Independent Test**: Import test API, call from public internet, verify backend receives request

### Implementation for User Story 4

- [ ] T019 [US4] Create sample API import guide at docs/apim/import-api.md
- [ ] T020 [US4] Create sample backend configuration template at bicep/apim/backends/sample-backend.bicep
- [ ] T021 [US4] Add API publishing walkthrough to README in docs/apim/README.md

**Checkpoint**: End-to-end API publishing documentation complete

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements and final validation

- [ ] T022 [P] Add troubleshooting section to docs/apim/README.md
- [ ] T023 [P] Add architecture diagram to docs/apim/README.md
- [ ] T024 Run quickstart.md validation steps
- [ ] T025 Verify all deployment outputs match contracts/deployment-contract.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational - Core APIM deployment
- **User Stories 2-4 (Phases 4-6)**: Depend on User Story 1 completion
- **Polish (Phase 7)**: Depends on desired user stories being complete

### User Story Dependencies

```
Phase 2: Foundational (Subnet + NSG)
         │
         ▼
Phase 3: US1 - Deploy APIM ─────────────────────┐
         │                                       │
         ├──────────────────┬───────────────────┤
         ▼                  ▼                   ▼
Phase 4: US2 - VPN    Phase 5: US3 - OAuth   Phase 6: US4 - Publish
         │                  │                   │
         └──────────────────┴───────────────────┘
                            │
                            ▼
                   Phase 7: Polish
```

### Within Each Phase

- Bicep modules before deployment scripts
- Deployment scripts before validation scripts
- Core implementation before documentation

### Parallel Opportunities

**Phase 1 (all parallel)**:
```
T002 Parameter file
T003 Docs folder
```

**Phase 2 (sequential - dependencies)**:
```
T004 NSG module → T005 Subnet module → T006 Update shared-services-vnet
```

**After US1 complete (parallel user stories)**:
```
US2 (VPN Access)  |  US3 (OAuth)  |  US4 (API Publish)
```

**Phase 7 (parallel polish)**:
```
T022 Troubleshooting docs
T023 Architecture diagram
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (NSG + Subnet)
3. Complete Phase 3: User Story 1 (APIM Deployment)
4. **STOP and VALIDATE**: Test APIM independently
5. Deploy/demo if ready - core gateway is operational

### Incremental Delivery

1. Setup + Foundational → Infrastructure ready
2. Add User Story 1 → Test → Deploy (**MVP: APIM gateway working**)
3. Add User Story 2 → Test → VPN access confirmed
4. Add User Story 3 → OAuth templates ready for use
5. Add User Story 4 → API publishing docs complete

---

## Notes

- APIM deployment takes 15-20 minutes - plan accordingly
- Publisher email is required parameter - must be set before deployment
- VNet integration uses Microsoft.Web/serverFarms delegation (not Microsoft.ApiManagement)
- Developer portal requires explicit publish action post-deployment
- OAuth configuration is documentation/template only - actual setup is post-deployment

---

## Task Summary

| Phase | Task Count | Parallel Tasks |
|-------|------------|----------------|
| 1. Setup | 3 | 2 |
| 2. Foundational | 3 | 0 |
| 3. US1 - Deploy APIM | 6 | 0 |
| 4. US2 - VPN Access | 3 | 0 |
| 5. US3 - OAuth | 3 | 0 |
| 6. US4 - Publish API | 3 | 0 |
| 7. Polish | 4 | 2 |
| **Total** | **25** | **4** |

**MVP Scope**: T001-T012 (12 tasks) - Fully functional APIM with VNet integration
