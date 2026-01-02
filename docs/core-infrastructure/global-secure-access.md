# Point-to-Site VPN Configuration Guide

## Overview

This guide explains how to configure and use the **Point-to-Site (P2S) VPN Gateway** to securely connect to your Azure Virtual WAN hub and access lab resources remotely.

**Point-to-Site VPN** provides:
- **Secure Remote Access**: Connect individual client devices to Azure resources via encrypted VPN tunnel
- **Azure AD Authentication**: Use your organizational identity to authenticate VPN connections
- **Flexible Connectivity**: Connect from anywhere using the Azure VPN Client
- **No On-Premises Hardware**: Client-based solution requiring no additional infrastructure

## Prerequisites

### Azure Infrastructure (Completed)

✅ Core infrastructure deployed (see [README.md](README.md)):
- Virtual WAN hub (hub-ai-eastus2)
- **Point-to-Site VPN Gateway** (vpngw-ai-hub)
- **VPN Server Configuration** with Azure AD authentication (vpnconfig-ai-hub)
- VPN client address pool: 172.16.0.0/24

### Client Requirements

- **Windows 10/11**, **macOS**, or **Linux** device
- **Azure VPN Client** installed (download links below)
- **Azure AD Account** with access to the Azure subscription
- **Internet Connection** for VPN connectivity

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    Remote Client Devices                        │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │   Laptop     │  │   Desktop    │  │   Mobile     │         │
│  │ (Azure VPN)  │  │ (Azure VPN)  │  │ (Azure VPN)  │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
│         │                  │                  │                 │
│         │  Secure VPN Tunnel (OpenVPN/IkeV2) │                 │
│         │         Azure AD Authentication     │                 │
└─────────┼──────────────────┼──────────────────┼─────────────────┘
          │                  │                  │
          └──────────────────┴──────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────────────┐
│              Azure Virtual WAN Hub (hub-ai-eastus2)             │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  P2S VPN Gateway (vpngw-ai-hub)                        │    │
│  │  - Type: Point-to-Site                                 │    │
│  │  - Authentication: Azure AD                            │    │
│  │  - Protocols: OpenVPN                                  │    │
│  │  - Client Address Pool: 172.16.0.0/24                  │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Connected Spoke VNets                                 │    │
│  │  - Lab virtual machines                                │    │
│  │  - Azure services                                      │    │
│  └────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

## Configuration Steps

### Step 1: Download VPN Client Profile

The VPN client profile contains the configuration needed to connect to your Azure VPN Gateway.

1. **Get the VPN profile using Azure CLI**:
   ```bash
   # Set variables
   RESOURCE_GROUP="rg-ai-core"
   VPN_GATEWAY_NAME="vpngw-ai-hub"
   
   # Download VPN client configuration
   az network p2s-vpn-gateway vpn-client generate \
     --resource-group $RESOURCE_GROUP \
     --name $VPN_GATEWAY_NAME \
     --authentication-method EAPTLS
   ```

2. **The command will return a URL** - download the ZIP file from that URL

3. **Extract the ZIP file** - you'll find configuration files for different platforms

### Step 2: Install Azure VPN Client

Download and install the Azure VPN Client for your operating system:

**Windows**:
- Download from [Microsoft Store](https://www.microsoft.com/store/productId/9NP355QT2SQB)
- Or download from [Azure VPN Client Downloads](https://aka.ms/azvpnclient)

**macOS**:
- Download from [Apple App Store](https://apps.apple.com/app/azure-vpn-client/id1553936137)

**Linux**:
- Follow the [Azure VPN Client for Linux documentation](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-vpn-client-linux-azure-vpn-client)

### Step 3: Import VPN Profile

1. **Open Azure VPN Client** on your device

2. **Click the "+" button** or "Import" to add a new connection

3. **Navigate to the extracted profile folder**:
   - For Azure VPN Client: Look for the `azurevpnconfig.xml` file in the `AzureVPN` folder

4. **Import the configuration file**

5. **The connection profile will appear** with the name of your VPN gateway

### Step 4: Connect to VPN

1. **In Azure VPN Client**, select the imported connection profile

2. **Click "Connect"**

3. **Sign in with Azure AD**:
   - A browser window will open
   - Sign in with your Azure AD credentials
   - You may be prompted for MFA if configured

4. **Connection established**:
   - The client will show "Connected" status
   - You'll receive an IP address from the client address pool (172.16.0.0/24)

5. **Verify connectivity**:
   ```bash
   # Check your VPN IP address
   ipconfig  # Windows
   ifconfig  # macOS/Linux
   
   # Test connectivity to Azure resources
   ping <private-ip-of-azure-vm>
   ```

## Troubleshooting

### Connection Fails with Authentication Error

**Issue**: Authentication fails or browser doesn't open

**Solutions**:
1. Verify you're using the correct Azure AD account
2. Check that your account has access to the subscription
3. Ensure Azure VPN Client is up to date
4. Clear browser cache and try again

### Cannot Access Azure Resources After Connecting

**Issue**: VPN connected but cannot reach VMs or services

**Solutions**:
1. **Verify spoke VNet is connected to hub**:
   ```bash
   az network vhub connection list \
     --resource-group rg-ai-core \
     --vhub-name hub-ai-eastus2 \
     --output table
   ```

2. **Check Network Security Groups (NSGs)**:
   - Ensure NSGs on target VMs allow traffic from VPN client pool (172.16.0.0/24)

3. **Verify routing**:
   ```bash
   # Check effective routes on hub
   az network vhub get-effective-routes \
     --resource-group rg-ai-core \
     --name hub-ai-eastus2 \
     --resource-type P2SVpnGateway \
     --resource-id /subscriptions/<sub-id>/resourceGroups/rg-ai-core/providers/Microsoft.Network/p2sVpnGateways/vpngw-ai-hub
   ```

### VPN Client Configuration Not Downloading

**Issue**: Cannot generate or download VPN client profile

**Solutions**:
1. **Verify VPN Gateway is fully provisioned**:
   ```bash
   az network p2s-vpn-gateway show \
     --resource-group rg-ai-core \
     --name vpngw-ai-hub \
     --query "provisioningState"
   ```
   - Should return "Succeeded"

2. **Check VPN Server Configuration**:
   ```bash
   az network vpn-server-config show \
     --resource-group rg-ai-core \
     --name vpnconfig-ai-hub
   ```

### Slow VPN Performance

**Issue**: VPN connection is slow or unstable

**Solutions**:
1. **Check VPN Gateway scale units**:
   - 1 scale unit = 500 Mbps aggregate throughput
   - Scale up if needed:
     ```bash
     # Update scale units in parameters file and redeploy
     # Or update directly (requires gateway recreation)
     ```

2. **Try different protocol**:
   - OpenVPN (TCP-based, better firewall traversal)
   - IkeV2 (UDP-based, better performance)

3. **Check client internet connection**:
   - VPN performance depends on your internet bandwidth
   - Run speed test without VPN to establish baseline

## Security Best Practices

### 1. Enable Conditional Access

Configure Conditional Access policies in Azure AD to control VPN access:
- Require MFA for VPN connections
- Restrict by location, device compliance, or risk level
- Limit access to specific user groups

### 2. Monitor VPN Connections

Check connected VPN clients and connection health:
```bash
# View VPN client connections
az network p2s-vpn-gateway show \
  --resource-group rg-ai-core \
  --name vpngw-ai-hub \
  --query "vpnClientConnectionHealth"
```

### 3. Regular Profile Updates

- Regenerate VPN profiles periodically
- Distribute updated profiles to users
- Revoke access for departed users via Azure AD

### 4. Network Segmentation

- Use NSGs to limit VPN client access to only required resources
- Implement least-privilege access model
- Consider Azure Firewall for additional traffic inspection

## Advanced Configuration

### Custom DNS Servers

To use custom DNS servers for VPN clients, update the VPN Gateway configuration:

```bash
# Update VPN Gateway with custom DNS
az network p2s-vpn-gateway update \
  --resource-group rg-ai-core \
  --name vpngw-ai-hub \
  --custom-dns-servers "10.0.1.4" "10.0.1.5"
```

### Multiple Connection Configurations

You can configure different settings for different user groups using VPN Server Configuration Policy Groups (advanced scenario - requires Azure AD group-based policies).

## Next Steps

After configuring VPN access:

1. **Connect spoke virtual networks** to the hub for resource access
2. **Configure NSGs** to allow VPN client traffic (172.16.0.0/24)
3. **Deploy lab resources** in spoke VNets
4. **Set up Azure Bastion** as an alternative access method for critical resources
5. **Enable diagnostic logging** for VPN Gateway monitoring

## Additional Resources

- [Azure Point-to-Site VPN Documentation](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-about)
- [Azure VPN Client Documentation](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-vpn-client-cert-windows)
- [Azure AD Authentication for VPN](https://learn.microsoft.com/azure/vpn-gateway/openvpn-azure-ad-tenant)
- [VPN Gateway Monitoring](https://learn.microsoft.com/azure/vpn-gateway/monitor-vpn-gateway)

### Step 4: Configure VPN Site Connection

1. In the Private network wizard, configure VPN site:
   - **VPN Site Name**: `Azure-AI-Lab-vWAN`
   - **Connection Type**: **Site-to-Site**
   - **BGP Enabled**: ✅ Yes (REQUIRED)
   
2. **BGP Configuration**:
   - **Remote BGP ASN**: `65515` (from Azure VPN Gateway)
   - **Remote BGP Peering Address**: `10.0.0.12` (from deployment outputs)
   
   **WHERE TO FIND**: Run this command to get BGP peering address:
   ```bash
   az deployment sub show \
     --name deploy-ai-core-YYYYMMDD-HHMMSS \
     --query 'properties.outputs.vpnGatewayBgpSettings.value.bgpPeeringAddress' -o tsv
   ```

3. **Domain Configuration** (when prompted):
   - **Domain name**: `<your-tenant>.onmicrosoft.com` (your tenant's default domain)
   - **Resolved to IP address type**: **IP address** (single VPN endpoint)
   - **IP address version**: **IPv4** (matches Virtual Hub's IPv4 addressing)
   - **Resolved to IP address value**: `10.0.0.12` (BGP peering address from deployment)
   
   **Get BGP Peering Address**:
   ```bash
   az deployment sub show \
     --name <your-deployment-name> \
     --query 'properties.outputs.vpnGatewayBgpSettings.value.bgpPeeringAddress' -o tsv
   ```

4. **Link Configuration**:
   - **Link Name**: `Primary-Link`
   - **Link Speed**: `500` (Mbps, matching 1 scale unit)

5. Click **Review + create**, then **Create**

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
