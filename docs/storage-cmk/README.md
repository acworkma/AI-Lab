# Private Azure Storage Account with Customer Managed Key

## Overview

This module enables customer-managed key (CMK) encryption on an existing private Storage Account using a key stored in a separate private Key Vault. Prerequisites:
- Private Key Vault deployed in `rg-ai-keyvault`
- Private Storage Account deployed in `rg-ai-storage`

**Architecture**:
```
┌─────────────────────────────────────────────────────────────────┐
│                        rg-ai-keyvault                           │
│  ┌─────────────────┐         ┌──────────────────────────────┐  │
│  │   Key Vault     │ STORES  │  Encryption Key              │  │
│  │   (existing)    │─────────│  storage-encryption-key      │  │
│  │                 │         │  RSA-4096, P18M rotation     │  │
│  └────────┬────────┘         └──────────────────────────────┘  │
│           │                                                     │
│           │ ROLE: Key Vault Crypto Service Encryption User      │
└───────────│─────────────────────────────────────────────────────┘
            │
            │ GRANTS ACCESS TO
            ▼
┌───────────────────────────────────────────────────────────────────┐
│                        rg-ai-storage                              │
│  ┌─────────────────┐         ┌──────────────────────────────┐   │
│  │ Managed Identity│◄────────│  Storage Account             │   │
│  │ id-stailab*-cmk │  USES   │  stailab* (existing)         │   │
│  └─────────────────┘         │  CMK: Microsoft.Keyvault     │   │
│                              └──────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
```

**Key Components**:
- **Managed Identity**: `id-stailab<suffix>-cmk` - User-assigned identity for Key Vault access
- **Encryption Key**: `storage-encryption-key` - RSA 4096-bit with P18M rotation policy
- **RBAC Role**: Key Vault Crypto Service Encryption User

**Deployment Region**: East US 2

## Prerequisites

### Required Infrastructure (Deployed First)

1. **Core Infrastructure** (`rg-ai-core`):
   - Deploy via `./scripts/deploy-core.sh`
   - Includes: vWAN hub, VPN gateway, shared services VNet, private DNS zones

2. **Private Key Vault** (`rg-ai-keyvault`):
   - Deploy via `./scripts/deploy-keyvault.sh`
   - **Required settings**: Soft-delete enabled, Purge protection enabled
   - Verify: `az keyvault show --name <kv-name> -g rg-ai-keyvault --query "{softDelete:properties.enableSoftDelete, purgeProtection:properties.enablePurgeProtection}"`

3. **Private Storage Account** (`rg-ai-storage`):
   - Deploy via `./scripts/deploy-storage-infra.sh`
   - Storage account name pattern: `stailab<suffix>`

4. **VPN Connection**:
   - Required for DNS resolution and storage access
   - See [VPN client setup guide](../core-infrastructure/vpn-client-setup.md)

### Required Tools

- **Azure CLI** (version 2.50.0 or later)
- **jq** (for JSON parsing in scripts)

### Required Permissions

| Role | Scope | Purpose |
|------|-------|---------|
| Key Vault Contributor | rg-ai-keyvault | Create encryption key |
| User Access Administrator | rg-ai-keyvault | Assign RBAC role to managed identity |
| Contributor | rg-ai-storage | Create managed identity, update storage |

## CMK Deployment

### Step 1: Verify Prerequisites

The deployment script automatically validates prerequisites. Run the check manually:

```bash
# Check Key Vault exists with required settings
az keyvault show --name <kv-name> --resource-group rg-ai-keyvault \
  --query "{name:name, softDelete:properties.enableSoftDelete, purgeProtection:properties.enablePurgeProtection}"

# Check Storage Account exists
az storage account show --name stailab<suffix> --resource-group rg-ai-storage \
  --query "{name:name, publicAccess:publicNetworkAccess, encryption:encryption.keySource}"
```

### Step 2: Configure Parameters

Edit `bicep/storage/main.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "value": "eastus2" },
    "environment": { "value": "dev" },
    "owner": { "value": "your-name" },
    "storageNameSuffix": { "value": "0117" },
    "keyVaultResourceGroupName": { "value": "rg-ai-keyvault" },
    "storageResourceGroupName": { "value": "rg-ai-storage" },
    "keyVaultName": { "value": "" },
    "encryptionKeyName": { "value": "storage-encryption-key" },
    "keySize": { "value": 4096 },
    "keyRotationInterval": { "value": "P18M" },
    "keyExpiryTime": { "value": "P2Y" }
  }
}
```

**Note**: If `keyVaultName` is empty, the script auto-discovers the Key Vault in `rg-ai-keyvault`.

### Step 3: Deploy CMK Encryption

```bash
# Standard deployment with what-if review
./scripts/deploy-storage.sh

# Or skip confirmation for CI/CD
./scripts/deploy-storage.sh --auto-approve
```

The deployment:
1. Validates prerequisites (Key Vault, Storage Account exist)
2. Creates user-assigned managed identity
3. Creates encryption key with rotation policy
4. Assigns Key Vault Crypto Service Encryption User role
5. Updates Storage Account with CMK configuration

### Step 4: Validate Deployment

```bash
# Run validation script
./scripts/validate-storage.sh --deployed
```

