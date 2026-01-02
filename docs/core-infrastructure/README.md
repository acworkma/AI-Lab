# Core Azure vWAN Infrastructure with Point-to-Site VPN

## Overview

This infrastructure establishes the foundational hub-spoke network topology for all AI lab projects using Azure Virtual WAN. The core infrastructure includes a Virtual WAN hub with **Point-to-Site (P2S) VPN Gateway** configured for secure remote access using Microsoft Entra ID authentication.

**Key Components**:
- **Resource Group**: `rg-ai-core` - Container for all core infrastructure
- **Virtual WAN**: `vwan-ai-hub` - Central networking hub (Standard SKU)
- **Virtual Hub**: `hub-ai-eastus2` - Regional hub instance (10.0.0.0/16 address space)
- **P2S VPN Gateway**: `vpngw-ai-hub` - Point-to-Site VPN with Azure AD authentication
- **VPN Server Configuration**: `vpnconfig-ai-hub` - Authentication and protocol settings
- **Key Vault**: `kv-ai-core-*` - Centralized secrets management

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
┌─────────────────────────────────────────────────────────────────┐
│                    Remote VPN Clients                           │
│         (Azure AD Authentication via Azure VPN Client)          │
└──────────────────────────┬──────────────────────────────────────┘
                           │ OpenVPN P2S Tunnel
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│                   rg-ai-core (Resource Group)                   │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Virtual WAN Hub (hub-ai-eastus2)                      │    │
│  │  Address Space: 10.0.0.0/16                            │    │
│  │                                                          │    │
│  │  ┌──────────────────────────────────────────────┐      │    │
│  │  │  P2S VPN Gateway (vpngw-ai-hub)              │      │    │
│  │  │  - Type: Point-to-Site                       │      │    │
│  │  │  - Authentication: Microsoft Entra ID        │      │    │
│  │  │  - Protocol: OpenVPN                         │      │    │
│  │  │  - Client Pool: 172.16.0.0/24                │      │    │
│  │  │  - Scale Units: 1 (500 Mbps)                 │      │    │
│  │  └──────────────────────────────────────────────┘      │    │
│  │                                                          │    │
│  └────────────────┬─────────────────────────────────────────┤    │
│                   │ Spoke Connections                       │    │
│                   │                                          │    │
│  ┌────────────────┴─────────────────────────────────────────┐   │
│  │  Key Vault (kv-ai-core-*)                                │   │
│  │  - RBAC Authorization                                    │   │
│  │  - Soft-Delete Enabled (90 days)                         │   │
│  │  - Secrets for all labs                                  │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
                           │
                           │ VNet Connections
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
  ┌──────────┐      ┌──────────┐      ┌──────────┐
  │ Spoke 1  │      │ Spoke 2  │      │ Spoke 3  │
  │ rg-ai-   │      │ rg-ai-   │      │ rg-ai-   │
  │ storage  │      │    ml    │      │  other   │
  └──────────┘      └──────────┘      └──────────┘
   10.1.0.0/16       10.2.0.0/16       10.3.0.0/16
```

### Point-to-Site VPN Access

The P2S VPN Gateway enables secure remote access to Azure lab resources:

- **Microsoft Entra ID Authentication**: Use organizational credentials to connect
- **OpenVPN Protocol**: Works through most firewalls, encrypted tunnels
- **Client Address Pool**: VPN clients receive IPs from 172.16.0.0/24
- **No On-Premises Hardware**: Client software only, no VPN appliances needed
- **Flexible Access**: Connect from Windows, macOS, Linux, or mobile devices

For VPN client setup instructions, see [vpn-client-setup.md](vpn-client-setup.md).

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
    "keyVaultName": {
      "value": "kv-ai-core-UNIQUE"  // CHANGE THIS to a globally unique name
    }
  }
}
```

**IMPORTANT**: `keyVaultName` must be globally unique across all Azure. Use a random suffix like `kv-ai-core-a1b2` or `kv-ai-core-lab1`.

For all available parameters, see `bicep/main.parameters.example.json`.

### Step 2: Run Deployment Script

```bash
# From repository root
./scripts/deploy-core.sh
```

The script will:
1. ✅ Check prerequisites (Azure CLI, login status)
2. ✅ Validate parameters (Key Vault name format, required values)
3. ✅ Run what-if analysis (preview changes)
4. ❓ Ask for confirmation
5. 🚀 Deploy infrastructure (25-30 minutes)
6. 📊 Show deployment outputs

**Deployment Time**: Approximately 25-30 minutes
- Resource Group: ~5 seconds
- Virtual WAN: ~2 minutes
- Virtual Hub: ~5 minutes
- Key Vault: ~1 minute
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
Key Vault: kv-ai-core-lab1
  - URI: https://kv-ai-core-lab1.vault.azure.net/
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

2. **Assign Key Vault RBAC Roles**:
   ```bash
   # Grant yourself Key Vault Secrets Officer role
   VAULT_ID=$(az keyvault show --name kv-ai-core-lab1 --query id -o tsv)
   USER_ID=$(az ad signed-in-user show --query id -o tsv)
   
   az role assignment create \
     --role "Key Vault Secrets Officer" \
     --assignee $USER_ID \
     --scope $VAULT_ID
   ```

3. **Store Test Secret** (verify access):
   ```bash
   az keyvault secret set \
     --vault-name kv-ai-core-lab1 \
     --name test-secret \
     --value "Hello from Key Vault"
   
   az keyvault secret show \
     --vault-name kv-ai-core-lab1 \
     --name test-secret \
     --query value -o tsv
   ```

### Secure Parameter Management

