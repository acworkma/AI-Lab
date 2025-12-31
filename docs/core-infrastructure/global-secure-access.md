# Microsoft Entra Global Secure Access Integration

## Overview

This guide explains how to integrate the Azure Virtual WAN hub with **Microsoft Entra Global Secure Access** to enable Security Service Edge (SSE) capabilities for your AI lab infrastructure.

**Global Secure Access** provides:
- **Private Access**: Secure access to private Azure resources and on-premises applications
- **Internet Access**: Web content filtering, threat protection, and secure web gateway
- **Microsoft 365 Access**: Optimized connectivity to Microsoft 365 services with conditional access

## Prerequisites

### Azure Infrastructure (Completed)

✅ Core infrastructure deployed (see [README.md](README.md)):
- Virtual WAN hub (hub-ai-eastus2)
- **Site-to-site VPN Gateway** with BGP enabled (vpngw-ai-hub)
- VPN Gateway BGP peering address and ASN from deployment outputs

### Microsoft Entra Requirements

- **Microsoft Entra ID P1 or P2** license (required for Global Secure Access)
- **Global Administrator** or **Security Administrator** role in Microsoft Entra
- **Global Secure Access license** for each user requiring SSE capabilities

### Required Information from Deployment

From `deploy-core.sh` output, you will need:

```
VPN Gateway: vpngw-ai-hub
  - BGP ASN: 65515
  - BGP Peering Address: 10.0.0.x  (SAVE THIS VALUE)
```

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                Microsoft Entra Global Secure Access            │
│                                                                 │
│  ┌───────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ Private Access│  │Internet      │  │ M365 Access        │  │
│  │ - Azure VMs   │  │Access        │  │ - SharePoint       │  │
│  │ - On-prem     │  │ - Web Filter │  │ - Exchange Online  │  │
│  └───────────────┘  └──────────────┘  └────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  VPN Site Configuration                                  │  │
│  │  - Name: Azure-AI-Lab-Hub                                │  │
│  │  - Connection Type: Site-to-Site                         │  │
│  │  │  - Remote BGP ASN: 65515 (from Azure VPN Gateway)     │  │
│  │  - Remote BGP Address: 10.0.0.x (from deployment)        │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                   Site-to-Site VPN
                    with BGP Enabled
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│              Azure Virtual WAN Hub (hub-ai-eastus2)             │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  VPN Gateway (vpngw-ai-hub)                            │    │
│  │  - Type: Site-to-Site                                  │    │
│  │  - BGP Enabled: Yes                                    │    │
│  │  - Local BGP ASN: 65515                                │    │
│  │  - BGP Peering Address: 10.0.0.x                       │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Configuration Steps

### Step 1: Access Microsoft Entra Admin Center

