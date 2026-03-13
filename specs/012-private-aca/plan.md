# Implementation Plan: Private Azure Container Apps Environment

**Branch**: `012-private-aca` | **Date**: 2026-02-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/012-private-aca/spec.md`

## Summary

Deploy a private Azure Container Apps (ACA) environment as a foundational infrastructure project with VNet injection, private endpoint for management plane, internal-only ingress, and Log Analytics integration. The environment provides serverless container hosting accessible only through VPN connection, following patterns established by Key Vault, Storage, ACR, and AKS projects.

## Technical Context

**Language/Version**: Bicep (Azure Resource Manager)  
**Primary Dependencies**: Azure CLI ≥2.50, Bicep CLI (bundled), Core infrastructure (rg-ai-core)  
**Compute**: Azure Container Apps (Consumption workload profile)  
**Network**: VNet-injected environment + private endpoint for management plane  
**Testing**: Shell scripts (validate-aca.sh, validate-aca-dns.sh, what-if), Azure CLI  
**Target Platform**: Azure Cloud (East US 2 region)  
**Project Type**: Infrastructure module (Bicep + scripts)  
**Performance Goals**: Deployment <10 min; DNS resolution < 100ms  
**Constraints**: Internal-only ingress; no public access; VPN required  
**Scale/Scope**: Single ACA environment; Consumption plan; lab/dev workloads

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Check ✅
✅ **Principle 1 (IaC)**: Bicep templates, no portal changes, parameterized modules  
✅ **Principle 2 (Hub-Spoke)**: Connects to vWAN hub via VNet injection and private endpoint; integrates with shared services VNet  
✅ **Principle 3 (Resource Org)**: Separate `rg-ai-aca` RG; naming convention followed (`cae-ai-lab`)  
✅ **Principle 4 (Security)**: Private endpoint only; internal ingress; public access disabled  
✅ **Principle 5 (Deployment)**: Azure CLI deploy; what-if validation; rollback via RG delete  
✅ **Principle 6 (Modularity)**: Independent deployment; clean deletion; self-contained README  
✅ **Principle 7 (Documentation)**: README with all required sections; inline Bicep comments

### Post-Design Check ✅
✅ **Principle 1 (IaC)**: Bicep modules define complete ACA environment with all parameters  
✅ **Principle 2 (Hub-Spoke)**: VNet-injected with VPN-only access  
✅ **Principle 3 (Resource Org)**: rg-ai-aca with proper tagging  
✅ **Principle 4 (Security)**: Private endpoint; internal ingress; public access disabled  
✅ **Principle 5 (Deployment)**: Deploy script with what-if, validation, post-deploy checks  
✅ **Principle 6 (Modularity)**: References core infrastructure; modular Bicep  
✅ **Principle 7 (Documentation)**: Full README with architecture diagram and examples

## Project Structure

### Documentation

```text
specs/012-private-aca/
├── plan.md              # This file
├── spec.md              # Feature specification ✅
├── tasks.md             # Task breakdown ✅
└── checklists/
    └── requirements.md  # Specification checklist ✅
```

### Implementation Files

```text
bicep/
├── modules/
│   ├── aca-environment.bicep     # Reusable ACA environment module ✅
│   ├── log-analytics.bicep       # Reusable Log Analytics module ✅
│   ├── private-dns-zones.bicep   # Modified: added ACA DNS zone ✅
│   └── shared-services-vnet.bicep# Modified: expanded VNet, added ACA subnet ✅
├── aca/
│   ├── main.bicep                # Orchestration template ✅
│   ├── main.parameters.json      # Dev parameter values ✅
│   └── main.parameters.example.json # Template with descriptions ✅
scripts/
├── deploy-aca.sh                 # Deployment orchestration ✅
├── validate-aca.sh               # Pre/post-deploy validation ✅
├── validate-aca-dns.sh           # DNS resolution validation ✅
└── cleanup-aca.sh                # Resource cleanup ✅
docs/
└── aca/
    └── README.md                 # Full documentation ✅
```

## Phases

### Phase 0: Core Infrastructure Changes (Blocking)

Modifications to existing core infrastructure modules:

1. **Expand shared services VNet** from `/24` to `/22` (10.1.0.0/22)
2. **Add ACA subnet** at `10.1.2.0/23` with `Microsoft.App/environments` delegation
3. **Add private DNS zone** `privatelink.azurecontainerapps.io` to core DNS zones module

### Phase 1: Bicep Modules

Create reusable modules:

1. **aca-environment.bicep** - ACA environment resource with VNet injection, private endpoint, DNS zone group
2. **log-analytics.bicep** - Log Analytics workspace (reusable for future projects)

### Phase 2: Orchestration

1. **main.bicep** - Subscription-scoped template referencing core resources, deploying RG + LA + ACA
2. **Parameter files** - Dev defaults and example template

### Phase 3: Scripts

Deployment automation following existing patterns:

1. **deploy-aca.sh** - What-if → confirm → deploy → post-validate
2. **validate-aca.sh** - Pre-deploy checks (login, params, core infra) + deployed validation
3. **validate-aca-dns.sh** - DNS resolution testing (private IP, timing, public blocked)
4. **cleanup-aca.sh** - Confirm → delete RG

### Phase 4: Documentation & Specs

1. **docs/aca/README.md** - Full documentation
2. **specs/012-private-aca/** - Spec, plan, tasks, checklists
3. **README.md update** - Add ACA to infrastructure projects table

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| VNet expansion | /24 → /22 | ACA requires /23 subnet minimum; /22 provides room |
| Both VNet injection + PE | Yes | Full isolation: VNet injection for data, PE for management |
| Consumption plan | Consumption-only | Lab/dev workloads; no dedicated compute needed |
| Log Analytics | New in rg-ai-aca | No existing shared workspace; parameterized for future consolidation |
| Internal ingress | Always internal | No external access; matches private-first architecture |
| DNS zone | Added to core | Follows pattern of centralized DNS in rg-ai-core |