**Constitutional Requirement**: Principle 4 - NO SECRETS IN SOURCE CONTROL

#### Workflow: Store Secret → Reference → Deploy

1. **Store sensitive value in Key Vault**:
   ```bash
   # Example: VPN shared key
   az keyvault secret set \
     --vault-name kv-ai-core-lab1 \
     --name vpn-shared-key \
     --value "$(openssl rand -base64 32)"
   ```

2. **Create local parameter file** (gitignored):
   ```bash
   # Copy example to local file
   cp bicep/main.keyvault-ref.parameters.json bicep/main.local.parameters.json
   
   # Edit with actual subscription ID and vault name
   nano bicep/main.local.parameters.json
   ```

3. **Reference secret in parameter file**:
   ```json
   {
     "parameters": {
       "vpnSharedKey": {
         "reference": {
           "keyVault": {
             "id": "/subscriptions/abc123.../resourceGroups/rg-ai-core/providers/Microsoft.KeyVault/vaults/kv-ai-core-lab1"
           },
           "secretName": "vpn-shared-key"
         }
       }
     }
   }
   ```

4. **Deploy using local parameter file**:
   ```bash
   ./scripts/deploy-core.sh --parameter-file bicep/main.local.parameters.json
   ```

5. **Verify secret not in source control**:
   ```bash
   # Scan for hardcoded secrets
   ./scripts/scan-secrets.sh
   
   # Check gitignore working
   git status  # Should NOT show .local.parameters.json
   ```

#### Security Best Practices

- ✅ **Always use Key Vault references** for sensitive values
- ✅ **Use .local.parameters.json pattern** for environment-specific secrets (gitignored)
- ✅ **Rotate secrets regularly** (every 90 days minimum)
- ✅ **Scan repository** with `./scripts/scan-secrets.sh` before commits
- ✅ **Enable audit logging** on Key Vault for secret access tracking
- ❌ **Never hardcode** passwords, keys, connection strings, or certificates
- ❌ **Never commit** *.local.parameters.json or *.secrets.* files

#### Example Secrets to Store

| Secret Name | Purpose | Example Command |
|-------------|---------|-----------------|
| `vpn-shared-key` | VPN Gateway PSK | `az keyvault secret set --vault-name kv-ai-core-lab1 --name vpn-shared-key --value "$(openssl rand -base64 32)"` |
| `vm-admin-password` | VM administrator password | `az keyvault secret set --vault-name kv-ai-core-lab1 --name vm-admin-password --value "Str0ng!Pass#$(date +%s)"` |
| `sql-connection-string` | Database connection | `az keyvault secret set --vault-name kv-ai-core-lab1 --name sql-connection-string --value "Server=..."` |
| `storage-account-key` | Storage account access | Retrieved from Azure, stored in Key Vault for spoke labs |

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
- ✅ Key Vault is accessible with RBAC
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

**Test Key Vault access**:
```bash
# Create test secret
az keyvault secret set --vault-name kv-ai-core-lab1 --name test --value "success"

# Retrieve test secret
az keyvault secret show --vault-name kv-ai-core-lab1 --name test --query value -o tsv

# Delete test secret
az keyvault secret delete --vault-name kv-ai-core-lab1 --name test
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
5. Optionally purge Key Vault (permanent deletion)

### Manual Cleanup

```bash
# Delete resource group (deletes all resources)
az group delete --name rg-ai-core --yes --no-wait

# Check deletion status
az group show --name rg-ai-core
# Should return: ResourceGroupNotFound

# Purge soft-deleted Key Vault (optional, permanent)
az keyvault purge --name kv-ai-core-lab1
```

**Note**: Soft-deleted Key Vault is retained for 90 days. Purge immediately if you need to reuse the same name.

## Troubleshooting

### Common Issues

#### 1. Key Vault Name Already Exists

**Error**: `The vault name 'kv-ai-core-lab1' is already in use.`

**Solution**: 
- Choose a different globally unique name
- Or purge the soft-deleted vault:
  ```bash
  az keyvault purge --name kv-ai-core-lab1
  ```

#### 2. Deployment Timeout

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

#### 3. Insufficient Permissions

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

1. **Configure Global Secure Access**: Follow [global-secure-access.md](global-secure-access.md) for SSE integration

2. **Deploy Spoke Labs**: Create spoke virtual networks and connect to hub:
   ```bash
   # Example spoke connection (from spoke lab deployment)
   az network vhub connection create \
     --name connection-to-storage \
     --resource-group rg-ai-core \
     --vhub-name hub-ai-eastus2 \
     --remote-vnet /subscriptions/{sub}/resourceGroups/rg-ai-storage/providers/Microsoft.Network/virtualNetworks/vnet-storage
   ```

3. **Implement Spoke Lab Pattern**: Each lab should:
   - Create its own resource group (`rg-ai-{service}`)
   - Deploy spoke VNet with non-overlapping address space (10.x.0.0/16)
   - Connect to hub using VNet connection
   - Reference Key Vault for secrets

4. **Set Up Monitoring**: Configure Log Analytics and Azure Monitor for hub infrastructure

## Reference

- **Constitution**: [.specify/memory/constitution.md](../../.specify/memory/constitution.md)
- **Specification**: [specs/001-vwan-core/spec.md](../../specs/001-vwan-core/spec.md)
- **Architecture Research**: [specs/001-vwan-core/research.md](../../specs/001-vwan-core/research.md)
- **Data Model**: [specs/001-vwan-core/data-model.md](../../specs/001-vwan-core/data-model.md)

---

**Version**: 1.0.0  
**Last Updated**: 2025-12-31  
**Status**: Production Ready