1. Navigate to [Microsoft Entra Admin Center](https://entra.microsoft.com)
2. Sign in with Global Administrator or Security Administrator account
3. Ensure you have Global Secure Access licenses activated

### Step 2: Enable Global Secure Access

1. In Microsoft Entra Admin Center, go to **Global Secure Access** (left menu)
2. If first time:
   - Click **Get started**
   - Review and accept terms
   - Wait for service provisioning (5-10 minutes)

### Step 3: Configure Private Access

Private Access enables secure connectivity to Azure resources and on-premises applications.

1. Navigate to **Global Secure Access > Connect > Private networks**
2. Click **+ Add private network**
3. Configure:
   - **Name**: `Azure AI Lab Hub`
   - **Connection type**: Select **Site-to-site VPN**
   - **Region**: Select **East US 2** (match your Azure hub region)

### Step 4: Configure VPN Site Connection

1. In the Private network wizard, configure VPN site:
   - **VPN Site Name**: `Azure-AI-Lab-vWAN`
   - **Connection Type**: **Site-to-Site**
   - **BGP Enabled**: ✅ Yes (REQUIRED)
   
2. **BGP Configuration**:
   - **Remote BGP ASN**: `65515` (from Azure VPN Gateway)
   - **Remote BGP Peering Address**: `10.0.0.x` (from deployment outputs)
   
   **WHERE TO FIND**: Run this command to get BGP peering address:
   ```bash
   az deployment sub show \
     --name deploy-ai-core-YYYYMMDD-HHMMSS \
     --query 'properties.outputs.vpnGatewayBgpSettings.value.bgpPeeringAddress' -o tsv
   ```

3. **Link Configuration**:
   - **Link Name**: `Primary-Link`
   - **Link Speed**: `500` (Mbps, matching 1 scale unit)

4. Click **Review + create**, then **Create**

### Step 5: Establish VPN Connection from Azure Side

After creating the VPN site in Global Secure Access, you'll receive connection details to configure the Azure VPN Gateway.

1. In Global Secure Access, go to the VPN site you just created
2. Click **Download VPN configuration**
3. Save the configuration file (contains Global Secure Access VPN endpoint details)

**Azure CLI Configuration**:

```bash
# Create VPN site in Azure (connecting to Global Secure Access)
az network vpn-site create \
  --resource-group rg-ai-core \
  --name vpnsite-global-secure-access \
  --location eastus2 \
  --virtual-wan vwan-ai-hub \
  --ip-address <GLOBAL_SECURE_ACCESS_VPN_ENDPOINT> \
  --bgp-peering-address <GLOBAL_SECURE_ACCESS_BGP_ADDRESS> \
  --asn <GLOBAL_SECURE_ACCESS_ASN>

# Create VPN connection
az network vpn-gateway connection create \
  --resource-group rg-ai-core \
  --gateway-name vpngw-ai-hub \
  --name connection-global-secure-access \
  --vpn-site vpnsite-global-secure-access \
  --enable-bgp true \
  --shared-key <SHARED_KEY_FROM_GLOBAL_SECURE_ACCESS>
```

**Note**: Replace placeholders with actual values from the downloaded Global Secure Access VPN configuration file.

### Step 6: Configure Traffic Forwarding Profiles

Traffic forwarding profiles determine which traffic is sent through Global Secure Access.

#### Private Access Profile

1. Navigate to **Global Secure Access > Connect > Traffic forwarding**
2. Click **Private access profile**
3. Configure:
   - **Enable**: ✅ On
   - **Quick Access**: Add Azure spoke VNet address ranges
     - Example: `10.1.0.0/16` (rg-ai-storage)
     - Example: `10.2.0.0/16` (rg-ai-ml)
   - **Enterprise Applications**: (optional) Add on-premises apps

#### Internet Access Profile (Optional)

1. Click **Internet access profile**
2. Configure:
   - **Enable**: ✅ On (if you want web filtering)
   - **Web Content Filtering**: Configure categories to block/allow
   - **Threat Protection**: Enable malware and phishing protection

#### Microsoft 365 Access Profile (Optional)

1. Click **Microsoft 365 access profile**
2. Configure:
   - **Enable**: ✅ On
   - **Optimize traffic**: Routes to closest Microsoft 365 endpoint
   - **Conditional Access**: Apply zero-trust policies

### Step 7: Verify VPN Connection

**In Azure Portal**:

1. Navigate to Resource Group: `rg-ai-core`
2. Go to VPN Gateway: `vpngw-ai-hub`
3. Check **Connections** blade
4. Verify connection status: **Connected**

**Using Azure CLI**:

```bash
# Check VPN Gateway connections
az network vpn-gateway connection list \
  --resource-group rg-ai-core \
  --gateway-name vpngw-ai-hub \
  --query "[].{Name:name, Status:connectionStatus}" -o table
```

**Expected Output**:
```
Name                            Status
------------------------------  ----------
connection-global-secure-access Connected
```

**In Microsoft Entra Admin Center**:

1. Navigate to **Global Secure Access > Monitor > Traffic logs**
2. Verify traffic flowing through the connection
3. Check **Health status** shows VPN tunnel as "Healthy"

### Step 8: Assign Users to Global Secure Access

Users need Global Secure Access client and policies to route traffic through SSE.

1. Navigate to **Global Secure Access > Deploy > Global Secure Access client**
2. Download and distribute the client to users
3. Navigate to **Conditional Access**
4. Create policies to require Global Secure Access for Azure resource access

## Testing

### Test Private Access

From a machine with Global Secure Access client installed:

1. **Test Azure spoke resource access**:
   ```bash
   # Ping a VM in spoke VNet (e.g., 10.1.0.4 in rg-ai-storage)
   ping 10.1.0.4
   
   # SSH to Azure VM via private IP
   ssh azureuser@10.1.0.4
   ```

2. **Verify traffic routing**:
   - Check Global Secure Access logs in Entra Admin Center
   - Traffic should appear under **Private Access** category

### Test Internet Access (if enabled)

1. Browse to a test website
2. Verify web filtering policies are applied
3. Check logs in **Global Secure Access > Monitor > Traffic logs**

### Test BGP Route Propagation

```bash
# From Azure Cloud Shell or authenticated session
az network vhub get-effective-routes \
  --resource-group rg-ai-core \
  --name hub-ai-eastus2 \
  --query "value[?nextHopType=='VPN Gateway']"
```

**Expected**: Should show routes learned via BGP from Global Secure Access

## Troubleshooting

### Connection Not Establishing

**Symptoms**: VPN connection status shows "Connecting" or "Not Connected"

**Solutions**:
1. Verify BGP settings match on both sides:
   ```bash
   # Azure side BGP ASN
   az network vhub show \
     --resource-group rg-ai-core \
     --name hub-ai-eastus2 \
     --query 'bgpSettings.asn'
   ```
2. Check shared key matches in both Azure and Global Secure Access
3. Verify firewall rules allow UDP 500, UDP 4500 (IPSec/IKE)

### No Traffic Flowing

**Symptoms**: VPN connected but no traffic visible in logs

**Solutions**:
1. Verify traffic forwarding profiles are enabled
2. Check Global Secure Access client is installed and running on user devices
3. Confirm conditional access policies are assigned to users
4. Test with diagnostic tool:
   ```bash
   # From client machine
   Test-NetConnection -ComputerName 10.1.0.4 -Port 22
   ```

### BGP Routes Not Propagating

**Symptoms**: Effective routes don't show BGP-learned routes

**Solutions**:
1. Verify BGP is enabled on both VPN Gateway and Global Secure Access
2. Check BGP peering addresses are correct:
   ```bash
   az network vpn-gateway show \
     --resource-group rg-ai-core \
     --name vpngw-ai-hub \
     --query 'bgpSettings'
   ```
3. Review Azure Network Watcher for BGP session status

### Global Secure Access Client Issues

**Symptoms**: Client shows "Disconnected" or "Not activated"

**Solutions**:
1. Verify user has Global Secure Access license assigned
2. Check conditional access policies include user
3. Restart Global Secure Access client service
4. Review client logs (location varies by OS)

## Security Best Practices

1. **Enable Conditional Access**:
   - Require compliant devices for Azure resource access
   - Enforce multi-factor authentication for sensitive resources

2. **Configure Threat Protection**:
   - Enable malware scanning in Internet Access profile
   - Block risky sign-ins with Identity Protection

3. **Monitor and Alert**:
   - Set up alerts for failed VPN connections
   - Review traffic logs regularly for anomalies
   - Enable diagnostic logging for VPN Gateway

4. **Rotate Shared Keys**:
   - Store VPN shared keys in Azure Key Vault
   - Rotate keys every 90 days
   - Use strong keys (minimum 32 characters)

## Cost Optimization

- **VPN Gateway Scale Units**: Start with 1 unit (500 Mbps), scale up only if needed
- **Global Secure Access Licensing**: Assign licenses only to users requiring SSE
- **Traffic Optimization**: Use Microsoft 365 profile to reduce data egress costs

## Reference

- [Microsoft Entra Global Secure Access Documentation](https://learn.microsoft.com/entra/global-secure-access/)
- [Connect Global Secure Access to Azure Virtual WAN](https://learn.microsoft.com/entra/global-secure-access/how-to-connect-azure-virtual-wan)
- [Configure Private Access](https://learn.microsoft.com/entra/global-secure-access/how-to-configure-private-access)

---

**Version**: 1.0.0  
**Last Updated**: 2025-12-31  
**Status**: Production Ready
