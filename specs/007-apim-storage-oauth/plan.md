# Implementation Plan: APIM Storage OAuth Demo

**Branch**: `007-apim-storage-oauth` | **Date**: 2025-01-15 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/007-apim-storage-oauth/spec.md`
**Project Type**: Solution

## Summary

Create an OAuth-protected API in APIM that enables authenticated clients to perform CRUD operations on Azure Blob Storage using APIM's managed identity. The solution demonstrates secure, credential-free access to storage via JWT-validated API calls.

## Technical Context

**Language/Version**: Bicep (Azure IaC), XML (APIM policies), Bash (scripts)
**Primary Dependencies**: Azure API Management Standard v2, Azure Blob Storage, Entra ID
**Storage**: Azure Blob Storage (stailab001, container: data)
**Testing**: Bash scripts with curl, Azure CLI validation
**Target Platform**: Azure Cloud (East US 2)
**Project Type**: Solution (consumes Infrastructure Projects)
**Performance Goals**: API responses < 5 seconds for files < 1MB
**Constraints**: No stored credentials, managed identity only
**Scale/Scope**: Demo/POC scale, single storage container

### Infrastructure Dependencies (Verified)

| Resource | Name | Resource Group | Principal ID |
|----------|------|----------------|--------------|
| APIM | apim-ai-lab-0115 | rg-ai-apim | c856d119-9ba7-48b6-a627-047c01014d82 |
| Storage | stailab001 | rg-ai-storage | N/A |
| Container | data | rg-ai-storage | N/A |
| App Registration | apim-ai-lab-0115-devportal | N/A | 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 |
| Tenant | MngEnvMCAP818246.onmicrosoft.com | N/A | 38c1a7b0-f16b-45fd-a528-87d8720e868e |

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| 1. IaC (Bicep Only) | ✅ PASS | All APIM APIs/policies defined in Bicep |
| 2. Hub-Spoke Architecture | ✅ PASS | Uses existing APIM in rg-ai-apim |
| 3. Resource Organization | ✅ PASS | Solution uses rg-ai-apim (existing) |
| 4. Security & Secrets | ✅ PASS | No secrets - managed identity only |
| 5. Deployment Standards | ✅ PASS | Azure CLI with what-if |
| 6. Lab Modularity | ✅ PASS | No new resource groups needed |
| 7. Documentation Standards | ✅ PASS | README with all required sections |

**Gate Status**: ✅ PASSED - Ready for Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/007-apim-storage-oauth/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (OpenAPI spec)
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```text
bicep/apim/
├── apis/
│   └── storage-api.bicep        # Storage API definition
├── policies/
│   ├── jwt-validation.xml       # JWT validation policy (new)
│   └── storage-operations.xml   # Managed identity auth to storage (new)
└── main.bicep                   # Updated to include storage API

scripts/
├── deploy-storage-api.sh        # Deploy the storage API to APIM
├── test-storage-api.sh          # End-to-end test script
└── grant-apim-storage-role.sh   # Grant APIM MI access to storage

docs/apim/
└── storage-api-guide.md         # Usage documentation
```

**Structure Decision**: Extends existing `bicep/apim/` structure with new API definition and policies. No new resource groups created as this is a Solution Project consuming existing infrastructure.

## Complexity Tracking

> No constitution violations - table not required.
