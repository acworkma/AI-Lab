# Implementation Plan: Core Azure vWAN Infrastructure with Global Secure Access

**Branch**: `001-vwan-core` | **Date**: 2025-12-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-vwan-core/spec.md`

## Summary

Deploy foundational Azure infrastructure in East US 2 region consisting of resource group `rg-ai-core` with Virtual WAN hub, site-to-site VPN Gateway configured for Microsoft Entra Global Secure Access integration, and Azure Key Vault for centralized secrets management. This establishes the hub-spoke network topology with Security Service Edge (SSE) capabilities that all future labs will connect to. All infrastructure defined as Bicep templates with parameterized deployments using Azure CLI.

## Technical Context

**Language/Version**: Bicep (latest stable version compatible with Azure CLI)  
**Primary Dependencies**: Azure CLI (az deployment), Azure Virtual WAN, Azure VPN Gateway, Azure Key Vault  
**Storage**: Azure Key Vault for secrets storage  
**Testing**: Azure CLI what-if validation, Azure deployment validation, connectivity tests  
**Target Platform**: Microsoft Azure (East US 2 region)
**Project Type**: Infrastructure as Code (IaC) - Bicep templates and deployment scripts  
**Performance Goals**: Complete infrastructure deployment in under 30 minutes, zero configuration drift  
**Constraints**: Must use Bicep only (no ARM JSON), all secrets in Key Vault (no source control), idempotent deployments  
**Scale/Scope**: Single hub infrastructure supporting unlimited spoke labs, foundation for multi-lab environment

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle 1: Infrastructure as Code (IaC)
- ✅ **Bicep Only**: All resources defined in Bicep templates
- ✅ **No Manual Changes**: Deployment only via Azure CLI, no portal changes
- ✅ **Version Control**: All Bicep files tracked in Git on feature branch
- ✅ **Parameterization**: Templates will use parameters for region, environment, naming
- ✅ **Modularity**: Reusable modules planned for resource group, vWAN, VPN Gateway, Key Vault

### Principle 2: Hub-Spoke Network Architecture
- ✅ **Core Lab (Hub)**: Deploying `rg-ai-core` with vWAN hub, VPN Gateway, Key Vault
- ✅ **Core First**: This IS the core infrastructure - foundation for all future labs
- ✅ **vWAN Configuration**: Hub will be configured to accept spoke connections

### Principle 3: Resource Organization
- ✅ **Naming Convention**: Using `rg-ai-core` as specified in constitution
- ✅ **Tagging Requirements**: Will implement environment, purpose, owner tags
- ✅ **Separation of Concerns**: Single resource group for all core infrastructure

### Principle 4: Security and Secrets Management
- ✅ **NO SECRETS IN SOURCE CONTROL**: .gitignore configured, parameter files use Key Vault references
- ✅ **Centralized Key Vault**: Deploying Key Vault in `rg-ai-core` for all labs
- ✅ **Secure Parameter Passing**: Bicep templates will use Key Vault references
- ✅ **Access Control**: RBAC policies will be configured
- ✅ **.gitignore**: Local parameter files with secrets excluded

### Principle 5: Deployment Standards
- ✅ **Azure Deploy**: Using Azure CLI `az deployment`
- ✅ **What-If Analysis**: Deployment scripts will include `--what-if` validation
- ✅ **Validation**: Azure deployment validation gates included
- ✅ **Rollback Procedures**: Documentation will include rollback steps
- ✅ **Deployment Logs**: Command outputs logged

### Principle 6: Lab Modularity and Independence
- ✅ **Independent Deployment**: Core infrastructure is independently deployable
- ✅ **Clean Deletion**: Resource group can be deleted cleanly
- ✅ **Minimal Dependencies**: No dependencies on other labs (this is the foundation)

### Principle 7: Documentation Standards
- ✅ **README Template**: Will include all required sections per constitution
- ✅ **Bicep Comments**: Inline comments planned for complex logic
- ✅ **Parameter Files**: Documentation for all parameters

**Constitution Check Result**: ✅ PASSED - All principles satisfied, no violations

## Project Structure

### Documentation (this feature)

```text
specs/001-vwan-core/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - Azure vWAN and Bicep best practices
├── data-model.md        # Phase 1 output - Resource relationships and dependencies
├── quickstart.md        # Phase 1 output - Deployment guide for core infrastructure
├── contracts/           # Phase 1 output - Parameter schemas and deployment contracts
│   ├── main.parameters.schema.json
│   └── deployment-contract.md
├── checklists/          # Already created
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Infrastructure as Code structure
bicep/
├── modules/
│   ├── resource-group.bicep      # Reusable RG module with tagging
│   ├── vwan-hub.bicep            # Virtual WAN hub module
│   ├── vpn-gateway.bicep         # VPN Gateway module
│   └── key-vault.bicep           # Key Vault module with RBAC
├── main.bicep                     # Main orchestration template
└── main.parameters.json          # Parameter file (no secrets)

scripts/
├── deploy-core.sh                # Deployment script with what-if
├── validate-core.sh              # Post-deployment validation
└── cleanup-core.sh               # Teardown script

docs/
└── core-infrastructure/
    ├── README.md                 # Deployment guide per constitution
    ├── architecture-diagram.png  # Hub-spoke network diagram
    └── troubleshooting.md        # Common issues

.gitignore                        # Excludes *.local.parameters.json
```

**Structure Decision**: Infrastructure as Code structure with modular Bicep templates. Core infrastructure uses `bicep/modules/` for reusable components and root-level `main.bicep` for orchestration. Deployment scripts in `scripts/` directory follow constitution's Azure CLI and what-if requirements. Documentation in `docs/core-infrastructure/` follows README template from constitution.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations detected. All constitutional principles are satisfied by this implementation plan.
