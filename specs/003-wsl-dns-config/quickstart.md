# Quickstart: Configure WSL DNS for Azure Private DNS

**Purpose**: Step-by-step guide to configure Windows Subsystem for Linux (WSL) to use Azure private DNS for accessing private Azure resources via VPN.

**Time Required**: 5-10 minutes  
**Difficulty**: Beginner  
**Prerequisites**: WSL2 installed, Azure VPN connected, sudo access

## Overview

This guide configures WSL to resolve Azure private DNS zones (e.g., `privatelink.azurecr.io`) correctly when connected via Azure VPN. After configuration, private Azure resources (ACR, Key Vault, Storage) will be accessible from WSL without manual `/etc/hosts` entries.

## Prerequisites

### Required Infrastructure

- ✅ **DNS Private Resolver deployed** (from 004-dns-resolver) - **REQUIRED**
- ✅ Azure VPN Client installed on Windows
- ✅ VPN connected to Azure virtual hub (from 001-vwan-core deployment)
- ✅ Private Azure resources deployed (e.g., ACR from 002-private-acr)
- ✅ WSL2 distribution installed (Ubuntu 20.04+ recommended)

**Note**: The DNS Private Resolver (feature 004) must be deployed before configuring WSL. Get the resolver IP:
```bash
az deployment group show -n dns-resolver-deploy-* -g rg-ai-core \
  --query 'properties.outputs.inboundEndpointIp.value' -o tsv
```
Expected output: `10.1.0.68` (or similar 10.1.0.x address)

### Required Access

- ✅ Sudo privileges in WSL
- ✅ Azure VPN access credentials
- ✅ RBAC permissions on private Azure resources (for testing)

### Verify Prerequisites

```bash
# 1. Check WSL version
wsl --list --verbose
# Expected: VERSION should be 2

# 2. Inside WSL, check sudo access
sudo -v
# Expected: Password prompt or "password cached"

# 3. Check Azure CLI installed (optional, for testing)
az version
# Expected: Azure CLI version information
```

## Step 1: Connect Azure VPN

Before configuring WSL, ensure Azure VPN is connected:

**Windows (PowerShell or Settings)**:
1. Open Azure VPN Client
2. Select your VPN connection (e.g., `vpngw-ai-hub`)
3. Click "Connect"
4. Verify connection status shows "Connected"

**Verify VPN from WSL**:
```bash
# Check if DNS Private Resolver is reachable
ping -c 1 10.1.0.68
```

**Expected**: Ping succeeds with response time < 50ms  
**If fails**: VPN not connected or resolver not deployed (run feature 004 first)

## Step 2: Download Configuration Script

```bash
# Navigate to AI-Lab repository
cd ~/AI-Lab

# Ensure on correct branch (or use main if merged)
git checkout 003-wsl-dns-config

# Verify script exists
ls -l scripts/configure-wsl-dns.sh
```

**Expected**: Script file exists and is executable

**If file doesn't exist**: Clone repository or create script manually (see Manual Configuration section below)

## Step 3: Run Configuration Script

```bash
# Make script executable (if not already)
chmod +x scripts/configure-wsl-dns.sh

# Run the configuration script
sudo ./scripts/configure-wsl-dns.sh
```

**Script Output**:
```
Configuring WSL DNS for Azure Private DNS Zones
================================================

[INFO] Checking prerequisites...
[OK] Sudo access available
[OK] Required utilities present

[INFO] Checking current configuration...
[INFO] Configuration not present, proceeding with setup

[INFO] Backing up existing configuration...
[OK] Backed up /etc/wsl.conf to /etc/wsl.conf.backup.20260102-153045
[OK] Backed up /etc/resolv.conf to /etc/resolv.conf.backup.20260102-153045

[INFO] Configuring /etc/wsl.conf...
[OK] WSL.conf configured (generateResolvConf = false)

[INFO] Configuring /etc/resolv.conf...
[OK] Resolv.conf configured (nameserver 10.1.0.68)

[INFO] Verifying DNS resolver reachability...
[OK] DNS Private Resolver (10.1.0.68) is reachable

[SUCCESS] WSL DNS configuration complete!
```

**If script fails**: See Troubleshooting section below

## Step 4: Restart WSL

Configuration changes require WSL to be restarted.

**From Windows PowerShell (as Administrator)**:
```powershell
# Shutdown all WSL distributions
wsl --shutdown
```

**Wait 5-10 seconds**, then restart your WSL distribution:
```powershell
# Start your distribution (e.g., Ubuntu)
wsl
```

**Alternative (from Start Menu)**:
1. Close all WSL terminals
2. Open PowerShell as Administrator
3. Run `wsl --shutdown`
4. Re-open your WSL distribution from Start Menu

## Step 5: Verify DNS Configuration

### 5.1: Check Configuration Files

```bash
# Verify wsl.conf
cat /etc/wsl.conf
```

**Expected Output**:
```ini
[network]
generateResolvConf = false
```

```bash
# Verify resolv.conf
cat /etc/resolv.conf
```

