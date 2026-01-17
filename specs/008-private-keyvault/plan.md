# Implementation Plan: Private Azure Key Vault Infrastructure

**Branch**: `008-private-keyvault` | **Date**: 2025-01-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/008-private-keyvault/spec.md`

## Summary

Deploy Azure Key Vault as a standalone infrastructure project with private endpoint connectivity, RBAC authorization, and integration with existing private DNS infrastructure. Previously Key Vault was deployed in core infrastructure without private endpoints - this project corrects that by creating a properly isolated, secure Key Vault that other projects can reference for secrets management.

## Technical Context

**Language/Version**: Bicep (Azure Resource Manager)  
**Primary Dependencies**: Azure CLI ≥2.50, Bicep CLI (bundled), Core infrastructure (rg-ai-core)  
**Storage**: N/A (Key Vault is the storage layer for secrets)  
**Testing**: Shell scripts (validate-keyvault.sh, what-if), Azure CLI assertions  
**Target Platform**: Azure Cloud (East US 2 region)  
**Project Type**: Infrastructure module (Bicep + scripts)  
**Performance Goals**: Deployment <3 min; DNS resolution <100ms; secret operations <100ms  
**Constraints**: Private endpoint only (no public access); RBAC auth (not access policies); VPN required  
**Scale/Scope**: Single Key Vault per deployment; lab/dev workloads; Standard SKU

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Check ✅
✅ **Principle 1 (IaC)**: Bicep templates, no portal changes, parameterized modules  
✅ **Principle 2 (Hub-Spoke)**: Connects to vWAN hub via private endpoint in shared services VNet  
✅ **Principle 3 (Resource Org)**: Separate `rg-ai-keyvault` RG; naming convention followed  
✅ **Principle 4 (Security)**: RBAC authorization; no secrets in source; private endpoint only  
✅ **Principle 5 (Deployment)**: Azure CLI deploy; what-if validation; rollback via RG delete  
✅ **Principle 6 (Modularity)**: Independent deployment; clean deletion; self-contained README  
✅ **Principle 7 (Documentation)**: README with all required sections; inline Bicep comments

### Post-Design Check ✅
✅ **Principle 1 (IaC)**: Bicep module contract defined; parameter file patterns documented  
✅ **Principle 2 (Hub-Spoke)**: Private endpoint uses existing snet-private-endpoints (10.1.0.0/26)  
✅ **Principle 3 (Resource Org)**: Data model confirms rg-ai-keyvault with proper tagging  
✅ **Principle 4 (Security)**: RBAC roles documented; enableRbacAuthorization=true; no access policies  
✅ **Principle 5 (Deployment)**: Deploy script contract with what-if, validation, exit codes  
✅ **Principle 6 (Modularity)**: References core DNS zone; doesn't duplicate; clean deletion path  
✅ **Principle 7 (Documentation)**: Quickstart guide with all required sections complete

## Project Structure

### Documentation (this feature)

```text
specs/008-private-keyvault/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: Technical decisions ✅
├── data-model.md        # Phase 1: Azure resource entities ✅
├── quickstart.md        # Phase 1: Deployment guide ✅
├── contracts/
│   └── deployment-contract.md  # Bicep module interface ✅
└── tasks.md             # Phase 2: Implementation tasks (via /speckit.tasks)
```

### Source Code (repository root)

```text
bicep/
├── modules/
│   └── key-vault.bicep            # Reusable Key Vault module
└── keyvault/
    ├── main.bicep                 # Orchestration template
    ├── main.parameters.json       # Deployment parameters
    └── main.parameters.example.json

scripts/
├── deploy-keyvault.sh             # Deployment script
├── validate-keyvault.sh           # Pre-deploy validation
├── validate-keyvault-dns.sh       # DNS resolution check
└── cleanup-keyvault.sh            # Resource cleanup

docs/
└── keyvault/
    └── README.md                  # User-facing documentation
```

**Structure Decision**: Infrastructure module pattern matching 005-storage-cmk. Bicep module in `bicep/modules/`, orchestration in `bicep/keyvault/`, scripts in `scripts/`, docs in `docs/keyvault/`.

## Complexity Tracking

> No violations detected - standard infrastructure pattern

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |

---

## Implementation Phases Status

### ✅ Phase 0: Research & Outline (COMPLETED)

**Artifacts Generated**:
- ✅ [research.md](./research.md) - All technical clarifications resolved

**Key Decisions**:
1. Naming: `kv-ai-lab-<MMDD>` with date-based suffix for uniqueness
2. Private endpoint: Uses existing DNS zone in rg-ai-core
3. Authorization: RBAC only (no access policies)
4. Bicep references: JSON and .bicepparam syntax documented
5. Soft-delete: 90 days, purge protection disabled for lab
6. SKU: Standard (Premium deferred)

**Unresolved Issues**: None - all research tasks completed

---

### ✅ Phase 1: Design & Contracts (COMPLETED)

**Artifacts Generated**:
- ✅ [data-model.md](./data-model.md) - 6 Azure resource entities documented
- ✅ [contracts/deployment-contract.md](./contracts/deployment-contract.md) - Complete Bicep module interface
- ✅ [quickstart.md](./quickstart.md) - Step-by-step deployment guide
- ✅ Agent context updated (Copilot instructions.md)

**Constitution Re-Check**: ✅ All gates still passed

---

### Phase 2: Tasks (PENDING - via /speckit.tasks)

**Output**: [tasks.md](./tasks.md) - Implementation tasks with checklist
