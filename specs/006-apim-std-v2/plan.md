# Implementation Plan: Azure API Management Standard v2

**Branch**: `006-apim-std-v2` | **Date**: 2026-01-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/006-apim-std-v2/spec.md`

## Summary

Deploy an Azure API Management Standard v2 instance as a centralized API gateway with public frontend and VNet-integrated backend. This Infrastructure Project provides API management capabilities that Solution Projects consume to expose internal services externally with OAuth/Entra authentication.

## Technical Context

**Language/Version**: Bicep (Azure IaC)
**Primary Dependencies**: Azure CLI 2.50.0+, jq
**Storage**: N/A (stateless gateway)
**Testing**: Azure CLI validation scripts, curl/Postman for API testing
**Target Platform**: Azure (australiaeast region, matching core infrastructure)
**Project Type**: Infrastructure Project (provides capabilities for Solution Projects)
**Performance Goals**: Standard v2 tier default throughput (scales automatically)
**Constraints**: Standard v2 tier limitations (no multi-region, no full VNet injection)
**Scale/Scope**: Single APIM instance serving all AI-Lab APIs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| 1. Infrastructure as Code | ✅ PASS | Bicep-only deployment, no portal changes |
| 2. Hub-Spoke Architecture | ✅ PASS | VNet integration via shared services VNet connected to vWAN hub |
| 3. Resource Organization | ✅ PASS | Dedicated `rg-ai-apim` resource group, follows naming convention |
| 4. Security & Secrets | ✅ PASS | OAuth/Entra auth, no secrets in code, publisher email parameterized |
| 5. Deployment Standards | ✅ PASS | Azure CLI deployment with what-if, validation gates |
| 6. Lab Modularity | ✅ PASS | Independent deployment, documented dependencies on core |
| 7. Documentation Standards | ✅ PASS | README with all required sections planned |

**Project Type**: Infrastructure Project ✅ (provides API gateway capability consumed by Solution Projects)

## Project Structure

### Documentation (this feature)

```text
specs/006-apim-std-v2/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── deployment-contract.md
└── tasks.md             # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
bicep/
├── apim/
│   ├── main.bicep                    # APIM deployment orchestration
│   ├── main.parameters.example.json  # Parameter template
│   ├── policies/
│   │   └── jwt-validation.xml        # Sample OAuth JWT validation policy (NEW)
│   └── backends/
│       └── sample-backend.bicep      # Sample backend configuration (NEW)
├── modules/
│   ├── apim.bicep                    # APIM instance module (NEW)
│   ├── apim-nsg.bicep                # APIM integration subnet NSG (NEW)
│   ├── apim-subnet.bicep             # VNet integration subnet module (NEW)
│   └── shared-services-vnet.bicep    # Existing - add APIM subnet

scripts/
├── deploy-apim.sh                    # Deployment script (NEW)
├── validate-apim.sh                  # Validation script (NEW)
└── cleanup-apim.sh                   # Cleanup script (NEW)

docs/
└── apim/
    └── README.md                     # APIM documentation (NEW)
```

**Structure Decision**: Follows existing AI-Lab patterns with dedicated bicep folder, reusable modules, and deployment scripts. APIM subnet added to existing shared-services-vnet or as separate module.

## Complexity Tracking

No constitution violations requiring justification.