**Expected Output**:
```
nameserver 10.1.0.68
nameserver 8.8.8.8
search <azure-internal-domain>
```

### 5.2: Test Private DNS Resolution

```bash
# Test ACR resolution
nslookup acraihubk2lydtz5uba3q.azurecr.io
```

**Expected Output**:
```
Server:         10.1.0.68
Address:        10.1.0.68#53

Non-authoritative answer:
Name:   acraihubk2lydtz5uba3q.azurecr.io
Address: 10.1.0.5
```

**Key Check**: Address should be `10.x.x.x` (private IP), **NOT** `20.x.x.x` (public IP)

### 5.3: Test ACR Connectivity

```bash
# Test HTTPS connection to ACR
curl -v https://acraihubk2lydtz5uba3q.azurecr.io/v2/ 2>&1 | grep -E "Connected to|HTTP"
```

**Expected Output**:
```
* Connected to acraihubk2lydtz5uba3q.azurecr.io (10.1.0.5) port 443
< HTTP/1.1 401 Unauthorized
```

**Key Checks**:
- ✅ Connected to private IP (`10.1.0.5`)
- ✅ HTTP response `401` (authentication required) or `200` (OK)
- ❌ **NOT** `403` (Forbidden - indicates public IP/firewall block)

### 5.4: Test Azure CLI Integration

```bash
# List ACR repositories
az acr repository list --name acraihubk2lydtz5uba3q -o table
```

**Expected**: Repository list appears (or authentication error, but not firewall error)

**If fails with 403**: DNS still resolving to public IP; re-check steps above

## Step 6: Test Other Private Resources

If you have other private endpoints deployed:

```bash
# Test Key Vault (if private endpoint exists)
# nslookup <keyvault-name>.vault.azure.net

# Test Storage Account (if private endpoint exists)
# nslookup <storage-account>.blob.core.windows.net
```

**Expected**: All resolve to `10.x.x.x` private IPs

## Manual Configuration (Alternative)

If you prefer manual configuration or don't have the script:

### Step 1: Create /etc/wsl.conf

```bash
# Create or edit wsl.conf
# Backup existing file if present
if [ -f /etc/wsl.conf ]; then
  sudo cp /etc/wsl.conf /etc/wsl.conf.backup.$(date +%Y%m%d-%H%M%S)
fi

sudo nano /etc/wsl.conf
```

Add this content:
```ini
[network]
generateResolvConf = false
```

Save and exit (Ctrl+X, Y, Enter)

### Step 2: Create /etc/resolv.conf

```bash
# Backup existing resolv.conf
if [ -f /etc/resolv.conf ]; then
  sudo cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d-%H%M%S)
fi

# Create new resolv.conf
sudo nano /etc/resolv.conf
```

Add this content (replace search domain with yours if different):
```
nameserver 168.63.129.16
nameserver 8.8.8.8
search x5ksal5ehxruph3istx2szuwhf.ux.internal.cloudapp.net
```
> The search domain follows Azure's internal DNS suffix format: `<random>.ux.internal.cloudapp.net` provided by your VPN; keep the exact value from your environment for short-name resolution.

Save and exit (Ctrl+X, Y, Enter)

### Step 3: Restart WSL

From PowerShell:
```powershell
wsl --shutdown
```

Then restart your WSL distribution.

**Manual verification commands (run inside WSL):**
- `nslookup acraihubk2lydtz5uba3q.azurecr.io` (expect 10.x.x.x)
- `curl -v https://acraihubk2lydtz5uba3q.azurecr.io/v2/ 2>&1 | grep -E "Connected to|HTTP"` (expect private IP + 401/200, not 403)

## Validation

Run automated validation script:

```bash
./scripts/validate-wsl-dns.sh
```

**Expected Output**:
```
WSL DNS Configuration Validation
=================================

Level 1: Configuration Files
[wsl.conf exists] ✅ PASS
[generateResolvConf disabled] ✅ PASS
[resolv.conf exists] ✅ PASS
[Azure DNS configured] ✅ PASS

Level 2: Network Connectivity
[Azure DNS reachable] ✅ PASS
[DNS queries work] ✅ PASS

Level 3: Private DNS Resolution
[ACR resolves to private IP] ✅ PASS
  Resolved IP: 10.1.0.5

Level 4: Connectivity
[ACR accessible (not 403)] ✅ PASS
  HTTP Code: 401

=================================
Results: 8 passed, 0 failed

✅ All validation checks passed!
```

## Troubleshooting

### Issue 1: DNS Resolver Not Reachable

**Symptom**: `ping 10.1.0.68` fails

**Causes**:
- VPN not connected
- DNS Private Resolver not deployed (feature 004)
- VPN routing not configured correctly

**Solution**:
```bash
# 1. Verify DNS resolver is deployed
az resource show -g rg-ai-core --resource-type Microsoft.Network/dnsResolvers -n dnsr-ai-shared

# 2. Disconnect and reconnect Azure VPN (from Windows)
# 3. Verify VPN status in Azure VPN Client
# 4. Check VPN routing from WSL:
ip route | grep 10.1.0.0

# 4. If still failing, check VPN gateway configuration in Azure Portal
```

