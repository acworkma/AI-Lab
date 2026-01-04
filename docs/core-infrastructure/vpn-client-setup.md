# Point-to-Site VPN Configuration Guide

## Overview

This guide explains how to configure and use the **Point-to-Site (P2S) VPN Gateway** to securely connect to your Azure Virtual WAN hub and access lab resources remotely.

**Point-to-Site VPN** provides:
- **Secure Remote Access**: Connect individual client devices to Azure resources via encrypted VPN tunnel
- **Microsoft Entra ID Authentication**: Use your organizational identity to authenticate VPN connections
- **Flexible Connectivity**: Connect from anywhere using the Azure VPN Client
- **No On-Premises Hardware**: Client-based solution requiring no additional infrastructure

## Prerequisites

### Azure Infrastructure (Completed)

✅ Core infrastructure deployed (see [README.md](README.md)):
- Virtual WAN hub (hub-ai-eastus2)
- **Point-to-Site VPN Gateway** (vpngw-ai-hub)
- **VPN Server Configuration** with Microsoft Entra ID authentication (vpnconfig-ai-hub)
- VPN client address pool: 172.16.0.0/24

### Client Requirements

- **Windows 10/11**, **macOS**, or **Linux** device
- **Azure VPN Client** installed (download links below)
- **Microsoft Entra ID Account** with access to the Azure subscription
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
│  │  - Authentication: Microsoft Entra ID                  │    │
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

3. **Sign in with Microsoft Entra ID**:
   - A browser window will open
   - Sign in with your Microsoft Entra ID credentials
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
1. Verify you're using the correct Microsoft Entra ID account
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

Configure Conditional Access policies in Microsoft Entra ID to control VPN access:
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
- Revoke access for departed users via Microsoft Entra ID

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
- [Microsoft Entra ID Authentication for VPN](https://learn.microsoft.com/azure/vpn-gateway/openvpn-azure-ad-tenant)
- [VPN Gateway Monitoring](https://learn.microsoft.com/azure/vpn-gateway/monitor-vpn-gateway)

---

**Version**: 1.0.0  
**Last Updated**: 2025-12-31  
**Status**: Production Ready  
