# Implementation Tasks: WSL DNS Configuration for Azure Private DNS

**Feature**: 003-wsl-dns-config  
**Created**: 2026-01-02  
**Sprint Goal**: Enable WSL to resolve Azure private DNS zones for VPN-connected developers

## Task Organization

Tasks are organized by **User Story** to enable independent implementation and testing. Each user story represents a complete, deployable increment.

**Story Dependencies**:
- User Story 1 (P1) → Foundational, no dependencies
- User Story 2 (P2) → Depends on User Story 1 completion
- User Story 3 (P3) → Can proceed in parallel with User Story 2

**Parallel Execution**: Tasks marked with `[P]` can be executed in parallel with other `[P]` tasks in the same phase.

## Implementation Strategy

**MVP Scope**: User Story 1 only
- Delivers core DNS configuration capability
- Manually configurable following quickstart guide
- Sufficient for immediate team needs

**Incremental Delivery**:
1. Sprint 1: User Story 1 (Manual configuration works)
2. Sprint 2: User Story 2 (Automated via script)
3. Sprint 3: User Story 3 (Full documentation and troubleshooting)

---

## Phase 1: Setup and Initialization

### Story: Project Setup

- [ ] T001 Create project directory structure per implementation plan
- [ ] T002 Initialize git branch 003-wsl-dns-config (already done, verify clean state)
- [ ] T003 Create placeholder scripts in scripts/ directory

**Story Goal**: Repository structure ready for implementation  
**Test**: All directories and placeholder files exist in correct locations

---

## Phase 2: User Story 1 - Enable Private DNS Resolution in WSL (P1)

### Story Goal
Developers can manually configure WSL to resolve Azure private DNS zones to private IPs, enabling access to private Azure resources without /etc/hosts entries.

### Independent Test Criteria
- [ ] WSL /etc/wsl.conf configured with `generateResolvConf = false`
- [ ] WSL /etc/resolv.conf configured with `nameserver 168.63.129.16`
- [ ] `nslookup acraihubk2lydtz5uba3q.azurecr.io` resolves to private IP (10.1.0.x)
- [ ] `curl https://acraihubk2lydtz5uba3q.azurecr.io/v2/` returns 401 (not 403)
- [ ] Configuration persists after WSL restart

### Implementation Tasks

#### Configuration File Templates

- [ ] T004 [P] Create /etc/wsl.conf template with generateResolvConf=false setting
- [ ] T005 [P] Create /etc/resolv.conf template with Azure DNS and fallback servers
- [ ] T006 Document required search domain format in templates

#### Manual Configuration Procedure

- [ ] T007 Write step-by-step manual configuration instructions in quickstart.md
- [ ] T008 [P] Document manual backup procedure for configuration files
- [ ] T009 [P] Document manual verification commands (nslookup, curl tests)
- [ ] T010 Document WSL restart procedure (wsl --shutdown from PowerShell)

#### Testing and Validation

- [ ] T011 Test manual configuration on fresh WSL instance
- [ ] T012 Verify private ACR DNS resolution (10.x.x.x IP)
- [ ] T013 Verify private ACR HTTPS connectivity (401/200, not 403)
- [ ] T014 Test configuration persistence after WSL restart
- [ ] T015 Test configuration persistence after Windows reboot

**Deliverables**:
- Configuration file templates
- Manual configuration documented in quickstart.md
- Verified working on at least one WSL instance

**Tests** (if requested): Manual testing checklist in validation-contract.md

---

## Phase 3: User Story 2 - Automated WSL DNS Configuration Script (P2)

### Story Goal
Infrastructure engineers can run an automated script to configure WSL DNS settings, eliminating manual steps and reducing onboarding time.

### Independent Test Criteria
- [ ] `./scripts/configure-wsl-dns.sh` runs without errors
- [ ] Script detects if configuration already applied (idempotency)
- [ ] Script creates timestamped backups before modifications
- [ ] Script outputs clear success/error messages
- [ ] Script prompts for WSL restart with instructions
- [ ] After script + restart, private DNS resolution works

### Implementation Tasks

#### Script Foundation

