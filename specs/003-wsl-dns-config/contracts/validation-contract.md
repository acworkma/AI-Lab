# Validation Contract: WSL DNS Configuration

**Version**: 1.0  
**Created**: 2026-01-02  
**Purpose**: Define acceptance criteria and validation procedures for WSL DNS configuration

## Validation Scope

This contract defines how to verify that WSL DNS configuration is correctly applied and functioning as expected for Azure private DNS resolution.

## Validation Levels

### Level 1: Configuration File Validation

Verify that configuration files are properly created and formatted.

#### 1.1: /etc/wsl.conf Validation

**Test**: WSL.conf exists and has correct content
```bash
# Check file exists
test -f /etc/wsl.conf
echo "Exit code: $?"  # Expected: 0

# Check generateResolvConf setting
grep -q "^\[network\]" /etc/wsl.conf && \
  grep -q "^generateResolvConf = false" /etc/wsl.conf
echo "Exit code: $?"  # Expected: 0
```

**Acceptance Criteria**:
- ✅ `/etc/wsl.conf` file exists
- ✅ Contains `[network]` section
- ✅ Contains `generateResolvConf = false` setting
- ✅ File is readable (permissions 644 or more permissive)

#### 1.2: /etc/resolv.conf Validation

**Test**: Resolv.conf contains Azure DNS resolver
```bash
# Check file exists
test -f /etc/resolv.conf
echo "Exit code: $?"  # Expected: 0

# Check Azure DNS present
grep -q "^nameserver 168.63.129.16" /etc/resolv.conf
echo "Exit code: $?"  # Expected: 0

# Check fallback DNS present (optional)
grep -q "^nameserver 8.8.8.8" /etc/resolv.conf
echo "Exit code: $?"  # Expected: 0 (warning if absent)
```

**Acceptance Criteria**:
- ✅ `/etc/resolv.conf` file exists
- ✅ Contains `nameserver 168.63.129.16` as first nameserver
- ✅ Contains fallback nameserver (8.8.8.8 or other)
- ✅ File is readable (permissions 644 or more permissive)

#### 1.3: Backup File Validation

**Test**: Backup files were created
```bash
# Check for backup files (pattern match)
ls -1 /etc/wsl.conf.backup.* 2>/dev/null | wc -l
# Expected: >= 1

ls -1 /etc/resolv.conf.backup.* 2>/dev/null | wc -l
# Expected: >= 1
```

**Acceptance Criteria**:
- ✅ At least one wsl.conf backup exists
- ✅ At least one resolv.conf backup exists
- ✅ Backup filenames match pattern: `<original>.backup.YYYYMMDD-HHMMSS`
- ✅ Backups are readable

### Level 2: Network Connectivity Validation

Verify that Azure DNS resolver is reachable and responding.

#### 2.1: Azure DNS Reachability

**Test**: Azure DNS responds to ping
```bash
# Ping Azure DNS
ping -c 1 -W 2 168.63.129.16
echo "Exit code: $?"  # Expected: 0 (if VPN connected)
```

**Acceptance Criteria**:
- ✅ Ping to 168.63.129.16 succeeds (requires VPN connection)
- ✅ Response time < 100ms (typical for Azure VPN)
- ⚠️ If ping fails: VPN likely not connected (user error, not config error)

#### 2.2: DNS Query Response

**Test**: DNS queries reach Azure DNS
```bash
# Query any domain (should work for public DNS even without VPN)
nslookup google.com 168.63.129.16
echo "Exit code: $?"  # Expected: 0
```

**Acceptance Criteria**:
- ✅ DNS queries to 168.63.129.16 succeed
- ✅ Public DNS resolution works (fallback test)
- ✅ No timeout errors (< 5 seconds response time)

### Level 3: Private DNS Resolution Validation

Verify that private Azure resources resolve to private IP addresses.

#### 3.1: Private ACR Resolution

**Test**: ACR FQDN resolves to private IP
```bash
# Resolve ACR hostname
RESOLVED_IP=$(nslookup acraihubk2lydtz5uba3q.azurecr.io | grep -A1 "Name:" | grep "Address:" | tail -1 | awk '{print $2}')

# Check if IP is in private range (10.x.x.x)
echo "$RESOLVED_IP" | grep -q "^10\."
echo "Exit code: $?"  # Expected: 0
echo "Resolved IP: $RESOLVED_IP"  # Expected: 10.1.0.5 or similar
```

