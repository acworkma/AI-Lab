# Core Azure vWAN Infrastructure with Point-to-Site VPN

## Overview

This infrastructure establishes the foundational hub-spoke network topology for all AI lab projects using Azure Virtual WAN. The core infrastructure includes a Virtual WAN hub with **Point-to-Site (P2S) VPN Gateway** configured for secure remote access using Microsoft Entra ID authentication.

**Key Components**:
- **Resource Group**: `rg-ai-core` - Container for all core infrastructure
- **Virtual WAN**: `vwan-ai-hub` - Central networking hub (Standard SKU)
- **Virtual Hub**: `hub-ai-eastus2` - Regional hub instance (10.0.0.0/16 address space)
- **P2S VPN Gateway**: `vpngw-ai-hub` - Point-to-Site VPN with Entra ID authentication
- **VPN Server Configuration**: `vpnconfig-ai-hub` - Authentication and protocol settings
- **DNS Private Resolver**: `dnsr-ai-shared` - Private DNS resolution for P2S clients (inbound endpoint: `10.1.0.68`)
- **Shared Services VNet**: `vnet-ai-shared` - Network for resolver, shared services, and private endpoints (10.1.0.0/24)
- **Private DNS Zones**: 5 zones for ACR, Key Vault, Storage, File Storage, SQL Database

**Deployment Region**: East US 2

## Prerequisites

### Required Tools

- **Azure CLI** (version 2.50.0 or later)
  ```bash
  # Install: https://aka.ms/azure-cli
  az version
  ```

- **Azure Subscription** with sufficient permissions:
  - Subscription Contributor (or Owner)
  - Ability to create resource groups and networking resources

- **jq** (for JSON parsing in scripts)
  ```bash
  # Ubuntu/Debian
  sudo apt-get install jq
  
  # macOS
  brew install jq
  ```

### Azure Account Setup

1. **Login to Azure**:
   ```bash
   az login
   ```

2. **Set active subscription** (if you have multiple):
   ```bash
   az account list -o table
   az account set --subscription "YOUR_SUBSCRIPTION_ID"
   ```

3. **Verify permissions**:
   ```bash
   az role assignment list --assignee $(az account show --query user.name -o tsv) -o table
   ```

## Architecture

### Hub-Spoke Network Topology

```
┌───────────────────────────────────────────────────────────────┐
│                      Remote VPN Clients                       │
│          (Entra ID Authentication via Azure VPN Client)       │
└─────────────────────────────┬─────────────────────────────────┘
                              │ OpenVPN P2S Tunnel
                              │
┌─────────────────────────────▼─────────────────────────────────┐
│                   rg-ai-core (Resource Group)                 │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Virtual WAN Hub (hub-ai-eastus2)                       │  │
│  │  Address Space: 10.0.0.0/16                             │  │
│  │                                                         │  │
│  │  ┌───────────────────────────────────────────────────┐  │  │
│  │  │  P2S VPN Gateway (vpngw-ai-hub)                   │  │  │
│  │  │  - Type: Point-to-Site                            │  │  │
│  │  │  - Authentication: Microsoft Entra ID             │  │  │
│  │  │  - Protocol: OpenVPN                              │  │  │
│  │  │  - Client Pool: 172.16.0.0/24                     │  │  │
│  │  │  - Scale Units: 1 (500 Mbps)                      │  │  │
│  │  └───────────────────────────────────────────────────┘  │  │
│  │                                                         │  │
│  └───────────────────────────┬─────────────────────────────┘  │
│                              │ Spoke Connections              │
│                              │                                │
│  ┌───────────────────────────┴─────────────────────────────┐  │
│  │  Shared Services VNet (vnet-ai-shared)                  │  │
│  │  Address Space: 10.1.0.0/24                             │  │
│  │                                                         │  │
│  │  ┌───────────────────────────────────────────────────┐  │  │
│  │  │  DNS Private Resolver (dnsr-ai-shared)            │  │  │
│  │  │  - Inbound Endpoint IP: 10.1.0.68                 │  │  │
│  │  │  - Queries Private DNS Zones                      │  │  │
│  │  │  - Public DNS Fallback                            │  │  │
│  │  └───────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
                              │
                              │ VNet Connections
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
  ┌───────────┐        ┌───────────┐        ┌───────────┐
  │  Spoke 1  │        │  Spoke 2  │        │  Spoke 3  │
  │  rg-ai-   │        │  rg-ai-   │        │  rg-ai-   │
  │  storage  │        │    ml     │        │   other   │
  └───────────┘        └───────────┘        └───────────┘
   10.1.0.0/16          10.2.0.0/16          10.3.0.0/16
```