- [ ] T016 Create scripts/configure-wsl-dns.sh with shebang and basic structure
- [ ] T017 Implement prerequisite checks (sudo access, required utilities)
- [ ] T018 Implement VPN connectivity check (ping 168.63.129.16)
- [ ] T019 Implement help text and usage display (--help flag)

#### Idempotency and Detection

- [ ] T020 Implement existing configuration detection in /etc/wsl.conf
- [ ] T021 Implement existing configuration detection in /etc/resolv.conf
- [ ] T022 Add --force flag to override existing configuration detection
- [ ] T023 Implement dry-run mode (--verify-only flag) that checks without modifying

#### Backup Functionality

- [ ] T024 [P] Implement backup function with timestamp generation
- [ ] T025 [P] Implement backup of /etc/wsl.conf to /etc/wsl.conf.backup.YYYYMMDD-HHMMSS
- [ ] T026 [P] Implement backup of /etc/resolv.conf to /etc/resolv.conf.backup.YYYYMMDD-HHMMSS
- [ ] T027 Validate backup files are created and readable

#### Configuration Application

- [ ] T028 Implement /etc/wsl.conf creation/modification function
- [ ] T029 Implement /etc/resolv.conf creation/modification function
- [ ] T030 Preserve existing search domain from current resolv.conf if present
- [ ] T031 Use atomic file operations (write to temp, then move)

#### Output and Messaging

- [ ] T032 [P] Implement colored output functions ([INFO], [OK], [WARNING], [ERROR])
- [ ] T033 [P] Add progress messages for each configuration step
- [ ] T034 [P] Implement post-configuration instructions (WSL restart steps)
- [ ] T035 Add troubleshooting reference at end of script output

#### Error Handling

- [ ] T036 Implement error handling for permission denied (exit code 2)
- [ ] T037 Implement error handling for backup failures (exit code 4)
- [ ] T038 Implement error handling for configuration write failures (exit code 5)
- [ ] T039 Implement graceful handling of VPN not connected (warning, not error)

#### Script Testing

- [ ] T040 Test script on fresh WSL instance (first-run scenario)
- [ ] T041 Test script idempotency (re-run on configured system)
- [ ] T042 Test script with --force flag (reconfiguration scenario)
- [ ] T043 Test script with --verify-only flag (no modifications)
- [ ] T044 Test script error scenarios (no sudo, backup failures, etc.)
- [ ] T045 Make script executable (chmod +x scripts/configure-wsl-dns.sh)

**Deliverables**:
- Fully functional configure-wsl-dns.sh script (~200 lines)
- Script tested on multiple WSL instances
- Script handles all error scenarios gracefully

**Tests** (if requested): Automated script unit tests

---

## Phase 4: Validation and Verification Automation

### Story Goal
Provide automated validation script to verify DNS configuration is working correctly across all levels.

### Independent Test Criteria
- [ ] `./scripts/validate-wsl-dns.sh` runs without errors
- [ ] Script checks all 4 validation levels (config, network, DNS, connectivity)
- [ ] Script outputs pass/fail for each check
- [ ] Script exits 0 if all checks pass, exits 1 if any fail
- [ ] Script output is clear and actionable

### Implementation Tasks

#### Validation Script Foundation

- [ ] T046 Create scripts/validate-wsl-dns.sh with basic structure
- [ ] T047 Implement check() function for pass/fail testing
- [ ] T048 Implement counter for passed/failed checks
- [ ] T049 Implement colored output for pass (✅) and fail (❌)

#### Level 1: Configuration File Validation

- [ ] T050 [P] Check /etc/wsl.conf exists
- [ ] T051 [P] Check generateResolvConf = false in wsl.conf
- [ ] T052 [P] Check /etc/resolv.conf exists
- [ ] T053 [P] Check nameserver 168.63.129.16 in resolv.conf

#### Level 2: Network Connectivity Validation

- [ ] T054 [P] Check Azure DNS reachable (ping 168.63.129.16)
- [ ] T055 [P] Check DNS queries work (nslookup google.com 168.63.129.16)

#### Level 3: Private DNS Resolution Validation

