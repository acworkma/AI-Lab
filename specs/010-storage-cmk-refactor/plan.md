# Implementation Plan: Storage CMK Refactor

**Branch**: `010-storage-cmk-refactor` | **Date**: 2026-01-17 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/010-storage-cmk-refactor/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enable customer-managed key (CMK) encryption on an existing private Storage Account by creating an encryption key in the existing Key Vault, establishing a user-assigned managed identity with Key Vault Crypto Service Encryption User role, and updating the Storage Account encryption configuration. This completes the separation of concerns from the monolithic 005-storage-cmk design.

## Technical Context

**Language/Version**: Bicep (Azure DSL), Bash scripts  
**Primary Dependencies**: Azure Key Vault (existing), Azure Storage Account (existing), Azure Managed Identity  
**Storage**: Azure Blob Storage with CMK encryption  
**Testing**: Azure CLI validation scripts, manual VPN connectivity tests  
**Target Platform**: Azure (eastus2 region)
**Project Type**: Solution Project (consumes infrastructure from 008-private-keyvault and 009-private-storage)  
**Performance Goals**: Deployment < 3 minutes, no perceptible latency impact on blob operations  
**Constraints**: Key Vault must have soft-delete and purge protection enabled; RSA 2048/3072/4096-bit keys only  
**Scale/Scope**: Single storage account with CMK, single Key Vault key with 18-month rotation policy

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| **1. Infrastructure as Code** | ✅ PASS | All resources defined in Bicep at `bicep/storage/main.bicep` |
| **2. Hub-Spoke Architecture** | ✅ PASS | Uses existing private endpoints connected to vWAN hub |
| **3. Resource Organization** | ✅ PASS | Uses `rg-ai-storage` (existing) and `rg-ai-keyvault` (existing) |
| **4. Security & Secrets** | ✅ PASS | CMK stored in Key Vault, managed identity with least-privilege |
| **5. Deployment Standards** | ✅ PASS | Scripts follow existing patterns (what-if, validation) |
| **6. Lab Modularity** | ✅ PASS | CMK enablement independent of storage/keyvault deployment |
| **7. Documentation Standards** | ✅ PASS | Updates to `docs/storage/README.md` required |

**Project Type**: Solution Project - Consumes infrastructure from 008-private-keyvault (Key Vault) and 009-private-storage (Storage Account)

## Project Structure

### Documentation (this feature)

```text
specs/010-storage-cmk-refactor/
├── plan.md              # This file
├── research.md          # Phase 0 output - Azure CMK patterns research
├── data-model.md        # Phase 1 output - Resource relationships
├── quickstart.md        # Phase 1 output - Deployment guide
├── contracts/           # Phase 1 output - N/A (no API contracts)
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
bicep/
├── storage/                    # CMK enablement orchestration (REFACTORED)
│   ├── main.bicep             # Orchestrates CMK on existing storage
│   ├── main.parameters.json   # Production parameters
│   └── main.parameters.example.json
└── modules/
    ├── storage-key.bicep      # Creates encryption key (existing)
    └── storage-rbac.bicep     # RBAC assignment helper (existing)

scripts/
├── deploy-storage.sh          # UPDATED: CMK deployment script
├── validate-storage.sh        # UPDATED: CMK validation
└── grant-storage-roles.sh     # User RBAC assignment

docs/
└── storage/
    └── README.md              # UPDATED: Refactored architecture docs
```

**Structure Decision**: Refactor existing `bicep/storage/` to enable CMK on pre-deployed storage rather than creating new storage. Reuse existing modules for key creation and RBAC.

## Complexity Tracking

> No Constitution Check violations. Feature follows established patterns.

## Constitution Check (Post-Design Re-evaluation)

*Re-evaluated after Phase 1 design completion*

| Principle | Status | Post-Design Evidence |
|-----------|--------|---------------------|
| **1. Infrastructure as Code** | ✅ PASS | All resources in Bicep; no manual portal changes |
| **2. Hub-Spoke Architecture** | ✅ PASS | Uses existing private endpoints; no new network resources |
| **3. Resource Organization** | ✅ PASS | Uses existing RGs (`rg-ai-storage`, `rg-ai-keyvault`); follows naming conventions |
| **4. Security & Secrets** | ✅ PASS | CMK in Key Vault; managed identity with least-privilege role; no secrets in code |
| **5. Deployment Standards** | ✅ PASS | what-if validation; validation scripts; deployment logs |
| **6. Lab Modularity** | ✅ PASS | CMK is independent layer; can be enabled/disabled without recreating storage |
| **7. Documentation Standards** | ✅ PASS | quickstart.md created; README update required in implementation |

**Project Type Verification**: Solution Project ✅
- Consumes: Key Vault (008), Storage Account (009)
- Provides: CMK encryption capability (not consumed by other projects)

**No violations identified. Design approved for Phase 2 task generation.**