### Point-to-Site VPN Access

The P2S VPN Gateway enables secure remote access to Azure lab resources:

- **Microsoft Entra ID Authentication**: Use organizational credentials to connect
- **OpenVPN Protocol**: Works through most firewalls, encrypted tunnels
- **Client Address Pool**: VPN clients receive IPs from 172.16.0.0/24
- **No On-Premises Hardware**: Client software only, no VPN appliances needed
- **Flexible Access**: Connect from Windows, macOS, Linux, or mobile devices

For VPN client setup instructions, see [vpn-client-setup.md](vpn-client-setup.md).

### Private DNS Resolution

The **DNS Private Resolver** provides seamless private endpoint resolution for P2S VPN clients:

- **Inbound Endpoint**: `10.1.0.68` (deployed in shared services VNet)
- **Purpose**: Allows P2S clients (like WSL) to resolve Azure service FQDNs to private endpoint IPs
- **Benefits**: No manual `/etc/hosts` management, automatic resolution for ACR, Storage, etc.
- **Public DNS Fallback**: Still resolves public domains (google.com, microsoft.com, etc.)

**How It Works**:
```
WSL Client (172.16.x.x) → DNS query for acr.azurecr.io → Resolver (10.1.0.68)
  → Private DNS Zone (privatelink.azurecr.io) → Returns private IP (10.1.0.5)
  → WSL connects to private endpoint over VPN tunnel
```

For detailed setup and configuration, see [dns-resolver-setup.md](dns-resolver-setup.md).

**Client Configuration**: Configure P2S clients to use `10.1.0.68` as primary DNS server.

## Deployment

### Step 1: Customize Parameters

Edit `bicep/main.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus2"
    },
    "environment": {
      "value": "dev"
    },
    "owner": {
      "value": "Your Name or Team"
    },
    "aadTenantId": {
      "value": "YOUR_ENTRA_TENANT_ID"  // REQUIRED: Your Microsoft Entra tenant ID
    },
    "aadIssuer": {
      "value": "https://sts.windows.net/YOUR_ENTRA_TENANT_ID/"
    }
  }
}
```

**IMPORTANT**: `aadTenantId` and `aadIssuer` are required for VPN authentication. Find your tenant ID in Azure Portal > Microsoft Entra ID > Overview.

For all available parameters, see `bicep/main.parameters.example.json`.

### Step 2: Run Deployment Script

```bash
# From repository root
./scripts/deploy-core.sh
```

The script will:
1. ✅ Check prerequisites (Azure CLI, login status)
2. ✅ Validate parameters (Entra ID tenant ID, required values)
3. ✅ Run what-if analysis (preview changes)
4. ❓ Ask for confirmation
5. 🚀 Deploy infrastructure (25-30 minutes)
6. 📊 Show deployment outputs

**Deployment Time**: Approximately 25-30 minutes
- Resource Group: ~5 seconds
- Virtual WAN: ~2 minutes
- Virtual Hub: ~5 minutes
- DNS Resolver: ~3-5 minutes
- **VPN Gateway: ~15-20 minutes** (longest component)

### Step 3: Verify Deployment

After deployment completes, the script will display outputs:

```
Deployment Outputs:
===================
Resource Group: rg-ai-core
Virtual WAN: vwan-ai-hub
Virtual Hub: hub-ai-eastus2
  - Address Prefix: 10.0.0.0/16
  - Routing State: Provisioned
VPN Server Config: vpnconfig-ai-hub
  - Authentication: Microsoft Entra ID
  - Protocols: OpenVPN
P2S VPN Gateway: vpngw-ai-hub
  - Scale Units: 1
  - Client Address Pool: 172.16.0.0/24
Shared Services VNet: vnet-ai-shared
  - Address Prefix: 10.1.0.0/24
DNS Resolver Inbound IP: 10.1.0.68
```

### Advanced: Custom Deployment

```bash
# Use custom parameter file
./scripts/deploy-core.sh --parameter-file bicep/main.parameters.prod.json

# Skip what-if analysis (not recommended)
./scripts/deploy-core.sh --skip-whatif

# Auto-approve for CI/CD pipelines
./scripts/deploy-core.sh --auto-approve
```

## Configuration

### Post-Deployment Tasks

1. **Configure VPN Client Access**:
   - Follow [vpn-client-setup.md](vpn-client-setup.md) for step-by-step client configuration
   - Download VPN client profile
   - Install Azure VPN Client on your device
   - Connect using Microsoft Entra ID credentials

2. **Configure DNS for P2S Clients**:
   - Set DNS server to `10.1.0.68` (DNS Resolver inbound IP)
   - This enables resolution of private endpoints
   - See [dns-resolver-setup.md](dns-resolver-setup.md) for details

3. **Connect Spoke Labs**:
   - Deploy spoke infrastructure (storage, ACR, etc.)
   - Connect spoke VNets to Virtual Hub
   - Private DNS zones will automatically resolve private endpoints

### Secure Parameter Management

**Constitutional Requirement**: Principle 4 - NO SECRETS IN SOURCE CONTROL

For deployments that require secrets (spoke labs, storage with CMK, etc.), use the following pattern:

#### Workflow: Store Secret → Reference → Deploy

1. **Deploy Key Vault separately** (when needed):
   - Key Vault is deployed as a separate infrastructure component
   - See `bicep/keyvault/` for standalone Key Vault deployment (future)
   - Each Key Vault includes private endpoint for secure access

2. **Create local parameter file** (gitignored):
   ```bash
   # Copy example to local file
   cp bicep/storage/main.parameters.example.json bicep/storage/main.local.parameters.json
   
   # Edit with actual values
   nano bicep/storage/main.local.parameters.json
   ```

3. **Deploy using local parameter file**:
   ```bash
   ./scripts/deploy-storage.sh --parameter-file bicep/storage/main.local.parameters.json
   ```

4. **Verify secret not in source control**:
   ```bash
   # Scan for hardcoded secrets
   ./scripts/scan-secrets.sh
   
   # Check gitignore working
   git status  # Should NOT show .local.parameters.json
   ```

#### Security Best Practices

- ✅ **Use .local.parameters.json pattern** for environment-specific config (gitignored)
- ✅ **Scan repository** with `./scripts/scan-secrets.sh` before commits
- ❌ **Never hardcode** passwords, keys, connection strings, or certificates
- ❌ **Never commit** *.local.parameters.json or *.secrets.* files

## Testing

### Validation Script

Run automated validation checks:

```bash
./scripts/validate-core.sh
```

This script verifies:
- ✅ Resource group exists with correct tags
- ✅ Virtual WAN and Hub are provisioned
- ✅ VPN Gateway is ready for connections
- ✅ DNS Resolver is configured
- ✅ Private DNS zones are linked
- ✅ No configuration drift (what-if shows no changes)

### Manual Verification

