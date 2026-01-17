# Quickstart: Storage CMK Refactor

**Feature**: 010-storage-cmk-refactor  
**Time to Complete**: ~5 minutes  
**Prerequisites**: 008-private-keyvault and 009-private-storage deployed

## Overview

This guide enables Customer-Managed Key (CMK) encryption on an existing private Storage Account using a key from the existing private Key Vault.

## Prerequisites Checklist

Before starting, verify these resources exist:

```bash
# Check Key Vault exists
az keyvault show --name kv-ai-lab-0117 --resource-group rg-ai-keyvault --query name -o tsv

# Check Storage Account exists  
az storage account show --name stailab0117 --resource-group rg-ai-storage --query name -o tsv

# Verify Key Vault has required security settings
az keyvault show --name kv-ai-lab-0117 --query '{softDelete:properties.enableSoftDelete, purgeProtection:properties.enablePurgeProtection}'
```

Expected output:
```json
{
  "softDelete": true,
  "purgeProtection": true
}
```

## Quick Deploy

### Step 1: Run What-If Validation

```bash
cd /home/adworkma/AI-Lab
./scripts/deploy-storage.sh --what-if
```

This shows:
- Managed identity creation
- Encryption key creation in Key Vault
- RBAC role assignment
- Storage account encryption update

### Step 2: Deploy CMK

```bash
./scripts/deploy-storage.sh
```

Deployment creates:
1. User-assigned managed identity `id-stailab0117-cmk`
2. RSA-4096 encryption key `storage-encryption-key`
3. Role assignment (Key Vault Crypto Service Encryption User)
4. Updates storage account encryption to use CMK

### Step 3: Validate CMK

```bash
./scripts/validate-storage.sh
```

Expected output includes:
```
✓ Storage Account: stailab0117
✓ Encryption: Microsoft.Keyvault (CMK)
✓ Key Name: storage-encryption-key
✓ Key Vault: kv-ai-lab-0117
✓ Managed Identity: id-stailab0117-cmk
```

## Test CMK is Working

### Upload a Test Blob

```bash
# Connect to VPN first, then:
az storage blob upload \
  --account-name stailab0117 \
  --container-name test \
  --name cmk-test.txt \
  --data "CMK encryption test" \
  --auth-mode login
```

### Verify Encryption

```bash
# Check storage account encryption settings
az storage account show \
  --name stailab0117 \
  --resource-group rg-ai-storage \
  --query encryption
```

Should show:
```json
{
  "keySource": "Microsoft.Keyvault",
  "keyVaultProperties": {
    "keyName": "storage-encryption-key",
    "keyVaultUri": "https://kv-ai-lab-0117.vault.azure.net"
  }
}
```

## Troubleshooting

### "Key Vault not found"
Deploy Key Vault first:
```bash
./scripts/deploy-keyvault.sh
```

### "Storage Account not found"
Deploy Storage Account first:
```bash
./scripts/deploy-storage-infra.sh
```

### "Insufficient permissions for role assignment"
You need Owner or User Access Administrator role on rg-ai-keyvault:
```bash
az role assignment create \
  --role "User Access Administrator" \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope /subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-ai-keyvault
```

### "Key Vault purge protection not enabled"
CMK requires purge protection. Enable it (irreversible):
```bash
az keyvault update --name kv-ai-lab-0117 --enable-purge-protection true
```

## Next Steps

- View key rotation policy: `az keyvault key rotation-policy show --vault-name kv-ai-lab-0117 --name storage-encryption-key`
- Manual key rotation: `az keyvault key rotate --vault-name kv-ai-lab-0117 --name storage-encryption-key`
- Review [docs/storage/README.md](../../docs/storage/README.md) for full documentation
