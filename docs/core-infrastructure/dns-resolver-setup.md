# Azure DNS Private Resolver Setup

**Feature**: 004-dns-resolver  
**Last Updated**: 2026-01-04  
**Status**: Deployed and Validated

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Validation](#validation)
- [Client Configuration](#client-configuration)
- [Troubleshooting](#troubleshooting)
- [Examples](#examples)
- [FAQ](#faq)

---

## Overview

### The Problem

Azure private endpoints enable secure, private access to Azure PaaS services (ACR, Key Vault, Storage, etc.) over private IPs within your VNet. Azure Private DNS zones map service FQDNs to these private IPs.

However, **Point-to-Site (P2S) VPN clients** face a routing gap:
- P2S clients connect to a Virtual WAN hub (172.16.0.0/24 address pool)
- The vWAN hub routes traffic to spoke VNets where private endpoints live
- **But**: Azure Private DNS zones are VNet-scoped resources. P2S clients, not being directly in a VNet, cannot query them automatically
- Result: P2S clients resolve service FQDNs to **public IPs** (e.g., `acr.azurecr.io` → `20.x.x.x`) instead of private IPs (e.g., `10.1.0.5`)

Without a solution, P2S clients (like WSL environments) must:
- Manually maintain `/etc/hosts` entries for every private endpoint
- OR: Accept using public IPs (defeating the purpose of private endpoints)

### The Solution: DNS Private Resolver

**Azure DNS Private Resolver** provides a VNet-scoped DNS service that:
1. **Bridges the gap**: Lives in a VNet, so it can query Private DNS zones
2. **Exposes an inbound endpoint** with a private IP (e.g., `10.1.0.68`) that P2S clients can reach over the VPN tunnel
3. **Answers queries** for both private zones (returns private endpoint IPs) and public domains (recursive resolution)

**Workflow**:
```
P2S Client (172.16.x.x) 
  → DNS query to 10.1.0.68 (resolver inbound endpoint)
  → Resolver (in VNet) queries Private DNS zones
  → Returns private endpoint IP (10.1.0.5)
  → Client connects to private endpoint over VPN tunnel
```

**Benefits**:
- ✅ No manual `/etc/hosts` management
- ✅ Automatic private endpoint resolution for all Azure services
- ✅ Public DNS still works (google.com, microsoft.com, etc.)
- ✅ Single configuration change (point DNS to resolver IP)

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│ Azure Subscription                                          │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ vWAN Hub (hub-ai-eastus2)                           │  │
│  │ Address Pool: 172.16.0.0/24 (P2S clients)           │  │
│  │                                                      │  │
│  │   [P2S Client: 172.16.0.10] ──────┐                 │  │
│  └────────────────────────────┬───────┘                 │  │
│                               │                         │  │
│                               │ vHub Connection         │  │
│                               ↓                         │  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Shared Services VNet (vnet-ai-shared)               │  │
│  │ Address Space: 10.1.0.0/24                          │  │
│  │                                                      │  │
│  │  ┌───────────────────────────────────────────────┐  │  │
│  │  │ DnsInboundSubnet: 10.1.0.64/27               │  │  │
│  │  │ Delegation: Microsoft.Network/dnsResolvers   │  │  │
│  │  │                                               │  │  │
│  │  │  ┌─────────────────────────────────────────┐ │  │  │
│  │  │  │ DNS Private Resolver                    │ │  │  │
│  │  │  │ Name: dnsr-ai-shared                    │ │  │  │
│  │  │  │                                         │ │  │  │
│  │  │  │  Inbound Endpoint: 10.1.0.68           │ │  │  │
│  │  │  │  (Auto-assigned from subnet)           │ │  │  │
│  │  │  └─────────────────────────────────────────┘ │  │  │
│  │  └───────────────────────────────────────────────┘  │  │
│  │                                                      │  │
│  │  Linked Private DNS Zones:                          │  │
│  │  - privatelink.azurecr.io                           │  │
│  │  - privatelink.vaultcore.azure.net                  │  │
│  │  - privatelink.blob.core.windows.net                │  │
│  │  - privatelink.database.windows.net                 │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Spoke VNet (e.g., vnet-ai-registry)                 │  │
│  │ Address Space: 10.2.0.0/24                          │  │
│  │                                                      │  │
│  │  [Private Endpoint: acr → 10.1.0.5]                 │  │
│  │  [Private Endpoint: kv → 10.1.0.6]                  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### DNS Resolution Flow

1. **P2S Client Query**: WSL client (172.16.0.10) queries `acraihubk2lydtz5uba3q.azurecr.io`
2. **Client DNS Config**: `/etc/resolv.conf` points to `nameserver 10.1.0.68` (resolver inbound endpoint)
3. **Routing**: Query routed via vHub connection to shared services VNet
4. **Resolver Processing**:
   - Resolver checks linked Private DNS zones
   - Finds `privatelink.azurecr.io` zone with A record: `acraihubk2lydtz5uba3q` → `10.1.0.5`
   - Returns private IP to client
5. **Client Connection**: Client connects to `10.1.0.5` over VPN tunnel (already routed via vHub)

**For public domains** (e.g., `google.com`):
- Resolver doesn't find a match in private zones
- Performs recursive DNS query to public DNS servers
- Returns public IP to client

### Network Details

| Component | Value |
|-----------|-------|
| **Resolver Name** | `dnsr-ai-shared` |
| **Resource Group** | `rg-ai-core` |
| **Location** | `eastus2` |
| **VNet** | `vnet-ai-shared` (10.1.0.0/24) |
| **Inbound Subnet** | `DnsInboundSubnet` (10.1.0.64/27) |
| **Inbound Endpoint IP** | `10.1.0.68` (auto-assigned) |
| **Service Delegation** | `Microsoft.Network/dnsResolvers` |

---

## Prerequisites

Before deploying the DNS Private Resolver, ensure:

1. **Core Infrastructure Deployed**:
   - Virtual WAN hub (`hub-ai-eastus2`) exists
   - Shared services VNet (`vnet-ai-shared`) exists with address space `10.1.0.0/24`
   - vHub connection to shared services VNet configured

2. **Private DNS Zones Created**:
   - `privatelink.azurecr.io` (for Azure Container Registry)
   - `privatelink.vaultcore.azure.net` (for Key Vault)
   - `privatelink.blob.core.windows.net` (for Storage)
   - Additional zones as needed

3. **Private DNS Zone Links**:
   - All private DNS zones linked to the shared services VNet (`vnet-ai-shared`)
   - Auto-registration **disabled** (resolver manages queries, not registration)

4. **Bicep Parameters**:
   - `dnsResolverName`: Name for the resolver resource (default: `dnsr-ai-shared`)
   - `dnsInboundSubnetPrefix`: Subnet CIDR for inbound endpoint (default: `10.1.0.64/27`)
   - `sharedVnetName`: Name of the shared services VNet (default: `vnet-ai-shared`)
   - `sharedVnetAddressPrefix`: Address space for shared VNet (default: `10.1.0.0/24`)

5. **Azure Subscription**:
   - Subscription must support DNS Private Resolver (check regional availability)
   - Sufficient IP addresses in inbound subnet (minimum /28, recommended /27 for future endpoints)

---

## Deployment

### Step 1: Review Parameters

The resolver is deployed as part of the core infrastructure. Review `bicep/main.parameters.example.json` to ensure resolver parameters are set:

```json
{
  "dnsResolverName": {
    "value": "dnsr-ai-shared"
  },
  "dnsInboundSubnetPrefix": {
    "value": "10.1.0.64/27"
  },
  "sharedVnetName": {
    "value": "vnet-ai-shared"
  },
  "sharedVnetAddressPrefix": {
    "value": "10.1.0.0/24"
  }
}
```

**Parameter Guidance**:
- **dnsResolverName**: Use environment suffix (`dnsr-<environment>-<region>`). Default is fine for shared core infrastructure.
- **dnsInboundSubnetPrefix**: Must be a /28 or larger within the shared VNet address space. /27 (32 IPs) recommended for future outbound endpoints or scaling.
- **sharedVnetName**: Must match the existing shared services VNet. If VNet doesn't exist, Bicep will create it.
- **sharedVnetAddressPrefix**: Must not overlap with vHub address pool (172.16.0.0/24) or spoke VNets (10.2.x.x/24, 10.3.x.x/24, etc.).

### Step 2: Deploy Core Infrastructure

Deploy (or re-deploy) the core infrastructure with resolver included:

```bash
# From repository root
cd /path/to/AI-Lab

# Deploy to Azure
az deployment sub create \
  --name dns-core-$(date +%Y%m%d-%H%M%S) \
  --location eastus2 \
  --template-file bicep/main.bicep \
  --parameters @bicep/main.parameters.example.json
```

**Deployment Time**: ~15-20 minutes (resolver creation takes 5-10 minutes)

### Step 3: Capture Resolver IP

The deployment outputs the inbound endpoint IP. Capture it for client configuration:

```bash
# Get deployment outputs
az deployment sub show \
  --name dns-core-<timestamp> \
  --query properties.outputs.dnsResolverInboundIp.value \
  --output tsv
```

**Example Output**: `10.1.0.68`

**Save this IP**: You'll configure P2S clients (WSL, jump boxes) to use this as their primary DNS server.

### Step 4: Verify Deployment

Check that the resolver and inbound endpoint were created successfully:

```bash
# Verify resolver exists
az resource show \
  --resource-group rg-ai-core \
  --resource-type Microsoft.Network/dnsResolvers \
  --name dnsr-ai-shared \
  --query "{name:name, location:location, provisioningState:properties.provisioningState}"

# Expected output:
# {
#   "name": "dnsr-ai-shared",
#   "location": "eastus2",
#   "provisioningState": "Succeeded"
# }
```

```bash
# Verify inbound endpoint
RESOLVER_ID=$(az resource show -g rg-ai-core --resource-type Microsoft.Network/dnsResolvers -n dnsr-ai-shared --query id -o tsv)

az rest \
  --method get \
  --uri "${RESOLVER_ID}/inboundEndpoints?api-version=2022-07-01" \
  --query "value[0].{name:name, ip:properties.ipConfigurations[0].privateIpAddress, state:properties.provisioningState}"

# Expected output:
# {
#   "name": "inbound-endpoint",
#   "ip": "10.1.0.68",
#   "state": "Succeeded"
# }
```

### Step 5: Verify Subnet Delegation

Ensure the inbound subnet has the correct service delegation:

```bash
az network vnet subnet show \
  --resource-group rg-ai-core \
  --vnet-name vnet-ai-shared \
  --name DnsInboundSubnet \
  --query "{name:name, addressPrefix:addressPrefix, delegation:delegations[0].serviceName, state:provisioningState}"

# Expected output:
# {
#   "name": "DnsInboundSubnet",
#   "addressPrefix": "10.1.0.64/27",
#   "delegation": "Microsoft.Network/dnsResolvers",
#   "state": "Succeeded"
# }
```

**Troubleshooting**: If `provisioningState` is `Failed`, check:
- Subnet CIDR doesn't overlap with existing subnets
- Subnet is within shared VNet address space
- No other resources exist in the subnet (must be dedicated to resolver)

### Idempotency and Re-Deployment

The Bicep template is **idempotent**. You can safely re-run the deployment:

```bash
# Re-deploy with same parameters
az deployment sub create \
  --name dns-core-redeploy-$(date +%Y%m%d-%H%M%S) \
  --location eastus2 \
  --template-file bicep/main.bicep \
  --parameters @bicep/main.parameters.example.json
```

**Expected behavior**:
- Existing resolver: No changes, deployment succeeds quickly
- Existing inbound endpoint: IP address **may change** if endpoint was deleted/recreated
- New configuration: Resolver updated to match parameters

**Best Practice**: Always capture the inbound endpoint IP after deployment and update client configurations if it changes.

---

## Validation

After deployment, validate that the resolver is functioning correctly.

### Automated Validation Script

Use the provided validation script:

```bash
# From repository root
./scripts/test-dns-resolver.sh --ip 10.1.0.68
```

**Expected Output**:
```
DNS Private Resolver Validation
================================

Configuration
  Resolver IP: 10.1.0.68
  Azure Region: eastus2

Level 1: Resolver Resource Check
  ✅ PASS - Resolver 'dnsr-ai-shared' exists
  ✅ PASS - Provisioning state: Succeeded

Level 2: Inbound Endpoint Check
  ✅ PASS - Inbound endpoint exists
  ✅ PASS - Endpoint IP: 10.1.0.68

Level 3: Private DNS Zone Resolution
  ✅ PASS - ACR resolves to private IP: 10.1.0.5
  ✅ PASS - Key Vault resolves to private IP: 10.1.0.x
  ✅ PASS - Storage resolves to private IP: 10.1.0.x

Level 4: Public DNS Resolution
  ✅ PASS - google.com resolves (public DNS fallback works)
  ✅ PASS - microsoft.com resolves

Level 5: Connectivity Validation
  ⚠️ WARN - HTTPS to ACR requires client DNS configuration

Summary: 5/5 validation levels passed
```

### Manual Validation Steps

#### Test 1: Private DNS Resolution

Query a private endpoint FQDN using the resolver IP:

```bash
nslookup acraihubk2lydtz5uba3q.azurecr.io 10.1.0.68
```

**Expected Output**:
```
Server:		10.1.0.68
Address:	10.1.0.68#53

Non-authoritative answer:
acraihubk2lydtz5uba3q.azurecr.io	canonical name = acraihubk2lydtz5uba3q.privatelink.azurecr.io.
Name:	acraihubk2lydtz5uba3q.privatelink.azurecr.io
Address: 10.1.0.5
```

✅ **Validation**: IP should be `10.1.0.5` (or your ACR's private endpoint IP), **not** `20.x.x.x` (public IP)

#### Test 2: Public DNS Fallback

Query a public domain to ensure recursive resolution works:

```bash
nslookup google.com 10.1.0.68
```

**Expected Output**:
```
Server:		10.1.0.68
Address:	10.1.0.68#53

Non-authoritative answer:
Name:	google.com
Address: 172.217.x.x
```

✅ **Validation**: Resolver returns public IPs for public domains

#### Test 3: HTTPS Connectivity (from WSL)

After configuring WSL to use the resolver IP (see [Client Configuration](#client-configuration)):

```bash
# Test ACR connectivity
curl -v https://acraihubk2lydtz5uba3q.azurecr.io/v2/
```

**Expected Output**:
```
* Connected to acraihubk2lydtz5uba3q.azurecr.io (10.1.0.5) port 443
...
< HTTP/1.1 401 Unauthorized
```

✅ **Validation**: 
- Connection to **private IP** `10.1.0.5` (not public `20.x.x.x`)
- HTTP 401 is expected (ACR requires authentication)
- HTTP 403 or timeout indicates routing issue

### Performance Validation

Measure DNS response time:

```bash
time nslookup acraihubk2lydtz5uba3q.azurecr.io 10.1.0.68
```

**Expected**: `< 0.100s` (100ms)

**Benchmark**: Resolver typically responds in 20-50ms for private zones, 50-100ms for public DNS queries.

---

## Client Configuration

### WSL (Windows Subsystem for Linux)

**See**: [specs/003-wsl-dns-config/quickstart.md](../../specs/003-wsl-dns-config/quickstart.md) for detailed WSL configuration steps.

**Quick Setup**:

1. **Connect to P2S VPN** (WSL must have VPN connectivity to reach resolver IP)

2. **Configure DNS**:
   ```bash
   # Set resolver IP as primary DNS
   sudo bash -c 'echo "nameserver 10.1.0.68" > /etc/resolv.conf'
   sudo bash -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'  # Fallback
   ```

3. **Disable Auto-Generation**:
   ```bash
   # Prevent WSL from overwriting resolv.conf
   sudo tee /etc/wsl.conf > /dev/null <<EOF
   [network]
   generateResolvConf = false
   EOF
   ```

4. **Restart WSL**:
   ```powershell
   # From PowerShell
   wsl --shutdown
   wsl
   ```

5. **Test**:
   ```bash
   nslookup acraihubk2lydtz5uba3q.azurecr.io
   # Should return 10.1.0.5
   ```

### Jump Box (Azure VM in Shared VNet)

VMs in the shared services VNet automatically use Azure DNS (168.63.129.16), which queries linked private DNS zones. **No configuration needed** for VMs in the VNet.

To explicitly use the resolver:

```bash
# Edit /etc/resolv.conf
sudo bash -c 'echo "nameserver 10.1.0.68" > /etc/resolv.conf'
```

### Other P2S Clients

Any P2S client can use the resolver by setting DNS to `10.1.0.68`:

- **macOS**: System Preferences → Network → VPN → Advanced → DNS → Add `10.1.0.68`
- **Linux**: Edit `/etc/resolv.conf` or NetworkManager connection settings
- **Windows**: Network Adapter Settings → VPN Properties → DNS Servers → Add `10.1.0.68`

---

## Troubleshooting

### Issue 1: Resolver Not Found

**Symptom**: `az resource show` returns "ResourceNotFound"

**Causes**:
- Deployment failed or didn't include resolver module
- Wrong resource group or resolver name

**Solutions**:
1. Check deployment status:
   ```bash
   az deployment sub list --query "[?name contains(@, 'dns-core')].{name:name, state:properties.provisioningState}" -o table
   ```
2. Verify parameters file includes `dnsResolverName`, `dnsInboundSubnetPrefix`
3. Re-deploy core infrastructure

---

### Issue 2: Private DNS Queries Timeout

**Symptom**: `nslookup acraihubk2lydtz5uba3q.azurecr.io 10.1.0.68` times out

**Causes**:
- Resolver IP unreachable (routing issue)
- P2S client not connected to VPN
- vHub connection to shared VNet misconfigured

**Solutions**:
1. **Verify VPN connection**:
   ```bash
   # From P2S client (WSL)
   ping 10.1.0.68
   # Should succeed if routing is correct
   ```
2. **Check vHub connection**:
   ```bash
   az network vhub connection show \
     --resource-group rg-ai-core \
     --vhub-name hub-ai-eastus2 \
     --name conn-shared-services \
     --query "{name:name, state:provisioningState, remoteVnetId:remoteVirtualNetwork.id}"
   ```
   - `provisioningState` should be `Succeeded`
   - `remoteVnetId` should point to `vnet-ai-shared`

3. **Check Network Security Groups**: Ensure no NSG blocks UDP port 53 to `10.1.0.64/27`

---

### Issue 3: Queries Return Public IP Instead of Private

**Symptom**: `nslookup acraihubk2lydtz5uba3q.azurecr.io 10.1.0.68` returns `20.x.x.x` (public IP)

**Causes**:
- Private DNS zone not linked to shared VNet
- Private endpoint not created for the service
- DNS zone name incorrect (e.g., missing `privatelink` subdomain)

**Solutions**:
1. **Verify Private DNS Zone Link**:
   ```bash
   az network private-dns link vnet list \
     --resource-group rg-ai-core \
     --zone-name privatelink.azurecr.io \
     --query "[?virtualNetwork.id contains(@, 'vnet-ai-shared')].{name:name, state:provisioningState}"
   ```
   - Should show link to `vnet-ai-shared` with state `Succeeded`

2. **Verify Private Endpoint**:
   ```bash
   az network private-endpoint list \
     --resource-group rg-ai-registry \
     --query "[?contains(privateLinkServiceConnections[0].privateLinkServiceId, 'containerregistry')].{name:name, ip:customDnsConfigs[0].ipAddresses[0]}"
   ```
   - Should show ACR private endpoint with IP `10.1.0.5`

3. **Create missing link** (if needed):
   ```bash
   az network private-dns link vnet create \
     --resource-group rg-ai-core \
     --zone-name privatelink.azurecr.io \
     --name link-shared-vnet \
     --virtual-network vnet-ai-shared \
     --registration-enabled false
   ```

---

### Issue 4: Public DNS Queries Fail

**Symptom**: `nslookup google.com 10.1.0.68` times out or returns SERVFAIL

**Causes**:
- Resolver cannot reach public DNS servers (outbound routing issue)
- Azure DNS resolution service unavailable (rare)

**Solutions**:
1. **Check outbound connectivity** from shared VNet:
   - VNet should have default route to Internet (system route or custom route table)
   - No NSG blocking outbound UDP/53 or TCP/53

2. **Test from resolver subnet**:
   - Deploy a test VM in the shared VNet
   - Query public DNS: `nslookup google.com 8.8.8.8`
   - If this fails, it's a VNet routing issue, not a resolver issue

3. **Verify resolver configuration**:
   ```bash
   az rest \
     --method get \
     --uri "/subscriptions/<subId>/resourceGroups/rg-ai-core/providers/Microsoft.Network/dnsResolvers/dnsr-ai-shared?api-version=2022-07-01" \
     --query "{state:properties.provisioningState, vnet:properties.virtualNetwork.id}"
   ```

---

### Issue 5: Resolver IP Changes After Re-Deployment

**Symptom**: After re-deploying core infrastructure, `dnsResolverInboundIp` output shows a different IP

**Causes**:
- Inbound endpoint was deleted and recreated (new IP allocated)
- Subnet CIDR changed (forces subnet recreation)

**Impact**: P2S clients configured with old IP will fail DNS queries

**Solutions**:
1. **Prevent unnecessary recreation**:
   - Don't change `dnsInboundSubnetPrefix` unless necessary
   - Don't delete resources manually (use Bicep for all changes)

2. **Update client configurations**:
   - After deployment, capture new IP: `az deployment sub show --name <name> --query properties.outputs.dnsResolverInboundIp.value`
   - Update all P2S client DNS settings with new IP
   - Update WSL templates and documentation

3. **Consider static IP** (future enhancement):
   - Modify Bicep to specify `privateIpAddress` for inbound endpoint (requires `privateIpAllocationMethod: Static`)
   - Guarantees IP stability across re-deployments

---

## Examples

### Example 1: Accessing ACR from WSL

**Scenario**: Pull a Docker image from private ACR using private endpoint

**Prerequisites**:
- ACR private endpoint deployed (`10.1.0.5`)
- WSL configured to use resolver IP (`nameserver 10.1.0.68`)
- P2S VPN connected

**Steps**:

1. **Verify DNS resolution**:
   ```bash
   nslookup acraihubk2lydtz5uba3q.azurecr.io
   # Returns: 10.1.0.5
   ```

2. **Authenticate to ACR**:
   ```bash
   az acr login --name acraihubk2lydtz5uba3q
   # Uses resolved private IP for authentication
   ```

3. **Pull image**:
   ```bash
   docker pull acraihubk2lydtz5uba3q.azurecr.io/myapp:latest
   # Downloads via private endpoint (10.1.0.5) over VPN
   ```

**Validation**: Monitor network traffic; should connect to `10.1.0.5`, not public IP

---

### Example 2: Accessing Key Vault from WSL

**Scenario**: Retrieve secrets from Key Vault using private endpoint

**Prerequisites**:
- Key Vault private endpoint deployed
- WSL configured with resolver IP

**Steps**:

1. **Verify DNS resolution**:
   ```bash
   nslookup kv-ai-shared.vault.azure.net
   # Returns: 10.1.0.x (private endpoint IP)
   ```

2. **Get secret**:
   ```bash
   az keyvault secret show \
     --vault-name kv-ai-shared \
     --name database-connection-string
   # Connects via private endpoint
   ```

**Benefit**: No exposure of secrets over public internet; all traffic over VPN tunnel

---

### Example 3: Accessing Storage Account from WSL

**Scenario**: Upload files to Blob Storage via private endpoint

**Prerequisites**:
- Storage account private endpoint deployed
- WSL configured with resolver IP

**Steps**:

1. **Verify DNS resolution**:
   ```bash
   nslookup staihubk2lydtz5uba3q.blob.core.windows.net
   # Returns: 10.1.0.x (blob private endpoint IP)
   ```

2. **Upload file**:
   ```bash
   az storage blob upload \
     --account-name staihubk2lydtz5uba3q \
     --container-name data \
     --name myfile.txt \
     --file ./myfile.txt \
     --auth-mode login
   # Uploads via private endpoint
   ```

**Network Flow**: WSL → VPN → vHub → Shared VNet → Resolver (10.1.0.68) → Private endpoint (10.1.0.x)

---

### Example 4: App Service with Private Endpoint

**Scenario**: Access a web app deployed with private endpoint

**Prerequisites**:
- App Service private endpoint deployed
- Private DNS zone `privatelink.azurewebsites.net` linked to shared VNet

**Steps**:

1. **Verify DNS resolution**:
   ```bash
   nslookup myapp.azurewebsites.net
   # Returns: 10.1.0.x (app service private endpoint IP)
   ```

2. **Access web app**:
   ```bash
   curl https://myapp.azurewebsites.net
   # Connects via private endpoint over VPN
   ```

**Use Case**: Internal web apps accessible only via VPN, not public internet

---

## FAQ

### Do I need to change my DNS if the resolver is deployed?

**Answer**: It depends on your network location.

- **P2S VPN clients** (WSL, laptops): **Yes**, you must configure DNS to use the resolver IP (`10.1.0.68`). Without this, you'll resolve service FQDNs to public IPs.
  
- **VMs in shared services VNet**: **No**, VMs automatically use Azure DNS (168.63.129.16), which queries linked private DNS zones. Resolver is optional for these VMs.

- **VMs in spoke VNets**: **No**, spoke VNets peered (or connected via vHub) to shared VNet can query private DNS zones automatically via Azure DNS. Resolver is not required unless you want centralized DNS auditing.

**Recommendation**: Configure P2S clients to use the resolver. Leave VNet-based VMs with default Azure DNS.

---

### What happens if the resolver goes down?

**Answer**: 
- **Private DNS queries** from P2S clients will fail (timeouts or NXDOMAIN)
- **Public DNS queries** depend on fallback DNS configuration:
  - If clients have a fallback DNS (e.g., `8.8.8.8`), public queries will work
  - If resolver is the only DNS server, all queries fail

**Mitigation**:
- Always configure a fallback public DNS server (e.g., `8.8.8.8` or `1.1.1.1`) in client DNS settings
- For high availability, deploy a second resolver in a different VNet/region (future enhancement)

---

### Can I use the resolver for conditional forwarding?

**Answer**: Not directly. Azure DNS Private Resolver supports **inbound** and **outbound** endpoints:
- **Inbound** (what we deployed): Allows external clients (P2S) to query Private DNS zones
- **Outbound** (future enhancement): Allows Private DNS queries to be forwarded to external DNS servers (e.g., on-premises DNS)

**Use Case**: If you need to query on-premises DNS from Azure, deploy an **outbound endpoint** and configure forwarding rules. See [Azure DNS Private Resolver documentation](https://learn.microsoft.com/azure/dns/dns-private-resolver-overview) for outbound endpoint setup.

---

### How much does the resolver cost?

**Answer**: Pricing (as of 2026):
- **Resolver**: ~$0.20/hour (~$146/month)
- **Inbound Endpoint**: ~$0.05/hour (~$36/month)
- **Query Volume**: First 1 billion queries/month free, then $0.40 per million queries

**Total**: ~$182/month for the resolver + inbound endpoint (assuming < 1B queries/month)

**Cost Optimization**: Resolver cost is per-region. If you have multiple VNets in the same region, link them all to one shared resolver to avoid duplicate costs.

---

### Can I deploy the resolver in a spoke VNet instead of the shared VNet?

**Answer**: Yes, but **not recommended** for core infrastructure.

**Rationale**:
- **Shared services VNet** is the central hub for cross-cutting services (DNS, monitoring, logging)
- Deploying in a spoke VNet:
  - Requires vHub connection from that spoke (increases routing complexity)
  - Limits reusability (other spokes can't easily use the resolver)
  - Violates hub-spoke architecture (spokes should be workload-specific)

**Exception**: If you have a dedicated "platform services" spoke VNet, that's acceptable. Ensure it's peered/connected to all VNets needing DNS resolution.

---

### How do I add support for a new private endpoint service?

**Answer**: Two steps:

1. **Create Private DNS Zone** (if not already exists):
   ```bash
   az network private-dns zone create \
     --resource-group rg-ai-core \
     --name privatelink.<service>.azure.net
   ```
   - Example zones:
     - `privatelink.azurecr.io` (ACR)
     - `privatelink.vaultcore.azure.net` (Key Vault)
     - `privatelink.blob.core.windows.net` (Blob Storage)
     - `privatelink.database.windows.net` (SQL)
     - `privatelink.azurewebsites.net` (App Service)

2. **Link Zone to Shared VNet**:
   ```bash
   az network private-dns link vnet create \
     --resource-group rg-ai-core \
     --zone-name privatelink.<service>.azure.net \
     --name link-shared-vnet \
     --virtual-network vnet-ai-shared \
     --registration-enabled false
   ```

**Resolver automatically queries new zones**: No resolver configuration changes needed. Once the zone is linked to the VNet, the resolver will query it for matching FQDNs.

---

### Can I see DNS query logs?

**Answer**: Yes, using **Azure Monitor** and **Diagnostic Settings**.

**Setup**:
1. Enable diagnostic logs for the DNS resolver:
   ```bash
   az monitor diagnostic-settings create \
     --resource <resolver-resource-id> \
     --name dns-logs \
     --logs '[{"category": "DnsQueryLogs", "enabled": true}]' \
     --workspace <log-analytics-workspace-id>
   ```

2. Query logs in Log Analytics:
   ```kql
   DnsQueryLogs
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, ClientIP, QueryName, QueryType, ResponseCode, ResponseIP
   | order by TimeGenerated desc
   ```

**Use Cases**:
- Troubleshooting DNS resolution issues
- Auditing which clients query which resources
- Performance analysis (query response times)

---

## Additional Resources

- [Azure DNS Private Resolver Overview](https://learn.microsoft.com/azure/dns/dns-private-resolver-overview)
- [Azure Private Endpoint DNS Configuration](https://learn.microsoft.com/azure/private-link/private-endpoint-dns)
- [WSL DNS Configuration (Feature 003)](../../specs/003-wsl-dns-config/quickstart.md)
- [Core Infrastructure Troubleshooting](./troubleshooting.md)
- [Validation Script Source](../../scripts/test-dns-resolver.sh)

---

**Last Updated**: 2026-01-04  
**Maintained By**: Platform Engineering Team  
**Feedback**: Submit issues or suggestions via GitHub
