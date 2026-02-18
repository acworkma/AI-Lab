# Implementation Plan: Private Azure Kubernetes Service Infrastructure

**Branch**: `011-private-aks` | **Date**: 2026-02-18 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/011-private-aks/spec.md`

## Summary

Deploy a private Azure Kubernetes Service (AKS) cluster as a foundational infrastructure project with private API server endpoint, Azure RBAC authorization, ACR integration via managed identity, and Azure CNI Overlay networking. The cluster provides container orchestration capabilities accessible only through VPN connection, following the same patterns established by Key Vault, Storage Account, and ACR infrastructure projects.

## Technical Context

**Language/Version**: Bicep (Azure Resource Manager)  
**Primary Dependencies**: Azure CLI ≥2.50, Bicep CLI (bundled), kubectl, Core infrastructure (rg-ai-core), Private ACR (rg-ai-acr)  
**Compute**: AKS (3x Standard_D2s_v3 nodes across AZs 1,2,3)  
**Node OS**: Azure Linux (CBL-Mariner)  
**Network**: Azure CNI Overlay (pod CIDR 10.244.0.0/16)  
**Testing**: Shell scripts (validate-aks.sh, what-if), kubectl assertions, Azure CLI  
**Target Platform**: Azure Cloud (East US 2 region)  
**Project Type**: Infrastructure module (Bicep + scripts)  
**Performance Goals**: Deployment <20 min; kubectl response <2 sec; nodes Ready <10 min  
**Constraints**: Private API server only (no public endpoint); Azure RBAC (local accounts disabled); VPN required  
**Scale/Scope**: Single AKS cluster; 3-node system pool; lab/dev workloads

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Check ✅
✅ **Principle 1 (IaC)**: Bicep templates, no portal changes, parameterized modules  
✅ **Principle 2 (Hub-Spoke)**: Connects to vWAN hub via private endpoint; integrates with shared services VNet  
✅ **Principle 3 (Resource Org)**: Separate `rg-ai-aks` RG; naming convention followed (`aks-ai-lab`)  
✅ **Principle 4 (Security)**: Azure RBAC; local accounts disabled; private endpoint only; managed identity for ACR  
✅ **Principle 5 (Deployment)**: Azure CLI deploy; what-if validation; rollback via RG delete  
✅ **Principle 6 (Modularity)**: Independent deployment; clean deletion; self-contained README  
✅ **Principle 7 (Documentation)**: README with all required sections; inline Bicep comments

### Post-Design Check ✅
✅ **Principle 1 (IaC)**: Bicep module defines complete AKS cluster with all parameters  
✅ **Principle 2 (Hub-Spoke)**: Private cluster with VPN-only API access  
✅ **Principle 3 (Resource Org)**: Data model confirms rg-ai-aks with proper tagging  
✅ **Principle 4 (Security)**: Azure RBAC; local accounts disabled; private endpoint only  
✅ **Principle 5 (Deployment)**: Deploy script with what-if, validation, role assignments  
✅ **Principle 6 (Modularity)**: References core infrastructure; ACR role cross-RG  
✅ **Principle 7 (Documentation)**: Full README with troubleshooting and architecture

## Project Structure

### Documentation (this feature)

```text
specs/011-private-aks/
├── plan.md              # This file
├── spec.md              # Feature specification ✅
├── research.md          # Phase 0: Technical decisions (pending)
├── data-model.md        # Phase 1: Azure resource entities (pending)
├── quickstart.md        # Phase 1: Deployment guide (pending)
├── contracts/
│   └── deployment-contract.md  # Bicep module interface (pending)
├── checklists/
│   └── requirements.md  # Specification checklist ✅
└── tasks.md             # Phase 2: Implementation tasks (via /speckit.tasks)
```

### Source Code (repository root)

```text
bicep/
├── modules/
│   ├── aks.bicep                  # Reusable AKS cluster module (NEW)
│   └── aks-subnet.bicep           # AKS subnet in shared services VNet (NEW)
└── aks/
    ├── main.bicep                 # Orchestration template
    ├── main.parameters.json       # Deployment parameters
    └── main.parameters.example.json

scripts/
├── deploy-aks.sh                  # Deployment script
├── validate-aks.sh                # Pre-deploy validation
├── validate-aks-dns.sh            # API server DNS resolution check
├── cleanup-aks.sh                 # Resource cleanup
└── grant-aks-acr-role.sh          # AcrPull role assignment helper

