# Private Azure Storage Account with Customer Managed Key

## Overview

This module deploys a private Azure Storage Account with customer-managed key (CMK) encryption using a key stored in the core Key Vault. The Storage Account is accessible only via private endpoint connected to the core shared services infrastructure, ensuring all data is encrypted with organizational control over encryption keys and accessed only through the VPN.

**Key Components**:
- **Resource Group**: `rg-ai-storage` - Container for storage resources
- **Storage Account**: `stai<env><unique>` - StorageV2 with CMK encryption
- **Managed Identity**: Service principal for accessing encryption key
- **Encryption Key**: Customer-managed key in core Key Vault
- **Private Endpoint**: Connected to `vnet-ai-shared/PrivateEndpointSubnet`
- **DNS Integration**: `privatelink.blob.core.windows.net` private DNS zone

**Deployment Region**: East US 2

## Prerequisites

### Required Infrastructure

1. **Core Infrastructure Deployed**:
   - Run `./scripts/deploy-core.sh` first
   - Must include:
     - Resource group `rg-ai-core`
     - Virtual WAN hub and vHub
     - Shared services VNet (`vnet-ai-shared` with address space `10.1.0.0/24`)
     - Private endpoint subnet (`PrivateEndpointSubnet`)
     - Key Vault (`kv-ai-core-*`)
     - Private DNS zone for `privatelink.blob.core.windows.net`
   - Verify outputs include `privateEndpointSubnetId`, `blobDnsZoneId`, `keyVaultId`

2. **VPN Connection**:
   - Azure VPN Client installed and configured
   - Connected to `vpngw-ai-hub` VPN gateway
   - Required for DNS resolution and storage access
   - See [VPN client setup guide](../core-infrastructure/vpn-client-setup.md)

### Required Tools

- **Azure CLI** (version 2.50.0 or later)
- **jq** (for JSON parsing in deployment script)

### Required Azure Permissions

To deploy this module, your Azure user account needs the following roles/permissions:

#### Deployment Permissions (required to deploy resources)
- **Subscription Level**:
  - `Storage Account Contributor` - Create and manage storage accounts
  - `Key Vault Administrator` (or equivalent) - Create/manage encryption keys in Key Vault
  - `Network Contributor` - Create private endpoints and manage networking
  - `User Access Administrator` - Assign RBAC roles to managed identity

#### Key Vault Permissions (required for CMK setup)
- **Key Vault Access Policy** or **RBAC Role**:
  - `Key Vault Crypto Service Encryption User` - Allow Storage Account to access encryption key
  - `Key Vault Secrets Officer` (deployment only) - Create/manage encryption key

#### Storage Account Management Permissions (post-deployment)
- **Storage Account Level**:
  - `Storage Account Contributor` - Modify configuration, add containers
  - `Storage Blob Data Owner` or `Storage Blob Data Contributor` - Upload/download data

#### Typical Role Combination for Deployment
If your organization uses custom roles, ensure you have:
1. `Contributor` role on the subscription (simplest, includes all above), OR
2. Combination of:
   - `Storage Account Contributor`
   - `Network Contributor`
   - `User Access Administrator`
   - `Key Vault Administrator` (or custom role with key creation permissions)

#### Service Principal/Managed Identity Permissions
The Storage Account managed identity automatically gets:
- **Role**: `Key Vault Crypto Service Encryption User` (assigned during deployment)
- **Scope**: Key Vault (`kv-ai-core-*`)
- **Purpose**: Access encryption key without human intervention

### Permission Verification

Before deployment, verify your permissions:

```bash
# Check your current roles
az role assignment list --assignee $(az account show --query user.name -o tsv) \
  --query "[].roleDefinitionName" -o table

# Verify Key Vault access
az keyvault show --name kv-ai-core-CHANGEME

# Verify DNS zone exists
az network private-dns zone show \
  --resource-group rg-ai-core \
  --name privatelink.blob.core.windows.net
```

If you lack required permissions, contact your subscription owner or Azure administrator.

## Deployment

### Step 1: Verify Core Infrastructure

```bash
# Check that core infrastructure is deployed
az group show --name rg-ai-core

# Verify shared services VNet exists
az network vnet show \
  --resource-group rg-ai-core \
  --name vnet-ai-shared

# Verify private endpoint subnet exists
az network vnet subnet show \
  --resource-group rg-ai-core \
  --vnet-name vnet-ai-shared \
  --name PrivateEndpointSubnet

# Verify Key Vault exists
az keyvault show --name kv-ai-core-<YOUR_SUFFIX>

# Verify private DNS zone exists
az network private-dns zone show \
  --resource-group rg-ai-core \
  --name privatelink.blob.core.windows.net
```

