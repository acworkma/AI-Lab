# Phase 0: Research - WSL DNS Configuration for Azure Private DNS

**Created**: 2026-01-02  
**Purpose**: Research WSL DNS mechanisms, Azure DNS resolver capabilities, and best practices for configuring WSL to work with Azure private DNS zones over VPN.

## Problem Statement

When developers use WSL (Windows Subsystem for Linux) on a Windows VM connected to Azure VPN, WSL's default DNS configuration does not properly resolve Azure private DNS zones. This occurs because:

1. **WSL Auto-Generated DNS**: By default, WSL automatically generates `/etc/resolv.conf` based on Windows network adapters
2. **DNS Propagation Gap**: Azure private DNS zone records (e.g., `privatelink.azurecr.io`) don't propagate correctly through this auto-generation mechanism
3. **VPN DNS Context**: While Windows (host) correctly uses Azure DNS when VPN is connected, WSL (guest) doesn't inherit this configuration properly
4. **Public IP Fallback**: Private resource FQDNs resolve to public IPs, which are blocked by Azure firewall rules (403 errors)

**Impact**: Developers cannot access private Azure resources (ACR, Key Vault, Storage) from WSL without manually maintaining `/etc/hosts` entries.

## Research Topics

### 1. WSL DNS Behavior and Configuration

**Decision**: Disable WSL's automatic `/etc/resolv.conf` generation and manually configure Azure DNS resolver

**Rationale**:
- WSL2 uses a virtualized network adapter that receives DNS settings from Windows, but the propagation of private DNS zones is unreliable
- The `/etc/wsl.conf` file controls WSL's system behavior, including DNS configuration
- Setting `[network] generateResolvConf = false` stops WSL from auto-generating `/etc/resolv.conf`
- This allows manual configuration of DNS servers that persist across WSL restarts

**Alternatives Considered**:
1. **Keep auto-generation, use /etc/hosts**: Requires manual entry for every private resource; doesn't scale
2. **Windows hosts file**: Doesn't affect WSL unless mapped; requires Windows admin access
3. **DNS proxy in WSL**: Adds complexity; requires additional software installation
4. **Corporate DNS forwarding**: Not applicable in this lab environment

**Implementation Approach**:
```ini
# /etc/wsl.conf
[network]
generateResolvConf = false
```