Expected output:
```
[✓ PASS] SC-001: CMK encryption enabled (keySource: Microsoft.Keyvault)
[✓ PASS] SC-001: User-assigned identity configured for CMK
[✓ PASS] SC-002: Encryption key exists: storage-encryption-key
[✓ PASS] SC-002: Key size appears to be RSA 4096-bit
[✓ PASS] SR-003: Key rotation interval is P18M (18 months)
[✓ PASS] SC-003: Key Vault Crypto Service Encryption User role assigned
[✓ PASS] SR-004: Public network access disabled
```

## Security

### Customer Managed Key Encryption

The Storage Account uses a customer-managed encryption key (CMK) stored in the private Key Vault. This provides:

- **Organizational Control**: You manage the encryption key lifecycle
- **Key Rotation**: Automatic rotation every 18 months (P18M)
- **Audit Trail**: All key access is logged in Azure Monitor
- **Compliance**: Meets regulatory requirements for key management
- **Versionless URI**: Uses versionless key URI for automatic rotation support

### Key Rotation

Keys are automatically rotated per the configured policy. To manually rotate:

```bash
# Get Key Vault name
KV_NAME=$(az keyvault list -g rg-ai-keyvault --query "[0].name" -o tsv)

# Create new key version
az keyvault key rotate --vault-name $KV_NAME --name storage-encryption-key

# Verify new version
az keyvault key show --vault-name $KV_NAME --name storage-encryption-key --query "key.kid"
```

### Managed Identity

The Storage Account uses a user-assigned managed identity to access the encryption key:
- **Identity Name**: `id-stailab<suffix>-cmk`
- **RBAC Role**: Key Vault Crypto Service Encryption User
- **Permissions**: Wrap/Unwrap key operations only (least privilege)

## Troubleshooting

### Issue: Prerequisites check fails

**Symptom**: Deployment script exits with prerequisite errors

**Solution**:

```bash
# Verify deployment order
# 1. Core: ./scripts/deploy-core.sh
# 2. Key Vault: ./scripts/deploy-keyvault.sh
# 3. Storage: ./scripts/deploy-storage-infra.sh
# 4. CMK: ./scripts/deploy-storage.sh (this script)

# Check Key Vault has required settings
az keyvault show --name <kv-name> -g rg-ai-keyvault \
  --query "{softDelete:properties.enableSoftDelete, purgeProtection:properties.enablePurgeProtection}"
# Both must be true
```

### Issue: "Key Vault Crypto Service Encryption User role not assigned"

**Symptom**: Storage operations fail after CMK enablement

**Solution**:

```bash
# Get managed identity principal ID
IDENTITY_NAME="id-stailab<suffix>-cmk"
PRINCIPAL_ID=$(az identity show -n $IDENTITY_NAME -g rg-ai-storage --query principalId -o tsv)

# Get Key Vault ID
KV_ID=$(az keyvault show -n <kv-name> -g rg-ai-keyvault --query id -o tsv)

# Assign role manually
az role assignment create \
  --assignee-object-id $PRINCIPAL_ID \
  --role "Key Vault Crypto Service Encryption User" \
  --scope $KV_ID
```

### Issue: Storage Account already has CMK from different Key Vault

**Symptom**: Warning during deployment about existing CMK configuration

**Solution**: The deployment will overwrite the existing CMK configuration. If this is unintended:

```bash
# Check current CMK configuration
az storage account show -n stailab<suffix> -g rg-ai-storage \
  --query "encryption.keyvaultproperties"
```

### Issue: "Public endpoints are disabled" error

**Symptom**: Cannot access storage from internet

**Solution**: This is expected - connect via VPN:

```bash
# Verify VPN connection
# Resolve storage via private DNS
nslookup stailab<suffix>.blob.core.windows.net 10.1.0.68
```

### Issue: Key Vault soft-deleted with same name

**Symptom**: Cannot create Key Vault key

**Solution**:

```bash
# Check for soft-deleted Key Vault
az keyvault list-deleted --query "[?name=='<kv-name>']"

# Recover or purge as needed
az keyvault recover --name <kv-name>
# OR
az keyvault purge --name <kv-name>
```

## Usage

### Upload/Download Data (VPN Required)

```bash
STORAGE_NAME="stailab<suffix>"

# Create container
az storage container create --account-name $STORAGE_NAME --name data --auth-mode login

# Upload file
az storage blob upload --account-name $STORAGE_NAME --container-name data \
  --name test.txt --file test.txt --auth-mode login

# Download file
az storage blob download --account-name $STORAGE_NAME --container-name data \
  --name test.txt --file downloaded.txt --auth-mode login
```

### View CMK Status

```bash
# Quick status check
az storage account show -n stailab<suffix> -g rg-ai-storage \
  --query "{keySource:encryption.keySource, keyVault:encryption.keyvaultproperties.keyvaulturi, keyName:encryption.keyvaultproperties.keyname}"

# Full validation
./scripts/validate-storage.sh --deployed
```

## Reference

- [Customer Managed Keys for Azure Storage](https://learn.microsoft.com/azure/storage/common/customer-managed-keys-overview)
- [Configure CMK for Existing Storage Account](https://learn.microsoft.com/azure/storage/common/customer-managed-keys-configure-existing-account)
- [Key Vault Key Rotation](https://learn.microsoft.com/azure/key-vault/keys/how-to-configure-key-rotation)
- [Key Vault Crypto Service Encryption User Role](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#key-vault-crypto-service-encryption-user)

---

**Version**: 2.0.0  
**Last Updated**: 2026-01-17

