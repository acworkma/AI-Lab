# Quickstart: Private Azure Key Vault

**Feature**: 008-private-keyvault  
**Phase**: 1 - Design  
**Date**: 2026-01-17

## Overview

This guide walks through deploying Azure Key Vault with private endpoint connectivity for secure secrets management in the AI-Lab environment.

---

## Prerequisites

### 1. Core Infrastructure Deployed
The following resources must exist in `rg-ai-core`:
- Virtual WAN hub with VPN Gateway
- Shared services VNet (`vnet-ai-shared`) with `snet-private-endpoints` subnet
- Private DNS zone `privatelink.vaultcore.azure.net`
- DNS Private Resolver

```bash
# Verify core infrastructure exists
az group show --name rg-ai-core --query "properties.provisioningState" -o tsv
# Expected: Succeeded

# Verify private DNS zone
az network private-dns zone show \
  --name "privatelink.vaultcore.azure.net" \
  --resource-group "rg-ai-core" \
  --query "name" -o tsv
# Expected: privatelink.vaultcore.azure.net
```

### 2. Azure CLI Configured
```bash
# Check Azure CLI version (requires 2.50+)
az --version | head -1

# Login and set subscription
az login
az account set --subscription "<your-subscription-id>"
```

### 3. VPN Connection (for Verification)
To validate private endpoint connectivity, you need VPN access to the vWAN hub.

---

## Step 1: Configure Parameters

### Create Parameter File
```bash
cd /home/adworkma/AI-Lab

# Copy example parameter file
cp bicep/keyvault/main.parameters.example.json bicep/keyvault/main.parameters.json

# Edit with your values
code bicep/keyvault/main.parameters.json
```

### Parameter File Contents
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "owner": {
      "value": "your-name-or-team"
    },
    "environment": {
      "value": "dev"
    }
  }
}
```

**Note**: The `keyVaultNameSuffix` parameter defaults to the current date (MMDD) to ensure uniqueness.

---

## Step 2: Validate Deployment

### Run Pre-Deployment Validation
```bash
./scripts/validate-keyvault.sh
```

This script checks:
- ✅ Azure CLI is logged in
- ✅ Core infrastructure exists
- ✅ Parameter file is valid
- ✅ No name collision with soft-deleted vaults

### Run What-If Analysis
```bash
./scripts/deploy-keyvault.sh --dry-run
```

Review the planned changes before deploying.

---

## Step 3: Deploy Key Vault

### Execute Deployment
```bash
./scripts/deploy-keyvault.sh
```

**Expected duration**: ~2-3 minutes

### Deployment Output
```
[INFO] Starting Key Vault deployment...
[INFO] Creating resource group: rg-ai-keyvault
[INFO] Deploying Key Vault: kv-ai-lab-0117
[INFO] Creating private endpoint...
[SUCCESS] Deployment completed!

Outputs:
  keyVaultName:      kv-ai-lab-0117
  keyVaultUri:       https://kv-ai-lab-0117.vault.azure.net/
  privateEndpointIp: 10.1.0.5
```

---

## Step 4: Verify Deployment

### 4.1 Check Azure Resources
```bash
# Verify Key Vault exists
az keyvault show \
  --name "kv-ai-lab-0117" \
  --resource-group "rg-ai-keyvault" \
  --query "{name:name, provisioningState:properties.provisioningState}" \
  -o table

# Verify RBAC authorization is enabled
az keyvault show \
  --name "kv-ai-lab-0117" \
  --resource-group "rg-ai-keyvault" \
  --query "properties.enableRbacAuthorization" \
  -o tsv
# Expected: true

# Verify public network access is disabled
az keyvault show \
  --name "kv-ai-lab-0117" \
  --resource-group "rg-ai-keyvault" \
  --query "properties.publicNetworkAccess" \
  -o tsv
# Expected: Disabled
```

### 4.2 Verify Private Endpoint
```bash
# Check private endpoint status
az network private-endpoint show \
  --name "kv-ai-lab-0117-pe" \
  --resource-group "rg-ai-keyvault" \
  --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" \
  -o tsv
# Expected: Approved

# Get private IP
az network private-endpoint show \
  --name "kv-ai-lab-0117-pe" \
  --resource-group "rg-ai-keyvault" \
  --query "customDnsConfigs[0].ipAddresses[0]" \
  -o tsv
# Expected: 10.1.0.x
```

### 4.3 Verify DNS Resolution (Requires VPN)
```bash
# Connect to VPN first, then:
nslookup kv-ai-lab-0117.vault.azure.net

