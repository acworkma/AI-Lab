# Quickstart: Deploy Storage Account with Customer Managed Keys

**Feature**: 005-storage-cmk  
**Audience**: Engineers deploying the storage CMK lab  
**Time**: 15-20 minutes  
**Difficulty**: Intermediate

## Overview

This quickstart guides you through deploying a production-ready Azure Storage Account with customer-managed encryption keys (CMK) on a private endpoint. By the end, you'll have:

- ✅ Storage account encrypted with keys from Azure Key Vault
- ✅ Private endpoint access only (no public access)
- ✅ Managed identity authentication (no shared access keys)
- ✅ Automatic encryption key rotation every 90 days
- ✅ Diagnostic logging to Log Analytics

**Architecture**:
```
User → VPN Client → P2S Gateway → Shared Services VNet 
     → Private Endpoint → Storage Account (CMK encrypted)
```

---

## Prerequisites

### 1. Core Infrastructure Deployed

You must have the core infrastructure running:

```bash
# Verify core resources exist
az group show -n rg-ai-core
az network vwan show -n vwan-ai -g rg-ai-core
az keyvault show -n kv-ai-core -g rg-ai-core
az network private-dns-zone show -n privatelink.blob.core.windows.net -g rg-ai-core
```

If any command fails, deploy core infrastructure first:
```bash
cd /path/to/AI-Lab
./scripts/deploy-core.sh
```

See [docs/core-infrastructure/README.md](../../docs/core-infrastructure/README.md) for details.

---

### 2. VPN Connection Established

You need VPN access to test private endpoint connectivity:

1. **Download VPN client**: Follow [docs/core-infrastructure/vpn-client-setup.md](../../docs/core-infrastructure/vpn-client-setup.md)
2. **Connect to VPN**: Ensure you can reach internal IPs (e.g., `ping 10.1.0.68`)
3. **Verify DNS resolution**:
   ```bash
   nslookup kv-ai-core.vault.azure.net 10.1.0.68
   # Should return private IP (10.1.x.x)
   ```

---

### 3. Azure Permissions

Required roles:

| Scope | Required Role | Purpose |
|-------|--------------|---------|
| Subscription | `Contributor` | Create rg-ai-storage resource group |
| rg-ai-core | `Reader` | Reference VNet, DNS zone, Key Vault |
| rg-ai-core (Key Vault) | `Key Vault Administrator` | Create encryption key, assign RBAC |

**Verify permissions**:
```bash
# Check subscription access
az role assignment list --assignee $(az account show --query user.name -o tsv) \
  --scope /subscriptions/$(az account show --query id -o tsv) \
  --query "[?roleDefinitionName=='Contributor'].roleDefinitionName" -o tsv

# Check Key Vault access
az role assignment list --assignee $(az account show --query user.name -o tsv) \
  --scope $(az keyvault show -n kv-ai-core -g rg-ai-core --query id -o tsv) \
  --query "[?roleDefinitionName=='Key Vault Administrator'].roleDefinitionName" -o tsv
```

If missing, request access from your Azure admin.

---

### 4. Tools Installed

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) ≥ 2.50.0
- [Bicep CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install) ≥ 0.20.0 (installed with Azure CLI)
- [Git](https://git-scm.com/) (for version control)

**Verify versions**:
```bash
az version --query '{"azure-cli": "azure-cli", "bicep": "extensions.bicep"}' -o table
git --version
```

---

## Step 1: Clone and Configure

### 1.1 Clone Repository

```bash
git clone https://github.com/yourusername/AI-Lab.git
cd AI-Lab
```

### 1.2 Checkout Feature Branch

```bash
git checkout 005-storage-cmk
```

### 1.3 Copy Parameter Template

```bash
cp bicep/storage/main.parameters.example.json bicep/storage/main.parameters.json
```

### 1.4 Edit Parameters

Open `bicep/storage/main.parameters.json` and customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "storageAccountName": {
      "value": "stailab001"  // ← CHANGE: Must be globally unique (3-24 chars, lowercase/numbers)
    },
    "location": {
      "value": "eastus"      // ← CHANGE: Match your core infrastructure region
    }
  }
}
```

**Storage account naming**:
- **Valid**: `stailab001`, `staiprod02`, `stmyuniquename`
- **Invalid**: `st-ailab` (no hyphens), `StAiLab` (no uppercase), `st` (too short)

**Check name availability**:
```bash
az storage account check-name --name stailab001
# Output: "nameAvailable": true or false
```

---

## Step 2: Validate Deployment

### 2.1 Template Validation

```bash
./scripts/validate-storage.sh
```

Expected output:
```
✓ Template syntax valid
✓ Parameters schema valid
✓ Core infrastructure dependencies verified
✓ Permissions check passed
```

If validation fails, see [Troubleshooting](#troubleshooting) section.

---

### 2.2 What-If Analysis

Preview changes before deploying:

```bash
az deployment sub what-if \
  --location eastus \
  --template-file bicep/storage/main.bicep \
  --parameters @bicep/storage/main.parameters.json