- [ ] T056 Check ACR FQDN resolves to private IP (10.x.x.x pattern match)
- [ ] T057 Display resolved IP address in output

#### Level 4: Connectivity Validation

- [ ] T058 Check ACR HTTPS returns 401/200 (not 403 or timeout)
- [ ] T059 Display HTTP status code in output

#### Summary and Reporting

- [ ] T060 [P] Implement summary output (X passed, Y failed)
- [ ] T061 [P] Implement exit code logic (0 if all pass, 1 if any fail)
- [ ] T062 [P] Add troubleshooting reference on failure
- [ ] T063 Make script executable (chmod +x scripts/validate-wsl-dns.sh)

#### Validation Testing

- [ ] T064 Test validation script on properly configured system
- [ ] T065 Test validation script on unconfigured system
- [ ] T066 Test validation script with VPN disconnected
- [ ] T067 Test validation script with partial configuration

**Deliverables**:
- Fully functional validate-wsl-dns.sh script (~100 lines)
- Script integrated into quickstart.md instructions

**Tests** (if requested): Validation script unit tests

---

## Phase 5: User Story 3 - Documentation and Troubleshooting Guide (P3)

### Story Goal
Developers can self-serve WSL DNS configuration and troubleshoot issues independently using comprehensive documentation.

### Independent Test Criteria
- [ ] Documentation explains WHY WSL DNS config is needed
- [ ] Documentation provides step-by-step setup instructions
- [ ] Troubleshooting guide covers all common error scenarios
- [ ] Documentation includes working examples for all commands
- [ ] Documentation integrated into core infrastructure docs

### Implementation Tasks

#### Core Documentation

- [ ] T068 [P] Create docs/core-infrastructure/wsl-dns-setup.md with overview section
- [ ] T069 [P] Document WSL DNS behavior and why configuration is needed
- [ ] T070 [P] Document Azure DNS resolver (168.63.129.16) role
- [ ] T071 [P] Document private DNS zone resolution flow

#### Setup Instructions

- [ ] T072 [P] Document prerequisites (WSL2, VPN, sudo access)
- [ ] T073 [P] Document automated setup using configure-wsl-dns.sh script
- [ ] T074 [P] Document manual setup as alternative
- [ ] T075 [P] Document verification steps using validate-wsl-dns.sh

#### Troubleshooting Guide

- [ ] T076 [P] Document "Azure DNS not reachable" troubleshooting
- [ ] T077 [P] Document "Resolves to public IP" troubleshooting
- [ ] T078 [P] Document "403 Forbidden errors" troubleshooting
- [ ] T079 [P] Document "Configuration reverts after restart" troubleshooting
- [ ] T080 [P] Document rollback procedures using backup files

#### Examples and Testing

- [ ] T081 [P] Add example commands with expected outputs
- [ ] T082 [P] Add FAQ section addressing common questions
- [ ] T083 [P] Test all documented commands on fresh WSL instance
- [ ] T084 [P] Verify all example outputs match actual behavior

#### Integration with Existing Docs

- [ ] T085 Update docs/core-infrastructure/README.md with WSL prerequisite section
- [ ] T086 Update docs/core-infrastructure/troubleshooting.md with WSL DNS section
- [ ] T087 Reference WSL DNS setup in docs/registry/README.md prerequisites
- [ ] T088 Add cross-references between documentation files

#### Quickstart Refinement

- [ ] T089 [P] Review and update specs/003-wsl-dns-config/quickstart.md based on testing
- [ ] T090 [P] Add screenshots or ASCII diagrams where helpful (optional)
- [ ] T091 [P] Verify quickstart timing estimates (5-10 minutes)
- [ ] T092 [P] Add validation success/failure example outputs

**Deliverables**:
- Complete wsl-dns-setup.md documentation
- Updated core infrastructure documentation
- Tested and validated quickstart guide

**Tests** (if requested): Documentation review checklist

---

## Phase 6: Polish and Cross-Cutting Concerns

### Story Goal
Code quality, consistency, and professional polish across all deliverables.

### Implementation Tasks

#### Code Quality

