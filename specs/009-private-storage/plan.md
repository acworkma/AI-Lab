# Implementation Plan: Private Azure Storage Account Infrastructure

**Branch**: `009-private-storage` | **Date**: 2026-01-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/009-private-storage/spec.md`

## Summary

Deploy Azure Storage Account as a standalone infrastructure project with private endpoint connectivity, RBAC authorization (shared key disabled), and integration with existing private DNS infrastructure. This creates a clean base storage layer that other projects can consume. Replaces the existing storage.bicep module (which combined base storage with CMK) with a simpler, focused implementation.

## Technical Context

**Language/Version**: Bicep (Azure Resource Manager)  
**Primary Dependencies**: Azure CLI ≥2.50, Bicep CLI (bundled), Core infrastructure (rg-ai-core)  
**Storage**: Azure Storage Account (StorageV2, Standard_LRS, blob only)  
**Testing**: Shell scripts (validate-storage-infra.sh, what-if), Azure CLI assertions  
**Target Platform**: Azure Cloud (East US 2 region)  
**Project Type**: Infrastructure module (Bicep + scripts)  
**Performance Goals**: Deployment <3 min; DNS resolution <100ms  
**Constraints**: Private endpoint only (no public access); RBAC auth (shared keys disabled); VPN required  
**Scale/Scope**: Single Storage Account per deployment; lab/dev workloads; Standard_LRS SKU

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Check ✅
✅ **Principle 1 (IaC)**: Bicep templates, no portal changes, parameterized modules  
✅ **Principle 2 (Hub-Spoke)**: Connects to vWAN hub via private endpoint in shared services VNet  
✅ **Principle 3 (Resource Org)**: Separate `rg-ai-storage` RG; naming convention followed  
✅ **Principle 4 (Security)**: RBAC authorization; shared keys disabled; private endpoint only  
✅ **Principle 5 (Deployment)**: Azure CLI deploy; what-if validation; rollback via RG delete  
✅ **Principle 6 (Modularity)**: Independent deployment; clean deletion; self-contained README  
✅ **Principle 7 (Documentation)**: README with all required sections; inline Bicep comments

### Post-Design Check ✅
✅ **Principle 1 (IaC)**: Bicep module contract defined; parameter file patterns documented  
✅ **Principle 2 (Hub-Spoke)**: Private endpoint uses existing PrivateEndpointSubnet (10.1.0.0/26)  
✅ **Principle 3 (Resource Org)**: Data model confirms rg-ai-storage with proper tagging  
✅ **Principle 4 (Security)**: RBAC roles documented; allowSharedKeyAccess=false; no shared keys  
✅ **Principle 5 (Deployment)**: Deploy script contract with what-if, validation, exit codes  
✅ **Principle 6 (Modularity)**: References core DNS zone; doesn't duplicate; clean deletion path  
✅ **Principle 7 (Documentation)**: Quickstart guide with all required sections complete

## Project Structure

### Documentation (this feature)

```text
specs/009-private-storage/
├── plan.md              # This file
├── spec.md              # Feature specification ✅
├── research.md          # Phase 0: Technical decisions
├── data-model.md        # Phase 1: Azure resource entities
├── quickstart.md        # Phase 1: Deployment guide
├── contracts/
│   └── deployment-contract.md  # Bicep module interface
├── checklists/
│   └── requirements.md  # Specification checklist ✅
└── tasks.md             # Phase 2: Implementation tasks (via /speckit.tasks)
```

### Source Code (repository root)

```text
bicep/
├── modules/
│   └── storage-account.bicep      # Reusable Storage Account module (NEW - replaces storage.bicep)
└── storage-infra/
    ├── main.bicep                 # Orchestration template
    ├── main.parameters.json       # Deployment parameters
    └── main.parameters.example.json

scripts/
├── deploy-storage-infra.sh        # Deployment script
├── validate-storage-infra.sh      # Pre-deploy validation
├── validate-storage-infra-dns.sh  # DNS resolution check
├── cleanup-storage-infra.sh       # Resource cleanup
└── grant-storage-infra-roles.sh   # RBAC assignment helper

docs/
└── storage-infra/
    └── README.md                  # User-facing documentation
```

**Structure Decision**: Infrastructure module pattern matching 008-private-keyvault. New Bicep module `storage-account.bicep` in `bicep/modules/`, orchestration in `bicep/storage-infra/`, scripts in `scripts/`, docs in `docs/storage-infra/`. Uses `-infra` suffix to distinguish from existing CMK-focused storage implementation.

## Complexity Tracking

> No violations detected - standard infrastructure pattern

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |

---

## Implementation Phases Status

### ✅ Phase 0: Research & Outline (COMPLETED)

**Artifacts Generated**:
- ✅ [research.md](./research.md) - All technical decisions documented

**Key Decisions**:
1. Naming: `stailab<MMDD>` with date-based suffix for global uniqueness
2. Private endpoint: Uses existing DNS zone in rg-ai-core (privatelink.blob.core.windows.net)
3. Authorization: RBAC only (allowSharedKeyAccess=false)
4. Security: TLS 1.2, HTTPS required, public access disabled
5. Soft-delete: 7 days default, configurable

**Unresolved Issues**: None - all research tasks completed

---

### ✅ Phase 1: Design & Contracts (COMPLETED)

**Artifacts Generated**:
- ✅ [data-model.md](./data-model.md) - 7 Azure resource entities documented
- ✅ [contracts/deployment-contract.md](./contracts/deployment-contract.md) - Complete Bicep module interface
- ✅ [quickstart.md](./quickstart.md) - Step-by-step deployment guide
- ✅ Agent context updated (Copilot instructions.md)

**Constitution Re-Check**: ✅ All gates passed

---

### ✅ Phase 2: Tasks (COMPLETED)

**Output**: [tasks.md](./tasks.md) - 27 implementation tasks with checklist

**Task Summary**:
- Phase 1 (Setup): 4 tasks
- Phase 2 (Foundation): 2 tasks  
- Phase 3 (US1 - Deploy): 11 tasks
- Phase 4 (US2 - Data Ops): 3 tasks
- Phase 5 (US3 - Integration): 4 tasks
- Final (Polish): 3 tasks

**MVP Scope**: Phases 1-3 (17 tasks) delivers deployable private storage account