```

Review the output:
```
Scope: /subscriptions/{sub-id}

+ Microsoft.Resources/resourceGroups/rg-ai-storage
  location: eastus

Scope: /subscriptions/{sub-id}/resourceGroups/rg-ai-storage

+ Microsoft.ManagedIdentity/userAssignedIdentities/id-storage-cmk-*
+ Microsoft.Storage/storageAccounts/stailab001
+ Microsoft.Network/privateEndpoints/pe-storage-blob-*

Scope: /subscriptions/{sub-id}/resourceGroups/rg-ai-core

+ Microsoft.KeyVault/vaults/kv-ai-core/keys/storage-encryption-key
+ Microsoft.Authorization/roleAssignments/*

Resource changes: 5 to create
```

---

## Step 3: Deploy Storage Account

### 3.1 Run Deployment Script

```bash
./scripts/deploy-storage.sh
```

Deployment takes approximately **5-8 minutes**. You'll see progress:

```
[2025-01-22 10:00:00] Starting storage account deployment...
[2025-01-22 10:00:05] ✓ Creating resource group rg-ai-storage
[2025-01-22 10:00:30] ✓ Deploying managed identity
[2025-01-22 10:01:00] ✓ Creating encryption key in Key Vault
[2025-01-22 10:01:30] ✓ Assigning RBAC permissions
[2025-01-22 10:02:00] ✓ Deploying storage account with CMK
[2025-01-22 10:04:00] ✓ Configuring private endpoint
[2025-01-22 10:05:00] ✓ Registering DNS record
[2025-01-22 10:05:30] ✓ Enabling diagnostic logging

Deployment complete!

Storage Account Name: stailab001
Private IP Address: 10.1.4.5
Blob Endpoint: https://stailab001.blob.core.windows.net
```

---

### 3.2 Verify Deployment

The script automatically runs verification checks:

```bash
# Manually verify if needed
az storage account show -n stailab001 -g rg-ai-storage \
  --query "{name:name, encryption:encryption.keySource, publicAccess:publicNetworkAccess}" \
  -o table
```

Expected output:
```
Name         Encryption           PublicAccess
-----------  -------------------  -------------
stailab001   Microsoft.Keyvault   Disabled
```

---

## Step 4: Test Private Endpoint Access

### 4.1 Connect to VPN

If not already connected:
1. Open Azure VPN Client
2. Connect to `P2S VPN - AI Lab`
3. Wait for "Connected" status

### 4.2 Verify DNS Resolution

From your VPN-connected machine:

```bash
nslookup stailab001.blob.core.windows.net 10.1.0.68
```

Expected output:
```
Server:  10.1.0.68
Address: 10.1.0.68#53

Name:    stailab001.blob.core.windows.net
Address: 10.1.4.5  # ← Private IP (10.1.x.x range)
```

❌ **If you see a public IP** (e.g., 52.x.x.x), DNS is not configured correctly. See [Troubleshooting](#dns-not-resolving-to-private-ip).

---

### 4.3 Test Blob Upload (Azure CLI)

```bash
# Assign yourself "Storage Blob Data Contributor" role
STORAGE_ID=$(az storage account show -n stailab001 -g rg-ai-storage --query id -o tsv)
az role assignment create \
  --assignee $(az account show --query user.name -o tsv) \
  --role "Storage Blob Data Contributor" \
  --scope $STORAGE_ID

# Create a test container
az storage container create \
  --account-name stailab001 \
  --name test-container \
  --auth-mode login

# Upload a test file
echo "Hello from private endpoint!" > test.txt
az storage blob upload \
  --account-name stailab001 \
  --container-name test-container \
  --name test.txt \
  --file test.txt \
  --auth-mode login

# Verify upload
az storage blob list \
  --account-name stailab001 \
  --container-name test-container \
  --auth-mode login \
  --query "[].name" -o table
```

Expected output:
```
Result
------
test.txt
```

---

### 4.4 Test Access Without VPN (Should Fail)

**Disconnect from VPN**, then try:

```bash
az storage blob list \
  --account-name stailab001 \
  --container-name test-container \
  --auth-mode login
```

Expected error:
```
AuthorizationFailure: This request is not authorized to perform this operation.
Status Code: 403
Error Code: AuthorizationFailure
```

✅ **This error is expected!** Public access is disabled, confirming security configuration.

**Reconnect to VPN** to restore access.

---

## Step 5: Verify Security Configuration

### 5.1 Check CMK Encryption

```bash
az storage account show -n stailab001 -g rg-ai-core \
  --query "{keySource: encryption.keySource, keyVaultUri: encryption.keyvaultproperties.keyvaulturi, keyName: encryption.keyvaultproperties.keyname}" \
  -o table
```

Expected output:
```
KeySource            KeyVaultUri                              KeyName
-------------------  ---------------------------------------  ----------------------
Microsoft.Keyvault   https://kv-ai-core.vault.azure.net/      storage-encryption-key
```

---

### 5.2 Check Managed Identity RBAC

```bash
# Get managed identity principal ID
PRINCIPAL_ID=$(az identity show \
  -n id-storage-cmk-* \
  -g rg-ai-storage \
  --query principalId -o tsv)

# Verify Key Vault role assignment
az role assignment list \
  --assignee $PRINCIPAL_ID \
  --scope $(az keyvault show -n kv-ai-core -g rg-ai-core --query id -o tsv) \
  --query "[].{Role:roleDefinitionName, Scope:scope}" \
  -o table
```

Expected output:
```
Role                                      Scope
----------------------------------------  -------------------------------------------------
Key Vault Crypto Service Encryption User  /subscriptions/{sub}/resourceGroups/rg-ai-core/...
```

---

### 5.3 Check Network Security

```bash
az storage account show -n stailab001 -g rg-ai-storage \
  --query "{publicNetworkAccess: publicNetworkAccess, allowBlobPublicAccess: allowBlobPublicAccess, allowSharedKeyAccess: allowSharedKeyAccess, minimumTlsVersion: minimumTlsVersion}" \
  -o table
```

Expected output:
```
PublicNetworkAccess  AllowBlobPublicAccess  AllowSharedKeyAccess  MinimumTlsVersion
-------------------  ---------------------  --------------------  ------------------
Disabled             False                  False                 TLS1_2
```

All values should be in their most secure state:
- ✅ Public network access: Disabled
- ✅ Anonymous blob access: Disabled
- ✅ Shared key access: Disabled (Entra ID only)
- ✅ TLS version: 1.2 or higher

---

## Step 6: View Diagnostic Logs

### 6.1 Query Storage Activity

```bash
# Replace with your Log Analytics workspace ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  -n law-ai-core -g rg-ai-core --query customerId -o tsv)

# Query recent storage operations
az monitor log-analytics query \
  -w $WORKSPACE_ID \
  --analytics-query "StorageAccountLogs | where TimeGenerated > ago(1h) | project TimeGenerated, OperationName, StatusCode, CallerIpAddress | limit 20" \
  -o table
```

Expected output:
```
TimeGenerated         OperationName      StatusCode  CallerIpAddress
--------------------  -----------------  ----------  ---------------
2025-01-22T10:15:00Z  PutBlob            201         10.1.4.100
2025-01-22T10:14:30Z  CreateContainer    201         10.1.4.100
```

Notice `CallerIpAddress` is from VNet private range (`10.1.x.x`), not public IP.

---

### 6.2 Monitor CMK Operations

```bash
az monitor log-analytics query \
  -w $WORKSPACE_ID \
  --analytics-query "StorageAccountLogs | where OperationName contains 'CustomerKey' | project TimeGenerated, OperationName, StatusCode" \
  -o table
```

This tracks encryption key access (should see operations during storage account creation).

---

## Next Steps

### Explore Advanced Features

1. **Enable Blob Versioning**:
   ```bash
   az storage account blob-service-properties update \
     --account-name stailab001 \
     --resource-group rg-ai-storage \
     --enable-versioning true
   ```

2. **Configure Lifecycle Policies**:
   - Archive old blobs to cool/archive tiers
   - See [Lifecycle management docs](https://learn.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-overview)

3. **Test from Applications**:
   - Python: [Azure Storage SDK](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-quickstart-blobs-python)
   - .NET: [Azure Storage SDK](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-quickstart-blobs-dotnet)
   - Use managed identity or Entra ID auth (no storage keys)

4. **Monitor Key Rotation**:
   ```bash
   az keyvault key show \
     --vault-name kv-ai-core \
     --name storage-encryption-key \
     --query "{version: key.kid, created: attributes.created, rotationPolicy: rotationPolicy.lifetimeActions[0].trigger}"
   ```

### Reference Documentation

- [Full documentation](../../docs/storage/README.md)
- [Troubleshooting guide](../../docs/storage/README.md#troubleshooting)
- [Feature specification](../specs/005-storage-cmk/spec.md)
- [Data model](./data-model.md)
- [Deployment contract](./contracts/deployment-contract.md)

---

## Cleanup

### Remove Storage Resources (Keep Core Infrastructure)

```bash
# Delete storage resource group
az group delete -n rg-ai-storage --yes --no-wait

# Resources deleted:
# - Storage account (including all blob data)
# - Private endpoint (DNS auto-cleaned)
# - Managed identity
# - Diagnostic settings

# Resources NOT deleted:
# - Core infrastructure (VPN, VNet, Key Vault, DNS zones)
# - Encryption key in Key Vault (orphaned but harmless)
```

**Verify deletion**:
```bash
az group show -n rg-ai-storage
# Expected: ResourceGroupNotFound error
```

---

### Full Cleanup (Including Core Infrastructure)

⚠️ **WARNING**: This removes ALL lab resources (core + storage)

```bash
./scripts/cleanup-core.sh
```

---

## Troubleshooting

### Issue: Storage Account Name Unavailable

**Error**:
```
StorageAccountAlreadyTaken: The storage account named 'stailab001' is already taken.
```

**Solution**:
```bash
# Check name availability
az storage account check-name --name stailab001

# Try different name
# Edit bicep/storage/main.parameters.json:
# "storageAccountName": { "value": "stailab002" }

# Redeploy
./scripts/deploy-storage.sh
```

---

### Issue: DNS Not Resolving to Private IP

**Symptom**:
```bash
nslookup stailab001.blob.core.windows.net
# Returns public IP (52.x.x.x) instead of private IP (10.1.x.x)
```

**Solutions**:

1. **Check VPN connection**:
   ```bash
   # Verify DNS resolver reachable
   ping 10.1.0.68
   ```
   If unreachable, reconnect VPN.

2. **Check DNS server configuration**:
   ```bash
   # Windows
   ipconfig /all | findstr "DNS Servers"
   
   # macOS/Linux
   cat /etc/resolv.conf
   ```
   Should show `10.1.0.68` as primary DNS.

3. **Clear DNS cache**:
   ```bash
   # Windows
   ipconfig /flushdns
   
   # macOS
   sudo dscacheutil -flushcache
   
   # Linux
   sudo systemd-resolve --flush-caches
   ```

4. **Verify private DNS zone configuration**:
   ```bash
   az network private-dns zone show \
     -n privatelink.blob.core.windows.net \
     -g rg-ai-core
   
   az network private-dns link vnet list \
     -g rg-ai-core \
     -z privatelink.blob.core.windows.net \
     -o table
   ```

---

### Issue: Deployment Fails with "AuthorizationFailed"

**Error**:
```
AuthorizationFailed: The client '...' does not have authorization to perform action 'Microsoft.KeyVault/vaults/keys/write'
```

**Solution**:

You need `Key Vault Administrator` role on the Key Vault:

```bash
# Get your user principal ID
USER_ID=$(az ad signed-in-user show --query id -o tsv)

# Assign role
az role assignment create \
  --assignee $USER_ID \
  --role "Key Vault Administrator" \
  --scope $(az keyvault show -n kv-ai-core -g rg-ai-core --query id -o tsv)

# Wait 5 minutes for RBAC propagation, then retry deployment
sleep 300
./scripts/deploy-storage.sh
```

---

### Issue: Blob Upload Fails with "PublicAccessNotPermitted"

**Error**:
```
PublicAccessNotPermitted: Public access is not permitted on this storage account.
```

**Solution**:

This error is expected when not connected to VPN. Ensure:

1. **VPN is connected**:
   ```bash
   # Test internal connectivity
   ping 10.1.0.68
   ```

2. **DNS resolves to private IP**:
   ```bash
   nslookup stailab001.blob.core.windows.net 10.1.0.68
   # Should return 10.1.x.x (private IP)
   ```

3. **Retry blob operation** (should succeed now).

---

### Issue: "Forbidden" Error Despite RBAC Assignment

**Error**:
```
Forbidden: The user or service principal does not have the required permissions.
```

**Solution**:

RBAC assignments can take 5-10 minutes to propagate. Wait and retry:

```bash
# Check role assignment exists
az role assignment list \
  --assignee $(az account show --query user.name -o tsv) \
  --scope $(az storage account show -n stailab001 -g rg-ai-storage --query id -o tsv) \
  -o table

# If missing, assign role
az role assignment create \
  --assignee $(az account show --query user.name -o tsv) \
  --role "Storage Blob Data Contributor" \
  --scope $(az storage account show -n stailab001 -g rg-ai-storage --query id -o tsv)

# Wait for propagation
sleep 600  # 10 minutes

# Retry operation
```

---

### Issue: Core Infrastructure Not Deployed

**Error during validation**:
```
ResourceNotFound: Resource group 'rg-ai-core' could not be found.
```

**Solution**:

Deploy core infrastructure first:

```bash
cd /path/to/AI-Lab
./scripts/deploy-core.sh
```

Wait for completion (30-45 minutes), then retry storage deployment.

---

## FAQ

**Q: Can I deploy multiple storage accounts?**

A: Yes. Change `storageAccountName` parameter to unique name (e.g., `stailab002`, `stailab003`). Each deployment creates a separate resource set in `rg-ai-storage`.

**Q: Can I access from public internet?**

A: No. Public access is intentionally disabled (`publicNetworkAccess: Disabled`). You must use VPN → private endpoint access path.

**Q: How much does this cost?**

A: Approximate monthly costs (East US region):
- Storage account (Standard_LRS, 10 GB): ~$0.20
- Private endpoint: ~$7.20
- Key Vault key operations: ~$0.03
- **Total: ~$7.50/month** (excluding data transfer)

**Q: Can I use this in production?**

A: Yes, but consider:
- Change SKU to `Standard_ZRS` or `Standard_GRS` for higher availability
- Increase key rotation frequency (60 days instead of 90)
- Enable blob versioning and soft delete with longer retention
- Set up alerts in Log Analytics

**Q: How do I rotate the encryption key manually?**

A: Keys rotate automatically every 90 days. For manual rotation:
```bash
az keyvault key rotate \
  --vault-name kv-ai-core \
  --name storage-encryption-key
```

Storage account detects new version and updates automatically.

---

## Support

- **Documentation Issues**: Open GitHub issue with tag `docs`
- **Deployment Failures**: Check [docs/storage/README.md#troubleshooting](../../docs/storage/README.md#troubleshooting)
- **Architecture Questions**: See [feature specification](../spec.md)