- [ ] T093 [P] Add header comments to all scripts (purpose, usage, author, date)
- [ ] T094 [P] Add inline comments explaining complex logic in scripts
- [ ] T095 [P] Ensure consistent error message formatting across scripts
- [ ] T096 [P] Add script version numbers and update version history

#### Script Enhancements (Optional)

- [ ] T097 [P] Add --dns-server flag to customize DNS server in configure script
- [ ] T098 [P] Add --skip-backup flag for advanced users
- [ ] T099 [P] Add logging to /var/log or temp directory (optional)

#### Testing and Validation

- [ ] T100 Perform end-to-end testing on Windows 10 WSL2
- [ ] T101 Perform end-to-end testing on Windows 11 WSL2
- [ ] T102 Test on Ubuntu 20.04 WSL distribution
- [ ] T103 Test on Ubuntu 22.04 WSL distribution (if available)
- [ ] T104 Test with VPN connected and disconnected scenarios

#### Documentation Polish

- [ ] T105 [P] Spell-check and grammar-check all documentation
- [ ] T106 [P] Ensure consistent terminology across all docs
- [ ] T107 [P] Validate all links and cross-references work
- [ ] T108 [P] Ensure code blocks have proper syntax highlighting hints

#### Integration Testing

- [ ] T109 Verify configuration enables ACR access per 002-private-acr requirements
- [ ] T110 Verify configuration works with core infrastructure VPN setup
- [ ] T111 Test on system with both configure and validate scripts
- [ ] T112 Verify scripts work from any working directory

**Deliverables**:
- Production-ready scripts and documentation
- Tested across multiple WSL distributions and Windows versions

---

## Dependencies Between User Stories

```
User Story 1 (P1): Manual Configuration
    ↓ (provides foundation)
User Story 2 (P2): Automated Script
    ↓ (provides tooling for)
User Story 3 (P3): Documentation
```

**Critical Path**: User Story 1 → User Story 2
**Parallel Work**: User Story 3 can begin once User Story 1 is complete

---

## Parallel Execution Opportunities

### Within User Story 1 (P1)
- T004, T005 (templates) can be created in parallel
- T008, T009 (documentation) can be written in parallel

### Within User Story 2 (P2)
- T024, T025, T026 (backup functions) can be implemented in parallel
- T032, T033, T034, T035 (output messaging) can be implemented in parallel

### Within Validation Phase
- T050-T053 (Level 1 checks) can be implemented in parallel
- T054-T055 (Level 2 checks) can be implemented in parallel

### Within User Story 3 (P3)
- Most documentation tasks (T068-T084) can be written in parallel
- T085-T088 (doc integration) can be done in parallel

---

## Task Summary

**Total Tasks**: 112
- Phase 1 (Setup): 3 tasks
- Phase 2 (US1 - Manual Config): 12 tasks
- Phase 3 (US2 - Automation): 30 tasks
- Phase 4 (Validation): 22 tasks
- Phase 5 (US3 - Documentation): 25 tasks
- Phase 6 (Polish): 20 tasks

**Parallelizable Tasks**: 43 tasks marked with [P]

**Estimated Effort**:
- User Story 1 (P1): 4-6 hours (MVP)
- User Story 2 (P2): 8-12 hours (Automation)
- User Story 3 (P3): 6-8 hours (Documentation)
- Total: 18-26 hours

**Recommended Approach**: Implement in story order (P1 → P2 → P3) for incremental delivery.

---

## Success Validation

After all tasks complete, the feature is successful if:

- ✅ **SC-001**: Private DNS resolves within 30 seconds of configuration
- ✅ **SC-002**: Configuration persists across WSL restarts (100%)
- ✅ **SC-003**: Configuration script completes in <1 minute
- ✅ **SC-004**: Zero /etc/hosts entries needed
- ✅ **SC-005**: 95% first-attempt success rate (team testing)
- ✅ **SC-006**: DNS queries <100ms response time
- ✅ **SC-007**: 90% self-service troubleshooting success
- ✅ **SC-008**: Idempotency produces zero errors

All success criteria from spec.md must be validated before marking feature complete.