**References**:
- [Microsoft WSL Documentation - Advanced settings configuration](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
- [WSL Network Configuration](https://learn.microsoft.com/en-us/windows/wsl/networking)

### 2. Azure DNS Resolver (168.63.129.16)

**Decision**: Configure WSL to use Azure's internal DNS resolver at 168.63.129.16

**Rationale**:
- **168.63.129.16** is Azure's internal DNS service, accessible from any Azure-connected network (VMs, VPN clients)
- This resolver has built-in knowledge of all private DNS zones linked to virtual networks in the subscription
- It automatically resolves private endpoint FQDNs to their private IPs when queried from authorized sources
- Provides authoritative responses for `*.privatelink.azurecr.io`, `*.privatelink.vaultcore.azure.net`, etc.
- Falls back to public DNS for non-private queries

**Alternatives Considered**:
1. **Public DNS (8.8.8.8, 1.1.1.1)**: Cannot resolve private DNS zones; defeats purpose
2. **Windows DNS from auto-generation**: Already proven unreliable for private zones
3. **VPN gateway DNS**: Not directly accessible; requires Azure DNS as intermediary
4. **Custom DNS server**: Unnecessary complexity; Azure DNS already provides required functionality

**Implementation Approach**:
```
# /etc/resolv.conf
nameserver 168.63.129.16
search <azure-internal-search-domain>
```

**Technical Details**:
- Azure DNS resolver is accessible only when connected via Azure network (VPN, VNet peering, or Azure VM)
- Provides sub-100ms query response times for Azure resources
- Automatically updated as private DNS zones and records change
- No authentication required; access control is network-based (must be on Azure network)

**References**:
- [Azure DNS Documentation](https://learn.microsoft.com/en-us/azure/dns/dns-overview)
- [Name resolution for resources in Azure virtual networks](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-name-resolution-for-vms-and-role-instances)
- [Azure DNS Private Zones](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)

### 3. Private DNS Zone Resolution

**Decision**: Rely on Azure DNS's automatic private zone resolution via VNet links

**Rationale**:
- Private DNS zones (e.g., `privatelink.azurecr.io`) are already linked to the shared services VNet in core infrastructure
- When a private endpoint is created, Azure automatically adds A records to the linked private DNS zone
- The Azure DNS resolver (168.63.129.16) queries these private zones automatically when handling requests from linked networks
- VPN clients are part of the virtual hub's address space, giving them access to linked private DNS zones
- No additional configuration needed beyond pointing to Azure DNS resolver

**DNS Resolution Flow**:
1. WSL queries `acraihubk2lydtz5uba3q.azurecr.io`
2. Query sent to 168.63.129.16 (Azure DNS)
3. Azure DNS checks if private DNS zone `privatelink.azurecr.io` is linked to VPN client's network
4. Finds A record: `acraihubk2lydtz5uba3q.privatelink.azurecr.io` → `10.1.0.5`
5. Returns private IP to WSL
6. WSL connects to private IP via VPN tunnel

**Alternatives Considered**:
1. **Conditional forwarding**: Unnecessary; Azure DNS handles automatically
2. **Split-horizon DNS**: Already implemented by Azure private DNS zones
3. **Direct private endpoint IP**: Bypasses DNS; breaks if endpoint IP changes

**References**:
- [Azure Private Endpoint DNS Configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [Private DNS Zone Virtual Network Links](https://learn.microsoft.com/en-us/azure/dns/private-dns-virtual-network-links)

### 4. Configuration Persistence and Idempotency

**Decision**: Configuration script must backup existing files, detect existing configuration, and be safe to run multiple times

**Rationale**:
- WSL distributions can be reset or updated, potentially overwriting configuration
- Multiple team members may run the script at different times
- Script failures shouldn't leave system in broken state
- Users may want to revert to original configuration

**Best Practices**:
1. **Backup before modification**: 
   ```bash
   sudo cp /etc/wsl.conf /etc/wsl.conf.backup.$(date +%Y%m%d-%H%M%S)
   sudo cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d-%H%M%S)
   ```

2. **Check existing configuration**:
   ```bash
   if grep -q "generateResolvConf = false" /etc/wsl.conf 2>/dev/null; then
       echo "WSL DNS already configured"
       exit 0
   fi
   ```

3. **Validate before applying**:
   ```bash
   # Check sudo access
   if ! sudo -n true 2>/dev/null; then
       echo "ERROR: Script requires sudo access"
       exit 1
   fi
   
   # Check VPN connectivity (optional warning)
   if ! ping -c 1 168.63.129.16 &>/dev/null; then
       echo "WARNING: Azure DNS not reachable. Is VPN connected?"
   fi
   ```

4. **Atomic operations**: Write to temp file, then move to target location

**References**:
- [Bash scripting best practices](https://google.github.io/styleguide/shellguide.html)
- [Idempotent configuration management principles](https://en.wikipedia.org/wiki/Idempotence)

### 5. WSL Restart Requirements

**Decision**: Script must instruct users to restart WSL from PowerShell for changes to take effect

**Rationale**:
- `/etc/wsl.conf` changes require WSL instance restart to apply
- `/etc/resolv.conf` changes take effect immediately if `generateResolvConf = false` is already set
- Cleanest approach is to always restart WSL after configuration changes
- Cannot be automated from within WSL (requires Windows-level command)

**Implementation Approach**:
```bash
cat << 'EOF'

Configuration complete! Please restart WSL for changes to take effect:

1. Exit all WSL terminals
2. Open PowerShell (as Administrator) and run:
   wsl --shutdown

3. Restart your WSL distribution

After restart, verify DNS resolution:
   nslookup acraihubk2lydtz5uba3q.azurecr.io

EOF
```

**Technical Details**:
- `wsl --shutdown` terminates all running WSL distributions
- Next WSL launch will read new `/etc/wsl.conf` settings
- Restart typically takes 5-10 seconds
- No data loss; filesystem persists across restarts

**References**:
- [WSL commands and configuration](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)

### 6. Fallback DNS and Search Domains

**Decision**: Include public DNS fallback and preserve Azure internal search domain

**Rationale**:
- If Azure DNS (168.63.129.16) is unavailable (VPN disconnected), WSL should still resolve public DNS
- Azure internal search domain enables short-name resolution for Azure-internal services
- Multi-nameserver configuration provides resilience

**Implementation Approach**:
```
# /etc/resolv.conf
nameserver 168.63.129.16
nameserver 8.8.8.8
search <azure-internal-search-domain>
```

**Behavior**:
- Primary nameserver (168.63.129.16): Tries first, resolves private and public DNS
- Secondary nameserver (8.8.8.8): Used if Azure DNS unreachable or times out
- Search domain: Appended to unqualified hostnames (e.g., `vm1` → `vm1.<azure-search-domain>`)

**Alternatives Considered**:
1. **Azure DNS only**: Fails completely if VPN disconnected; poor user experience
2. **Public DNS first**: Would resolve private FQDNs to public IPs; defeats purpose
3. **No search domain**: Acceptable; search domain is optional enhancement

**References**:
- [resolv.conf man page](https://man7.org/linux/man-pages/man5/resolv.conf.5.html)
- [DNS server failover behavior](https://www.ietf.org/rfc/rfc1123.txt)

### 7. Verification and Validation

**Decision**: Provide automated verification script to validate DNS configuration success

**Rationale**:
- Users need confidence that configuration was applied correctly
- Troubleshooting requires systematic diagnosis
- Verification should test both configuration and functionality

**Validation Checks**:
```bash
# 1. Check /etc/wsl.conf
echo "Checking /etc/wsl.conf..."
grep -q "generateResolvConf = false" /etc/wsl.conf && echo "✓ WSL.conf configured" || echo "✗ WSL.conf not configured"

# 2. Check /etc/resolv.conf
echo "Checking /etc/resolv.conf..."
grep -q "168.63.129.16" /etc/resolv.conf && echo "✓ Azure DNS configured" || echo "✗ Azure DNS not configured"

# 3. Test DNS resolution
echo "Testing DNS resolution..."
PRIVATE_IP=$(nslookup acraihubk2lydtz5uba3q.azurecr.io | grep -A1 "Name:" | grep "Address:" | awk '{print $2}')
if [[ $PRIVATE_IP == 10.* ]]; then
    echo "✓ Private DNS resolves to private IP: $PRIVATE_IP"
else
    echo "✗ DNS resolves to public IP or fails: $PRIVATE_IP"
fi

# 4. Test connectivity
echo "Testing ACR connectivity..."
curl -s -o /dev/null -w "%{http_code}" https://acraihubk2lydtz5uba3q.azurecr.io/v2/ | grep -q "401\|200" && echo "✓ ACR accessible via private endpoint" || echo "✗ ACR not accessible"
```

**References**:
- [DNS troubleshooting methodology](https://www.linux.com/training-tutorials/how-to-troubleshoot-dns-linux/)

## Summary of Technical Decisions

| Decision Area | Choice | Justification |
|--------------|--------|---------------|
| WSL DNS Generation | Disable (`generateResolvConf = false`) | Allows manual control of DNS configuration |
| DNS Resolver | Azure DNS (168.63.129.16) | Required for private DNS zone resolution |
| Fallback DNS | Google DNS (8.8.8.8) | Resilience when VPN disconnected |
| Configuration Method | Bash script with backup | Automation with safety (idempotent, reversible) |
| Restart Requirement | Manual WSL shutdown required | WSL.conf changes need instance restart |
| Validation | Automated verification script | Systematic diagnosis and confidence building |
| Documentation Location | `docs/core-infrastructure/` | Consistent with constitution standards |
| Script Location | `scripts/` directory | Alongside existing infrastructure scripts |

## Open Questions Resolved

All functional requirements from the spec are fully defined with no remaining [NEEDS CLARIFICATION] markers:

- ✅ DNS resolver address: 168.63.129.16 (Azure internal DNS)
- ✅ Configuration persistence: Via /etc/wsl.conf which survives restarts
- ✅ VPN detection: Optional ping test to 168.63.129.16
- ✅ Backup strategy: Timestamped backups before modification
- ✅ Idempotency: Check existing config before applying changes
- ✅ WSL1 vs WSL2: Configuration works for both (focus on WSL2)
- ✅ Search domain: Preserve from current /etc/resolv.conf or use Azure default
- ✅ Verification method: Nslookup + curl testing against known private endpoint

## Next Steps (Phase 1)

1. Document configuration file data model (wsl.conf, resolv.conf structures)
2. Define script interface contract (inputs, outputs, exit codes)
3. Define validation contract (test criteria, expected outcomes)
4. Create quickstart guide with step-by-step instructions
5. Update agent context with Bash scripting technology