**Acceptance Criteria**:
- ✅ ACR FQDN resolves successfully
- ✅ Resolved IP is in private range (10.x.x.x)
- ✅ Resolved IP matches known private endpoint IP
- ❌ If resolves to public IP (20.x.x.x): Private DNS not working

#### 3.2: Multiple Private Resource Types

**Test**: Various private endpoints resolve correctly
```bash
# Test different privatelink zones (if available)
# ACR: privatelink.azurecr.io
nslookup acraihubk2lydtz5uba3q.azurecr.io | grep "^Address: 10\."

# Key Vault: privatelink.vaultcore.azure.net (if private endpoint exists)
# nslookup <keyvault>.vault.azure.net | grep "^Address: 10\."

# Storage: privatelink.blob.core.windows.net (if private endpoint exists)
# nslookup <storage>.blob.core.windows.net | grep "^Address: 10\."
```

**Acceptance Criteria**:
- ✅ All private endpoints resolve to private IPs
- ✅ Different privatelink zones work (azurecr.io, vaultcore.azure.net, etc.)
- ✅ Resolution is consistent across multiple queries

### Level 4: End-to-End Connectivity Validation

Verify that private resources are accessible via resolved private IPs.

#### 4.1: ACR HTTPS Connectivity

**Test**: Connect to ACR via HTTPS using private IP
```bash
# Attempt connection to ACR
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://acraihubk2lydtz5uba3q.azurecr.io/v2/)

echo "HTTP Code: $HTTP_CODE"
# Expected: 401 (authentication required) or 200 (public access)
# NOT Expected: 403 (firewall blocked) or timeout

# Test that it's NOT public IP (should fail if VPN disconnected)
if [[ "$HTTP_CODE" == "403" ]]; then
    echo "ERROR: ACR returning 403 - likely using public IP"
    exit 1
fi
```

**Acceptance Criteria**:
- ✅ HTTPS connection succeeds (no timeout)
- ✅ HTTP response code is 401 or 200 (NOT 403)
- ✅ TLS certificate validates correctly
- ✅ Connection uses private IP (verify via `curl -v` output)

#### 4.2: Azure CLI Integration

**Test**: Azure CLI can access private ACR
```bash
# Login to ACR (requires Azure VPN + proper RBAC)
az acr login --name acraihubk2lydtz5uba3q 2>&1

# Expected output contains: "Login Succeeded" or token retrieval message
# NOT expected: "403 Forbidden" or firewall errors
```

**Acceptance Criteria**:
- ✅ ACR login succeeds (or fails with auth error, not firewall error)
- ✅ Repository list command works:
  ```bash
  az acr repository list --name acraihubk2lydtz5uba3q -o table
  ```
- ✅ No 403 or firewall-related errors

### Level 5: Persistence and Restart Validation

Verify that configuration survives WSL restart.

#### 5.1: Post-Restart Configuration Check

**Test**: Configuration persists after WSL restart
```bash
# 1. Note current configuration
grep "generateResolvConf" /etc/wsl.conf > /tmp/wsl-before.txt
cat /etc/resolv.conf > /tmp/resolv-before.txt

# 2. Restart WSL (from PowerShell)
# wsl --shutdown
# (restart WSL)

# 3. Compare configuration
grep "generateResolvConf" /etc/wsl.conf > /tmp/wsl-after.txt
cat /etc/resolv.conf > /tmp/resolv-after.txt

diff /tmp/wsl-before.txt /tmp/wsl-after.txt
echo "wsl.conf changed: $?"  # Expected: 1 (no change)

diff /tmp/resolv-before.txt /tmp/resolv-after.txt
echo "resolv.conf changed: $?"  # Expected: 1 (no change)
```

**Acceptance Criteria**:
- ✅ `/etc/wsl.conf` unchanged after restart
- ✅ `/etc/resolv.conf` unchanged after restart (because generateResolvConf = false)
- ✅ Private DNS resolution still works after restart
- ✅ No manual reconfiguration needed