# Expected output:
# Server:  10.1.0.68 (DNS resolver)
# Address: 10.1.0.68
#
# Non-authoritative answer:
# kv-ai-lab-0117.vault.azure.net  canonical name = kv-ai-lab-0117.privatelink.vaultcore.azure.net
# Name:    kv-ai-lab-0117.privatelink.vaultcore.azure.net
# Address: 10.1.0.5
```

---

## Step 5: Grant Access (RBAC)

### Assign Yourself Key Vault Secrets Officer
```bash
# Get your user object ID
USER_ID=$(az ad signed-in-user show --query id -o tsv)

# Get Key Vault resource ID
KV_ID=$(az keyvault show --name "kv-ai-lab-0117" --resource-group "rg-ai-keyvault" --query id -o tsv)

# Assign role
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee "$USER_ID" \
  --scope "$KV_ID"
```

---

## Step 6: Test Secret Operations (Requires VPN)

### Create a Secret
```bash
# Ensure VPN is connected
az keyvault secret set \
  --vault-name "kv-ai-lab-0117" \
  --name "test-secret" \
  --value "Hello from private Key Vault!"
```

### Read the Secret
```bash
az keyvault secret show \
  --vault-name "kv-ai-lab-0117" \
  --name "test-secret" \
  --query "value" \
  -o tsv
# Expected: Hello from private Key Vault!
```

### List Secrets
```bash
az keyvault secret list \
  --vault-name "kv-ai-lab-0117" \
  --query "[].name" \
  -o tsv
```

---

## Using Key Vault References in Bicep

### JSON Parameter File Reference
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "adminPassword": {
      "reference": {
        "keyVault": {
          "id": "/subscriptions/<sub-id>/resourceGroups/rg-ai-keyvault/providers/Microsoft.KeyVault/vaults/kv-ai-lab-0117"
        },
        "secretName": "admin-password"
      }
    }
  }
}
```

### Bicep Parameter File Reference (.bicepparam)
```bicep
using './main.bicep'

param adminPassword = az.getSecret(
  '<subscription-id>',
  'rg-ai-keyvault',
  'kv-ai-lab-0117',
  'admin-password'
)
```

---

## Cleanup

### Delete Key Vault Resources
```bash
./scripts/cleanup-keyvault.sh
```

This script:
1. Deletes the private endpoint
2. Deletes the Key Vault (soft-delete, retained 90 days)
3. Deletes the resource group

### Purge Soft-Deleted Vault (Optional)
```bash
# Only if purge protection is disabled
az keyvault purge --name "kv-ai-lab-0117" --location "eastus2"
```

**Warning**: Purging permanently deletes all secrets and cannot be undone.

---

## Troubleshooting

### Cannot Connect to Key Vault

**Symptom**: `az keyvault secret list` times out or fails

**Check VPN Connection**:
```bash
# Verify you're on the VPN
ip route | grep "10.1.0.0"
# Should show route to 10.1.0.0/24 network
```

**Check DNS Resolution**:
```bash
nslookup kv-ai-lab-0117.vault.azure.net
# Should resolve to 10.1.0.x, NOT public IP
```

### Access Denied (403)

**Symptom**: `ForbiddenByRbac` error

**Solution**: Ensure RBAC role is assigned:
```bash
az role assignment list \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-ai-keyvault/providers/Microsoft.KeyVault/vaults/kv-ai-lab-0117" \
  --query "[].{role:roleDefinitionName, principal:principalName}" \
  -o table
```

### Soft-Deleted Vault Blocking Deployment

**Symptom**: Deployment fails with "vault already exists"

**Solution**: Purge or use different name suffix:
```bash
# Option 1: Purge (if purge protection is off)
az keyvault purge --name "kv-ai-lab-0117" --location "eastus2"

# Option 2: Use different suffix
./scripts/deploy-keyvault.sh --parameter keyVaultNameSuffix=0118
```

---

## Next Steps

1. **Store secrets** for other AI-Lab projects (connection strings, API keys)
2. **Update existing deployments** to use Key Vault references
3. **Review RBAC assignments** for team members
4. **Enable diagnostic logging** for audit trail

## References

- [Azure Key Vault documentation](https://learn.microsoft.com/en-us/azure/key-vault/)
- [Key Vault private endpoints](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service)
- [Key Vault RBAC guide](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [Bicep Key Vault references](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/key-vault-parameter)
