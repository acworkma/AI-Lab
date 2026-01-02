# Implementation Plan: WSL DNS Configuration for Azure Private DNS

**Branch**: `003-wsl-dns-config` | **Date**: 2026-01-02 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `/specs/003-wsl-dns-config/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enable developers using WSL on Windows VMs to access Azure private DNS zones through VPN connectivity by configuring WSL to use Azure's internal DNS resolver (168.63.129.16). This eliminates the need for manual /etc/hosts management and enables automatic resolution of all private Azure resources (ACR, Key Vault, Storage) to their private endpoint IP addresses.

## Technical Context

**Language/Version**: Bash 4.0+ (standard on Ubuntu 20.04+ WSL distributions)  
**Primary Dependencies**: None (standard Linux utilities: sudo, cat, grep, nslookup)  
**Storage**: Local configuration files (/etc/wsl.conf, /etc/resolv.conf) with backup copies  
**Testing**: Manual verification via nslookup, curl, and Azure CLI commands  
**Target Platform**: WSL2 on Windows 10/11 (basic WSL1 compatibility attempted)  
**Project Type**: Configuration script and documentation (no build artifacts)  
**Performance Goals**: Script execution <1 minute, DNS resolution <100ms  
**Constraints**: Requires sudo access, Azure VPN must be connected, persistent across WSL restarts  
**Scale/Scope**: Single configuration script (~200 lines), 2 config files, documentation integration

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

✅ **Infrastructure as Code (IaC)**: N/A - This feature configures local WSL environment, not Azure resources  
✅ **Hub-Spoke Network Architecture**: Compliant - Prerequisite for core infrastructure, enables private DNS resolution  
✅ **Resource Organization**: N/A - No Azure resources created by this feature  
✅ **Security and Secrets Management**: Compliant - No secrets involved, configuration is local to WSL  
✅ **Deployment Standards**: Compliant - Script follows bash conventions, includes validation and idempotency  
✅ **Lab Modularity**: Compliant - Configuration is independent, required only for WSL users accessing private resources  
✅ **Documentation Standards**: Compliant - Will integrate into docs/core-infrastructure/ with troubleshooting guide

**Gate Status**: ✅ PASS - No constitution violations. Feature is a local environment prerequisite.

**Notes**: 
- This feature does not deploy Azure infrastructure; it configures the local WSL development environment
- Enables compliance with "private-only" networking principles by allowing WSL to resolve private endpoints
- Documentation will be added to core infrastructure docs as a prerequisite setup step

## Project Structure

### Documentation (this feature)

```text
specs/003-wsl-dns-config/
├── plan.md              # This file (/speckit.plan command output)
├── spec.md              # Feature specification
├── research.md          # Phase 0 output - WSL DNS research and best practices
├── data-model.md        # Phase 1 output - Configuration file structures
├── quickstart.md        # Phase 1 output - Step-by-step setup guide
├── contracts/           # Phase 1 output - Script interface and validation contracts
│   ├── script-contract.md
│   └── validation-contract.md
└── checklists/
    └── requirements.md  # Specification quality checklist
```

### Source Code (repository root)

```text
scripts/
├── configure-wsl-dns.sh     # WSL DNS configuration automation script
├── validate-wsl-dns.sh      # DNS configuration validation script
└── deploy-core.sh           # Existing - will reference WSL setup as prerequisite

docs/
└── core-infrastructure/
    ├── README.md            # Updated with WSL prerequisite section
    ├── wsl-dns-setup.md     # New - Comprehensive WSL DNS configuration guide
    └── troubleshooting.md   # Updated with WSL DNS troubleshooting section
```

**Structure Decision**: Configuration scripts live in `/scripts` alongside other infrastructure automation. Documentation integrates into existing `/docs/core-infrastructure` to maintain consistency with constitution's documentation standards. No build artifacts or compiled code - pure bash scripting and markdown documentation.

## Complexity Tracking

*No constitution violations detected. This section is not applicable.*

---

## Phase 0: Research Complete ✅

All research completed in [research.md](research.md):
- WSL DNS behavior and auto-generation mechanisms
- Azure DNS resolver (168.63.129.16) capabilities
- Private DNS zone resolution flow
- Configuration persistence and idempotency patterns
- WSL restart requirements
- Fallback DNS and search domain handling
- Verification and validation approaches

**Key Decisions**:
- Use Azure DNS (168.63.129.16) as primary nameserver
- Disable WSL auto-generation (`generateResolvConf = false`)
- Implement idempotent bash script with backup capability
- Provide automated validation script

---

## Phase 1: Design Complete ✅

### Data Model ([data-model.md](data-model.md))
- Configuration file entities documented
- State machine for configuration lifecycle
- DNS resolution data flow
- File dependency graph
- Validation data structures

### Contracts ([contracts/](contracts/))
- **Script Contract**: CLI interface, exit codes, output format, idempotency guarantees
- **Validation Contract**: 5-level validation (config files, network, DNS resolution, connectivity, persistence)

### Quickstart ([quickstart.md](quickstart.md))
- Step-by-step configuration guide
- Prerequisites and verification steps
- Manual configuration alternative
- Comprehensive troubleshooting section
- Rollback procedures

### Agent Context
- GitHub Copilot context updated with Bash/WSL technology stack

---

## Constitution Re-Check (Post-Design) ✅

**Re-evaluated after Phase 1 design completion:**

✅ **Infrastructure as Code**: N/A - Local WSL configuration only  
✅ **Hub-Spoke Architecture**: Enables access to hub infrastructure  
✅ **Resource Organization**: No Azure resources created  
✅ **Security**: No secrets, local configuration only  
✅ **Deployment Standards**: Bash script follows best practices (idempotent, validated, documented)  
✅ **Lab Modularity**: Independent configuration, optional for non-WSL users  
✅ **Documentation**: Integrates with core infrastructure docs per standards  

**Final Gate Status**: ✅ PASS - All constitution principles upheld

---

## Phase 2: Implementation Tasks

**Note**: Phase 2 tasks are generated by the `/speckit.tasks` command (NOT by `/speckit.plan`).

To proceed with implementation:
```bash
/speckit.tasks
```

This will create `tasks.md` with concrete implementation tasks based on this plan.

---

## Summary

This implementation plan provides a complete blueprint for enabling WSL DNS resolution of Azure private DNS zones. The feature:

- **Solves**: WSL's inability to resolve private Azure resources over VPN
- **Approach**: Configure WSL to use Azure DNS (168.63.129.16) with persistent settings
- **Deliverables**: 
  - Configuration script (`configure-wsl-dns.sh`)
  - Validation script (`validate-wsl-dns.sh`)
  - Comprehensive documentation integrated into core infrastructure docs
- **Compliance**: Fully aligned with AI-Lab constitution
- **Testing**: 5-level validation ensures correctness and persistence

Ready for Phase 2 task generation and implementation.