docs/
└── aks/
    └── README.md                  # User-facing documentation
```

**Structure Decision**: Infrastructure module pattern matching 008-private-keyvault and 009-private-storage. Bicep module in `bicep/modules/`, orchestration in `bicep/aks/`, scripts in `scripts/`, docs in `docs/aks/`.

## Complexity Tracking

> Moderate complexity due to AKS private cluster networking and ACR integration

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| AKS subnet module | AKS needs dedicated subnet with proper sizing for nodes | Reusing private endpoint subnet would exhaust IPs |
| Azure CNI Overlay | Conserves VNet IP space while enabling pod networking | Standard Azure CNI would require /16+ for pods |
| Cross-RG role assignment | AKS identity needs AcrPull on ACR in different RG | Putting ACR in same RG would violate modularity principle |

---

## Implementation Phases Status

### ✅ Phase 0: Research & Outline (COMPLETED)

**Artifacts Generated**:
- ✅ K8s version documented (Azure default: 1.33)
- ✅ AKS networking decisions captured in clarifications

**Key Decisions**:
1. Node pool: 3x Standard_D2s_v3 across AZs 1,2,3
2. Node OS: Azure Linux (CBL-Mariner)
3. Network: Azure CNI Overlay with pod CIDR 10.244.0.0/16
4. K8s version: Azure default stable (queried at deploy)
5. DNS: System-managed private DNS zone
6. ACR: Managed identity with AcrPull role

**Unresolved Issues**: None

---

### ✅ Phase 1: Design & Contracts (COMPLETED)

**Artifacts Generated**:
- ✅ [plan.md](./plan.md) - Implementation plan complete
- ✅ Bicep module contract in aks.bicep comments
- ✅ [docs/aks/README.md](../../docs/aks/README.md) - Deployment guide

**Constitution Re-Check**: ✅ All gates passed

---

### ✅ Phase 2: Tasks (COMPLETED - via /speckit.tasks)

**Output**: [tasks.md](./tasks.md) - 35 implementation tasks with checklist

**Task Breakdown**:
- Phase 1 (Setup): 4 tasks - Directory structure, parameter files
- Phase 2 (Foundation): 3 tasks - Prerequisites, K8s version query
- Phase 3 (US1 - Deploy): 12 tasks - AKS module, private cluster config, deployment script
- Phase 4 (US2 - ACR Integration): 4 tasks - Identity, role assignment, image pull test
- Phase 5 (US3 - kubectl Access): 4 tasks - DNS validation, kubeconfig, connectivity test
- Phase 6 (US4 - Documentation): 4 tasks - README, pattern consistency, idempotency
- Final (Polish): 4 tasks - Bicep validation, comments, tags

**MVP Scope**: Phases 1-3 (19 tasks) delivers deployable private AKS cluster

---

## Key Technical Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Node pool size | 3x Standard_D2s_v3 | HA across 3 AZs; 2 vCPU/8GB RAM per node sufficient for lab |
| Node OS | Azure Linux (CBL-Mariner) | Container-optimized, smaller attack surface, faster boot |
| Network plugin | Azure CNI Overlay | Conserves VNet IPs; pods use 10.244.0.0/16 internally |
| K8s version | Azure default stable | Auto-selected at deploy; no manual version tracking |
| API server access | Private endpoint only | No public endpoint; VPN required |
| ACR integration | Managed identity + AcrPull | No manual secrets; cross-RG RBAC |
| Authentication | Azure RBAC | Local accounts disabled; Entra ID integration |

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| AKS deployment takes >20 min | Medium | Set realistic expectations; document typical times |
| Private DNS zone not linked | High | Validation script checks resolution before claiming success |
| ACR role assignment fails | High | Deployment script assigns role; retry logic |
| Quota exceeded for D2s_v3 | High | Pre-flight quota check in deploy script |
| K8s version deprecated mid-deploy | Low | Use Azure default; don't pin specific version |

---

## Next Steps

1. **Run `/speckit.research`** - Complete Phase 0 research on AKS networking and DNS
2. **Run `/speckit.design`** - Generate data model and contracts
3. **Run `/speckit.tasks`** - Generate implementation task list
4. **Begin implementation** - Follow task checklist in tasks.md
