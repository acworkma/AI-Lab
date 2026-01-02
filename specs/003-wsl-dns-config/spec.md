# Feature Specification: WSL DNS Configuration for Azure Private DNS

**Feature Branch**: `003-wsl-dns-config`  
**Created**: 2026-01-02  
**Status**: Draft  
**Input**: User description: "Configure WSL to use Azure private DNS for VPN connectivity"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enable Private DNS Resolution in WSL (Priority: P1)

As a developer using WSL on a Windows VM connected to Azure VPN, I need WSL to resolve Azure private DNS zones correctly so that I can access private Azure resources (like ACR, Key Vault) by their FQDNs without manually managing /etc/hosts entries.

**Why this priority**: This is the foundation for all private resource access from WSL. Without proper DNS resolution, developers must manually maintain /etc/hosts entries for every private resource, which is error-prone and doesn't scale.

**Independent Test**: Can be fully tested by configuring WSL DNS settings, reconnecting VPN, and verifying that `nslookup acraihubk2lydtz5uba3q.azurecr.io` resolves to the private IP (10.1.0.x) instead of public IP. Delivers functional private DNS resolution from WSL.

**Acceptance Scenarios**:

1. **Given** WSL is configured with Azure DNS resolver, **When** running `nslookup [private-resource].azurecr.io`, **Then** FQDN resolves to private endpoint IP (10.x.x.x range)
2. **Given** Azure VPN is connected, **When** accessing ACR from WSL using private FQDN, **Then** connection succeeds without 403 firewall errors
3. **Given** WSL DNS configuration is applied, **When** VPN disconnects and reconnects, **Then** DNS resolution continues to work without manual intervention
4. **Given** multiple private DNS zones exist (ACR, Key Vault, Storage), **When** querying any private resource, **Then** all resolve to their respective private IPs automatically

---

### User Story 2 - Automated WSL DNS Configuration Script (Priority: P2)

As an infrastructure engineer, I need an automated script to configure WSL DNS settings so that new team members can quickly set up their WSL environment without manual configuration steps.

**Why this priority**: Reduces onboarding time and human error. Essential for team scalability but depends on understanding the correct DNS configuration first (P1).

**Independent Test**: Can be tested by running the configuration script on a fresh WSL instance and verifying DNS resolution works immediately. Delivers automated, repeatable WSL setup.

**Acceptance Scenarios**:

1. **Given** fresh WSL installation with default DNS, **When** running the configuration script, **Then** /etc/wsl.conf and /etc/resolv.conf are updated correctly
2. **Given** configuration script completes, **When** script prompts for WSL restart, **Then** clear instructions are provided to restart WSL from PowerShell
3. **Given** script runs on already-configured WSL, **When** re-running the script, **Then** script detects existing configuration and reports status without breaking existing setup
4. **Given** script execution completes successfully, **When** user validates DNS, **Then** verification steps confirm private DNS resolution is working

---

### User Story 3 - Documentation and Troubleshooting Guide (Priority: P3)

As a developer new to the Azure VPN + WSL setup, I need clear documentation explaining why WSL DNS configuration is necessary and how to troubleshoot common issues so that I can resolve DNS problems independently.

**Why this priority**: Improves self-service capabilities and reduces support burden. Can be added incrementally after automation works.

**Independent Test**: Can be tested by following the documentation on a clean system and successfully resolving all common troubleshooting scenarios. Delivers comprehensive reference documentation.

**Acceptance Scenarios**:

1. **Given** documentation exists, **When** reading the "Why is this needed?" section, **Then** clear explanation of WSL DNS behavior vs Windows DNS behavior is provided
2. **Given** DNS resolution fails, **When** following troubleshooting guide, **Then** step-by-step diagnosis commands identify the root cause
3. **Given** common error scenarios (DNS not resolving, resolving to public IP), **When** following remediation steps, **Then** issue is resolved
4. **Given** documentation includes examples, **When** user tests each example command, **Then** all commands execute successfully and produce expected output

---

### Edge Cases

- What happens when WSL is used without Azure VPN connected (DNS should gracefully fall back)?
- How does system handle WSL version differences (WSL1 vs WSL2 DNS behavior)?
- What if Azure DNS resolver (168.63.129.16) becomes unavailable?
- How to handle scenarios where user needs both Azure private DNS and corporate DNS servers?
- What if /etc/wsl.conf or /etc/resolv.conf are managed by other tools (conflicts)?
- How does configuration persist across WSL distribution reinstalls or updates?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST configure WSL to use Azure DNS resolver (168.63.129.16) for DNS queries
- **FR-002**: WSL MUST disable automatic /etc/resolv.conf generation to prevent configuration overwrite
- **FR-003**: Configuration MUST persist across WSL restarts and Windows reboots
- **FR-004**: System MUST preserve Azure internal DNS search domain for proper name resolution
- **FR-005**: Configuration script MUST be idempotent (safe to run multiple times)
- **FR-006**: Script MUST detect if Azure VPN is currently connected before applying changes
- **FR-007**: Script MUST backup existing /etc/wsl.conf and /etc/resolv.conf before modifications
- **FR-008**: System MUST provide verification commands to validate DNS configuration success
- **FR-009**: Documentation MUST explain the root cause (WSL DNS vs Windows DNS behavior)
- **FR-010**: Script MUST check for required permissions (sudo access) before execution
- **FR-011**: Configuration MUST support fallback DNS servers for non-Azure queries
- **FR-012**: Script MUST provide clear output messages indicating success, warnings, or errors
- **FR-013**: Documentation MUST be integrated into existing core infrastructure documentation
- **FR-014**: Script MUST be compatible with both WSL1 and WSL2

### Key Entities

- **/etc/wsl.conf**: WSL configuration file that controls system behavior including DNS generation; setting `generateResolvConf = false` disables automatic /etc/resolv.conf creation
- **/etc/resolv.conf**: System DNS resolver configuration file that specifies nameserver IPs and search domains; must point to Azure DNS (168.63.129.16) for private DNS zone resolution
- **Azure DNS Resolver (168.63.129.16)**: Azure's internal DNS service that has knowledge of private DNS zones linked to virtual networks; accessible only from Azure VPN-connected clients
- **Private DNS Zones**: Azure DNS zones (e.g., privatelink.azurecr.io) linked to virtual networks that provide private name resolution for private endpoints
- **WSL Configuration Script**: Bash script that automates the process of configuring wsl.conf and resolv.conf with proper backup and validation

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Developers can resolve private Azure resource FQDNs to private IPs within 30 seconds of applying configuration
- **SC-002**: DNS configuration persists across 100% of WSL restarts without manual re-configuration
- **SC-003**: Configuration script completes successfully in under 1 minute on standard WSL installations
- **SC-004**: Zero manual /etc/hosts entries required for accessing private Azure resources after configuration
- **SC-005**: 95% of users successfully configure WSL DNS on first attempt using automated script
- **SC-006**: DNS query response time for private resources is under 100ms when VPN is connected
- **SC-007**: Documentation enables developers to troubleshoot and resolve DNS issues independently in 90% of cases
- **SC-008**: Configuration script produces zero errors when run on already-configured systems (idempotency test)
