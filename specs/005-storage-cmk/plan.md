# Implementation Plan: Private Azure Storage with CMK

**Branch**: `005-storage-cmk` | **Date**: 2026-01-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-storage-cmk/spec.md`

## Summary

Deploy an Azure Storage Account with customer-managed key (CMK) encryption using a key stored in the core Key Vault, integrated with a private endpoint on the existing vWAN infrastructure. Blob storage only for MVP; file shares deferred. Standard_LRS tier for lab cost-efficiency.

## Technical Context

**Language/Version**: Bicep (Azure Resource Manager)  
**Primary Dependencies**: Azure CLI ≥2.50, Bicep CLI (bundled), Core infrastructure (rg-ai-core)  
**Storage**: Azure Blob Storage (Standard_LRS, StorageV2)  
**Testing**: Shell scripts (validate-storage.sh, what-if), Azure CLI assertions  
**Target Platform**: Azure Cloud (East US region)  
**Project Type**: Infrastructure module (Bicep + scripts)  
**Performance Goals**: Deployment <5 min; DNS resolution <100ms; CMK latency <50ms overhead  
**Constraints**: Private endpoint only (no public access); RBAC auth (no shared keys); VPN required  
**Scale/Scope**: Single storage account per deployment; lab/dev workloads

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

✅ **Principle 1 (IaC)**: Bicep templates, no portal changes, parameterized modules  
✅ **Principle 2 (Hub-Spoke)**: Connects to vWAN hub via private endpoint in shared services VNet  
✅ **Principle 3 (Resource Org)**: Separate `rg-ai-storage` RG; naming convention followed  
✅ **Principle 4 (Security)**: CMK in Key Vault; managed identity; no secrets in source  
✅ **Principle 5 (Deployment)**: Azure CLI deploy; what-if validation; rollback via RG delete  
✅ **Principle 6 (Modularity)**: Independent deployment; clean deletion; self-contained README  
✅ **Principle 7 (Documentation)**: README with all required sections; inline Bicep comments

## Project Structure

## Project Structure

### Documentation (this feature)

```text
specs/005-storage-cmk/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: Technical decisions
├── data-model.md        # Phase 1: Azure resource entities
├── quickstart.md        # Phase 1: Deployment guide
├── contracts/
│   └── deployment-contract.md  # Bicep module interface
└── tasks.md             # Phase 2: Implementation tasks
```

### Source Code (repository root)

```text
bicep/
├── modules/
│   └── storage.bicep              # Reusable storage module
└── storage/
    ├── main.bicep                 # Orchestration template
    ├── main.parameters.json       # Deployment parameters
    └── main.parameters.example.json

scripts/
├── deploy-storage.sh              # Deployment script
├── validate-storage.sh            # Pre-deploy validation
├── validate-storage-dns.sh        # DNS resolution check
├── grant-storage-roles.sh         # RBAC assignment
└── storage-ops.sh                 # Blob operations helper

docs/
└── storage/
    └── README.md                  # User-facing documentation
```

**Structure Decision**: Infrastructure module pattern matching 002-private-acr. Bicep module in `bicep/modules/`, orchestration in `bicep/storage/`, scripts in `scripts/`, docs in `docs/storage/`.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |

---

## Implementation Phases Status

### ✅ Phase 0: Research & Outline (COMPLETED)

**Artifacts Generated**:
- ✅ [research.md](./research.md) - All technical clarifications resolved

**Key Decisions**:
1. Storage tier: Standard_LRS (lab-appropriate, CMK-compatible)
2. Private endpoint scope: Blob storage only (matches spec)
3. CMK configuration: User-assigned managed identity with 90-day auto-rotation
4. DNS integration: Leverage existing core infrastructure (no new resources)
5. Network security: Public access fully disabled, private endpoint only
6. Bicep architecture: Follow 002-private-acr module pattern
7. Resource group: Separate rg-ai-storage (modularity compliance)
8. Diagnostic logging: Comprehensive logs to existing Log Analytics workspace

**Unresolved Issues**: None - all NEEDS CLARIFICATION items resolved

---

### ✅ Phase 1: Design & Contracts (COMPLETED)

**Artifacts Generated**:
- ✅ [data-model.md](./data-model.md) - 8 Azure resource entities documented
- ✅ [contracts/deployment-contract.md](./contracts/deployment-contract.md) - Complete Bicep module interface
- ✅ [quickstart.md](./quickstart.md) - Step-by-step deployment guide
- ✅ Agent context updated (Copilot instructions.md)

**Constitution Re-Check**: ✅ All gates still passed

---

### ✅ Phase 2: Tasks Breakdown (COMPLETED)

**Artifacts Generated**:
- ✅ [tasks.md](./tasks.md) - 35 tasks across 6 phases

**Task Summary**:
- Setup: 4 tasks | Foundational: 3 tasks
- US1 (P1 MVP): 15 tasks | US2 (P2): 5 tasks | US3 (P3): 5 tasks
- Polish: 4 tasks

---

### ✅ Phase 3: Implementation (COMPLETED)

**Artifacts Generated**:
- ✅ `bicep/modules/storage.bicep` - Reusable storage module with CMK, PE, diagnostics
- ✅ `bicep/modules/storage-key.bicep` - Key Vault key with rotation policy
- ✅ `bicep/modules/storage-rbac.bicep` - RBAC assignment helper
- ✅ `bicep/storage/main.bicep` - Orchestration template
- ✅ `bicep/storage/main.parameters.json` - Deployment parameters
- ✅ `scripts/deploy-storage.sh` - Deployment with NFR timing
- ✅ `scripts/validate-storage.sh` - Pre/post deployment validation
- ✅ `scripts/validate-storage-dns.sh` - DNS NFR-003 validation
- ✅ `scripts/grant-storage-roles.sh` - RBAC assignment
- ✅ `scripts/storage-ops.sh` - Blob operations helper
- ✅ `scripts/validate-storage-ops.sh` - E2E data ops test
- ✅ `scripts/what-if-storage.sh` - Idempotency check
- ✅ `scripts/lint-bicep.sh` - Bicep linting
- ✅ `.github/workflows/bicep.yml` - CI/CD pipeline
- ✅ `tests/storage/README.md` - Validation suite docs
- ✅ `docs/storage/README.md` - User documentation (updated)

**Implementation Complete**: All 35 tasks completed

---

## Plan Execution Summary

| Phase | Status | Completion Date | Artifacts | Notes |
|-------|--------|----------------|-----------|-------|
| **Phase 0** | ✅ COMPLETE | 2026-01-07 | research.md | 8 decisions, 0 unresolved |
| **Phase 1** | ✅ COMPLETE | 2026-01-07 | data-model.md, contracts/, quickstart.md | Agent context updated |
| **Phase 2** | ✅ COMPLETE | 2026-01-07 | tasks.md | 35 tasks, MVP = US1 |
| **Phase 3** | ✅ COMPLETE | 2026-01-07 | Bicep modules, scripts, CI/CD | All US1-US3 + Polish |

**Command Completion**: Implementation complete. Ready for deployment.

**Branch**: `005-storage-cmk`

**Next Actions**:
1. ✅ All tasks complete
2. Deploy to dev environment: `./scripts/deploy-storage.sh`
3. Validate deployment: `./scripts/validate-storage.sh --deployed`
4. Run data ops test: `./scripts/validate-storage-ops.sh`

**Constitution Compliance**: ✅ All 7 principles validated and passing