All commands should return successfully with resource details. If any fail, redeploy core infrastructure.

### Step 2: Customize Parameters

Edit `bicep/registry/main.parameters.json` (create if needed):

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2018-05-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus2"
    },
    "environment": {
      "value": "dev"
    },
    "owner": {
      "value": "AI-Lab Team"
    },
    "storageAccountName": {
      "value": "staidevlab001"  # Must be globally unique (3-24 chars)
    },
    "coreResourceGroupName": {
      "value": "rg-ai-core"
    },
    "keyVaultName": {
      "value": "kv-ai-core-CHANGEME"  # Match your core deployment
    },
    "encryptionKeyName": {
      "value": "storage-encryption-key"
    },
    "vnetResourceGroupName": {
      "value": "rg-ai-core"
    },
    "vnetName": {
      "value": "vnet-ai-shared"
    },
    "privateEndpointSubnetName": {
      "value": "PrivateEndpointSubnet"
    },
    "tags": {
      "value": {
        "project": "AI-Lab",
        "service": "Storage"
      }
    }
  }
}
```

### Step 3: Deploy Storage Account

```bash
# Create resource group
az group create \
  --name rg-ai-storage \
  --location eastus2

# Deploy storage module
az deployment group create \
  --resource-group rg-ai-storage \
  --template-file bicep/storage.bicep \
  --parameters bicep/storage.parameters.json

# Capture outputs
STORAGE_ID=$(az deployment group show \
  --resource-group rg-ai-storage \
  --name storage \
  --query "properties.outputs.storageAccountId.value" -o tsv)

STORAGE_NAME=$(az deployment group show \
  --resource-group rg-ai-storage \
  --name storage \
  --query "properties.outputs.storageAccountName.value" -o tsv)

echo "Storage Account: $STORAGE_NAME"
echo "Resource ID: $STORAGE_ID"
```

### Step 4: Verify Deployment

```bash
# Check storage account exists
az storage account show \
  --name $STORAGE_NAME \
  --resource-group rg-ai-storage \
  --query "{name:name, encryption:encryption, kind:kind, primaryEndpoints:primaryEndpoints}"

# Verify CMK encryption
az storage account show \
  --name $STORAGE_NAME \
  --resource-group rg-ai-storage \
  --query "encryption"

# Check private endpoint
az network private-endpoint show \
  --name pe-storage-blob \
  --resource-group rg-ai-storage

# Verify managed identity
IDENTITY=$(az storage account show \
  --name $STORAGE_NAME \
  --resource-group rg-ai-storage \
  --query "identity.principalId" -o tsv)

az ad sp show --id $IDENTITY --query displayName
```

## Usage

### Create a Blob Container

```bash
# Create container
az storage container create \
  --account-name $STORAGE_NAME \
  --name data \
  --auth-mode login
```

### Upload Data (from VPN-connected client)

```bash
# Ensure VPN is connected
# Create a test file
echo "Test data" > test.txt

# Upload to storage
az storage blob upload \
  --account-name $STORAGE_NAME \
  --container-name data \
  --name test.txt \
  --file test.txt \
  --auth-mode login
```

### Download Data

```bash
# Download from storage
az storage blob download \
  --account-name $STORAGE_NAME \
  --container-name data \
  --name test.txt \
  --file downloaded.txt \
  --auth-mode login

# Verify contents
cat downloaded.txt
```

## Security

### Customer Managed Key Encryption

The Storage Account uses a customer-managed encryption key (CMK) stored in the core Key Vault. This provides:

- **Organizational Control**: You manage the encryption key lifecycle
- **Key Rotation**: Rotate keys annually or per policy
- **Audit Trail**: All key access is logged in Azure Monitor
- **Compliance**: Meets regulatory requirements for key management

### Key Rotation

```bash
# List versions of encryption key
az keyvault key list-versions \
  --vault-name kv-ai-core-CHANGEME \
  --name storage-encryption-key

# Create new key version (automatic rotation)
az keyvault key rotate \
  --vault-name kv-ai-core-CHANGEME \
  --name storage-encryption-key