**Check resources in Azure Portal**:
1. Navigate to [Azure Portal](https://portal.azure.com)
2. Go to Resource Group: `rg-ai-core`
3. Verify all resources show **"Succeeded"** provisioning state

**Check VPN Gateway readiness**:
```bash
az network vhub show \
  --resource-group rg-ai-core \
  --name hub-ai-eastus2 \
  --query routingState -o tsv
# Should output: Provisioned
```

**Check DNS Resolver**:
```bash
az dns-resolver inbound-endpoint list \
  --resource-group rg-ai-core \
  --dns-resolver-name dnsr-ai-shared \
  --query "[].{name:name, ip:ipConfigurations[0].privateIpAddress}" -o table
# Should show: 10.1.0.68
```

## Cleanup

### Delete All Resources

**WARNING**: This will permanently delete all core infrastructure and spoke connections.

```bash
./scripts/cleanup-core.sh
```

The cleanup script will:
1. List all spoke connections and warn if any exist
2. Ask for confirmation
3. Delete spoke connections (if any)
4. Delete resource group `rg-ai-core` (cascades to all resources)

### Manual Cleanup

```bash
# Delete resource group (deletes all resources)
az group delete --name rg-ai-core --yes --no-wait

# Check deletion status
az group show --name rg-ai-core
# Should return: ResourceGroupNotFound
```

## Troubleshooting

### Common Issues

#### 1. Deployment Timeout

**Error**: Deployment exceeds 30 minutes, particularly for VPN Gateway.

**Solution**:
- VPN Gateway can take 15-25 minutes - this is normal
- Check deployment status:
  ```bash
  az deployment sub show --name deploy-ai-core-TIMESTAMP --query properties.provisioningState
  ```
- If truly stuck, cancel and redeploy:
  ```bash
  az deployment sub cancel --name deploy-ai-core-TIMESTAMP
  ```

#### 2. Insufficient Permissions

**Error**: `Authorization failed` or `The client does not have authorization to perform action`

**Solution**:
- Verify you have Contributor role on subscription:
  ```bash
  az role assignment list --assignee $(az account show --query user.name -o tsv) -o table
  ```
- Request elevated permissions from subscription admin

#### 4. What-if Shows Unexpected Changes

**Error**: What-if shows resources will be deleted or modified on re-deployment

**Solution**:
- **Expected**: First deployment shows all resources as "Create"
- **Unexpected (re-deployment)**: Should show "No change" if parameters unchanged
- If seeing unexpected changes:
  - Review parameter differences
  - Check for manual portal modifications (violates constitution)
  - Verify Bicep template hasn't changed

### Debug Commands

```bash
# Check resource provisioning states
az resource list --resource-group rg-ai-core --query "[].{Name:name, Type:type, State:provisioningState}" -o table

# View deployment error details
az deployment sub show --name deploy-ai-core-TIMESTAMP --query properties.error

# Check activity log for errors
az monitor activity-log list --resource-group rg-ai-core --max-events 50 --query "[?level=='Error']" -o table

# Test Key Vault connectivity
az keyvault secret list --vault-name kv-ai-core-lab1
```

## Next Steps

1. **Deploy Spoke Labs**: Create spoke virtual networks and connect to hub:
   ```bash
   # Example spoke connection (from spoke lab deployment)
   az network vhub connection create \
     --name connection-to-storage \
     --resource-group rg-ai-core \
     --vhub-name hub-ai-eastus2 \
     --remote-vnet /subscriptions/{sub}/resourceGroups/rg-ai-storage/providers/Microsoft.Network/virtualNetworks/vnet-storage
   ```

2. **Implement Spoke Lab Pattern**: Each lab should:
   - Create its own resource group (`rg-ai-{service}`)
   - Deploy spoke VNet with non-overlapping address space (10.x.0.0/16)
   - Connect to hub using VNet connection
   - Reference Key Vault for secrets

3. **Set Up Monitoring**: Configure Log Analytics and Azure Monitor for hub infrastructure

## Reference

- **Constitution**: [.specify/memory/constitution.md](../../.specify/memory/constitution.md)
- **Specification**: [specs/001-vwan-core/spec.md](../../specs/001-vwan-core/spec.md)
- **Architecture Research**: [specs/001-vwan-core/research.md](../../specs/001-vwan-core/research.md)
- **Data Model**: [specs/001-vwan-core/data-model.md](../../specs/001-vwan-core/data-model.md)

---

**Version**: 1.0.0  
**Last Updated**: 2025-12-31  
**Status**: Production Ready