### Issue 2: Resolves to Public IP

**Symptom**: `nslookup acr*.azurecr.io` returns `20.x.x.x` IP

**Causes**:
- WSL.conf not applied (WSL not restarted)
- resolv.conf being auto-generated

**Solution**:
```bash
# 1. Verify wsl.conf setting
grep "generateResolvConf" /etc/wsl.conf
# Must show: generateResolvConf = false

# 2. Restart WSL (from PowerShell)
wsl --shutdown

# 3. Restart WSL and re-check DNS
nslookup acr*.azurecr.io

# 4. If still fails, manually verify resolv.conf
cat /etc/resolv.conf
# First nameserver MUST be 10.1.0.68
```

### Issue 3: 403 Forbidden Errors

**Symptom**: `curl https://acr*.azurecr.io/v2/` returns `403`

**Causes**:
- Still using public IP (DNS not working)
- Firewall blocking public IP access

**Solution**:
```bash
# 1. Verify DNS resolution
nslookup acraihubk2lydtz5uba3q.azurecr.io | grep "Address: 10."
# MUST resolve to 10.x.x.x

# 2. If resolving correctly but still 403, check ACR networking
az acr show --name acraihubk2lydtz5uba3q \
  --query "{publicNetwork:publicNetworkAccess,privateEndpoint:privateEndpointConnections[0].privateLinkServiceConnectionState.status}" \
  -o table

# 3. Verify private endpoint exists
az network private-endpoint list \
  --resource-group rg-ai-acr \
  --query "[].{name:name,state:provisioningState}" \
  -o table
```

### Issue 4: Configuration Reverts After Restart

**Symptom**: resolv.conf changes back to auto-generated content after WSL restart

**Cause**: `generateResolvConf = false` not set or not taking effect

**Solution**:
```bash
# 1. Verify wsl.conf exists and has correct content
sudo cat /etc/wsl.conf

# 2. Ensure file is in /etc/ (not /mnt/etc/ or other location)
# 3. Check file permissions
ls -l /etc/wsl.conf
# Should be readable: -rw-r--r--

# 4. Completely shutdown and restart WSL
# From PowerShell:
wsl --shutdown
# Wait 30 seconds
wsl

# 5. Check if resolv.conf persists
cat /etc/resolv.conf
```

### Issue 5: Permission Denied

**Symptom**: Script fails with "Permission denied"

**Cause**: Not running with sudo

**Solution**:
```bash
# Always run with sudo
sudo ./scripts/configure-wsl-dns.sh

# Or make files writable (not recommended)
# Better to use sudo
```

## Rollback

If you need to revert to original configuration:

```bash
# Find latest backup
ls -lt /etc/wsl.conf.backup.* | head -1
ls -lt /etc/resolv.conf.backup.* | head -1

# Restore from backup (replace timestamp)
sudo cp /etc/wsl.conf.backup.20260102-153045 /etc/wsl.conf
sudo cp /etc/resolv.conf.backup.20260102-153045 /etc/resolv.conf

# Restart WSL (from PowerShell)
wsl --shutdown
```

## Next Steps

Once WSL DNS is configured:

1. **Deploy Private Resources**: All private endpoints will automatically resolve
2. **Access ACR**: `az acr login`, `docker pull`, `az acr import` all work via private IP
3. **Access Key Vault**: `az keyvault secret show` works if Key Vault has private endpoint
4. **Team Onboarding**: Share this quickstart with team members for their WSL setup

## Reference

- **Full Documentation**: [docs/core-infrastructure/wsl-dns-setup.md](../../docs/core-infrastructure/wsl-dns-setup.md)
- **Troubleshooting Guide**: [docs/core-infrastructure/troubleshooting.md](../../docs/core-infrastructure/troubleshooting.md)
- **Script Contract**: [contracts/script-contract.md](contracts/script-contract.md)
- **Validation Contract**: [contracts/validation-contract.md](contracts/validation-contract.md)
- **Feature Spec**: [spec.md](spec.md)

## FAQ

**Q: Do I need to reconnect VPN after WSL restart?**  
A: No, VPN connection is at Windows level and persists.

**Q: Will this affect my non-Azure DNS queries?**  
A: No, the DNS Private Resolver (10.1.0.68) handles public DNS queries normally via fallback. Fallback DNS (8.8.8.8) provides redundancy when VPN disconnects.

**Q: What happens if I disconnect VPN?**  
A: Private DNS resolution will fail, but public DNS still works via fallback server. No configuration changes needed.

**Q: Can I use this with WSL1?**  
A: Yes, configuration should work, but WSL2 is recommended for better network compatibility.

**Q: Do I need to reconfigure after Windows updates?**  
A: Usually no, configuration persists. If resolv.conf reverts, verify wsl.conf still has `generateResolvConf = false`.

**Q: Can I add additional DNS servers?**  
A: Yes, edit `/etc/resolv.conf` and add more `nameserver` lines (max 3 total).