```

### Managed Identity

The Storage Account uses a managed identity to access the encryption key. This eliminates the need for:
- Service account passwords
- Connection strings with secrets
- Key Vault connection secrets

The managed identity is automatically assigned the `Key Vault Crypto Service Encryption User` role during deployment.

### Network Security

- **Public Access**: Disabled - storage is not accessible from the internet
- **Private Endpoint**: All traffic flows through the private endpoint in the shared services VNet
- **DNS Resolution**: Private DNS resolves storage FQDN to private IP (10.1.0.x)
- **VPN Required**: Access requires VPN connection to the hub

## Troubleshooting

### Issue: "Public endpoints are disabled" error when uploading

**Cause**: Storage account has public access disabled (expected behavior)

**Solution**: Ensure you are connected to VPN and using private endpoint DNS:

```bash
# Verify you're connected to VPN
# Use storage account's private endpoint DNS
nslookup ${STORAGE_NAME}.blob.core.windows.net 10.1.0.68
```

### Issue: Private endpoint DNS resolution returns public IP

**Cause**: DNS query is not going through the resolver, or DNS zone link is missing

**Solution**:

```bash
# Verify DNS zone is linked to shared VNet
az network private-dns link vnet show \
  --resource-group rg-ai-core \
  --zone-name privatelink.blob.core.windows.net \
  --name vnet-link

# If missing, link it:
az network private-dns link vnet create \
  --resource-group rg-ai-core \
  --zone-name privatelink.blob.core.windows.net \
  --name vnet-link \
  --virtual-network /subscriptions/{sub}/resourceGroups/rg-ai-core/providers/Microsoft.Network/virtualNetworks/vnet-ai-shared \
  --registration-enabled false
```

### Issue: "The user, group, or application does not have the right permissions" when deploying

**Cause**: User account lacks required permissions

**Solution**: Verify permissions and request elevated access:

```bash
# Check current roles
az role assignment list --assignee $(az account show --query user.name -o tsv) \
  --query "[].roleDefinitionName" -o table

# Request: Storage Account Contributor, Network Contributor, Key Vault Administrator
```

### Issue: Encryption key not found or Key Vault access denied

**Cause**: Managed identity doesn't have permission to access Key Vault

**Solution**:

```bash
# Get managed identity
IDENTITY=$(az storage account show \
  --name $STORAGE_NAME \
  --resource-group rg-ai-storage \
  --query "identity.principalId" -o tsv)

# Verify Key Vault role assignment
az role assignment list \
  --assignee $IDENTITY \
  --scope /subscriptions/{sub}/resourceGroups/rg-ai-core/providers/Microsoft.KeyVault/vaults/kv-ai-core-CHANGEME

# If missing, assign role (requires Key Vault Administrator)
az role assignment create \
  --assignee-object-id $IDENTITY \
  --role "Key Vault Crypto Service Encryption User" \
  --scope /subscriptions/{sub}/resourceGroups/rg-ai-core/providers/Microsoft.KeyVault/vaults/kv-ai-core-CHANGEME
```

## FAQ

### Q: Can I use the same encryption key for multiple storage accounts?

**A**: Yes, multiple Storage Accounts can share the same Key Vault encryption key. Each references the same key by name. Key rotation affects all accounts using that key.

### Q: What happens if the Key Vault key is deleted?

**A**: Storage Account operations will fail with "Key not found" errors. Keys are soft-deleted by default (30-day recovery window). Restore the key or recover from backups.

### Q: Can I disable public access after deployment?

**A**: Public access should already be disabled during deployment. If you enabled it, disable it:

```bash
az storage account update \
  --name $STORAGE_NAME \
  --resource-group rg-ai-storage \
  --default-action Deny
```

### Q: How do I monitor encryption key usage?

**A**: Check Azure Monitor / Log Analytics:

```bash
# Query Key Vault operations
az monitor metrics list \
  --resource /subscriptions/{sub}/resourceGroups/rg-ai-core/providers/Microsoft.KeyVault/vaults/kv-ai-core-CHANGEME \
  --metric "ServiceApiLatency" \
  --interval PT1M
```

### Q: Can I use storage from outside VPN?

**A**: No - public endpoint is disabled and private endpoint is accessible only from networks with routing to the shared services VNet. This includes:
- VPN-connected clients (recommended)
- Resources in peered VNets
- Resources in the shared services VNet itself

Non-VPN access is blocked by design.

## Reference

- [Azure Storage Account Overview](https://learn.microsoft.com/azure/storage/common/storage-account-overview)
- [Customer Managed Keys for Storage Encryption](https://learn.microsoft.com/azure/storage/common/customer-managed-keys-overview)
- [Azure Storage Private Endpoints](https://learn.microsoft.com/azure/storage/common/storage-private-endpoints)
- [Azure Key Vault Best Practices](https://learn.microsoft.com/azure/key-vault/general/best-practices)
- [RBAC for Storage Accounts](https://learn.microsoft.com/azure/storage/common/authorization-resource-provider)

---

**Version**: 1.0.0  
**Last Updated**: 2026-01-07  
**Status**: In Development