#### 5.2: Windows Reboot Validation

**Test**: Configuration survives Windows reboot
```bash
# 1. Note configuration before reboot
# 2. Reboot Windows
# 3. Start WSL
# 4. Verify configuration unchanged
# 5. Verify private DNS still works
```

**Acceptance Criteria**:
- ✅ Configuration persists after Windows reboot
- ✅ No manual steps required after reboot
- ✅ Private DNS resolution works immediately

## Automated Validation Script

### validate-wsl-dns.sh

A script should be provided to automate all validation checks:

```bash
#!/usr/bin/env bash
# validate-wsl-dns.sh - Automated WSL DNS Configuration Validation

CHECKS_PASSED=0
CHECKS_FAILED=0

check() {
    local name="$1"
    local command="$2"
    
    echo -n "[$name] "
    if eval "$command" &>/dev/null; then
        echo "✅ PASS"
        ((CHECKS_PASSED++))
        return 0
    else
        echo "❌ FAIL"
        ((CHECKS_FAILED++))
        return 1
    fi
}

echo "WSL DNS Configuration Validation"
echo "================================="
echo

echo "Level 1: Configuration Files"
check "wsl.conf exists" "test -f /etc/wsl.conf"
check "generateResolvConf disabled" "grep -q 'generateResolvConf = false' /etc/wsl.conf"
check "resolv.conf exists" "test -f /etc/resolv.conf"
check "Azure DNS configured" "grep -q '168.63.129.16' /etc/resolv.conf"
echo

echo "Level 2: Network Connectivity"
check "Azure DNS reachable" "ping -c 1 -W 2 168.63.129.16"
check "DNS queries work" "nslookup google.com 168.63.129.16"
echo

echo "Level 3: Private DNS Resolution"
ACR_IP=$(nslookup acraihubk2lydtz5uba3q.azurecr.io 2>/dev/null | grep -A1 "Name:" | grep "Address:" | tail -1 | awk '{print $2}')
check "ACR resolves to private IP" "[[ '$ACR_IP' =~ ^10\. ]]"
echo "  Resolved IP: $ACR_IP"
echo

echo "Level 4: Connectivity"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://acraihubk2lydtz5uba3q.azurecr.io/v2/ 2>/dev/null)
check "ACR accessible (not 403)" "[[ '$HTTP_CODE' != '403' && '$HTTP_CODE' != '000' ]]"
echo "  HTTP Code: $HTTP_CODE"
echo

echo "================================="
echo "Results: $CHECKS_PASSED passed, $CHECKS_FAILED failed"
echo

if [[ $CHECKS_FAILED -eq 0 ]]; then
    echo "✅ All validation checks passed!"
    exit 0
else
    echo "❌ Some validation checks failed. See above for details."
    echo "Troubleshooting: docs/core-infrastructure/wsl-dns-setup.md"
    exit 1
fi
```

## Success Criteria Summary

| Level | Criteria | Required | 
|-------|----------|----------|
| 1 | Configuration files created correctly | ✅ Yes |
| 2 | Azure DNS reachable | ⚠️ Warning if VPN not connected |
| 3 | Private resources resolve to private IPs | ✅ Yes |
| 4 | Private resources accessible via HTTPS | ✅ Yes |
| 5 | Configuration persists across restarts | ✅ Yes |

**Overall Success**: All "✅ Yes" criteria must pass. "⚠️ Warning" criteria can fail if VPN is not connected, but should be documented as a prerequisite for the user.

## Troubleshooting Validation Failures

| Failure | Possible Causes | Resolution |
|---------|-----------------|------------|
| Azure DNS not reachable | VPN disconnected | Connect Azure VPN, verify tunnel |
| Resolves to public IP | Private DNS zones not linked | Check VNet links in Azure Portal |
| 403 Forbidden | Using public IP | Verify DNS resolution, check VPN routing |
| resolv.conf reverts | generateResolvConf still true | Check /etc/wsl.conf, restart WSL |
| Config lost after restart | wsl.conf not saved | Re-run configure script, verify file write |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-02 | Initial validation contract |
