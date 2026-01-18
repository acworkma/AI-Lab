# Private Azure Key Vault

Deploy Azure Key Vault with private endpoint connectivity, RBAC authorization, and integration with existing private DNS infrastructure for secure secrets management.

## Overview

This project deploys a standalone Azure Key Vault as an Infrastructure Project following the AI-Lab constitution patterns. Key Vault provides centralized, secure secrets management for all AI lab projects.

**Key Features:**
- ✅ Private endpoint only (no public access)
- ✅ RBAC authorization (modern, no access policies)
- ✅ Soft-delete enabled (90-day retention)
- ✅ DNS integration with existing private DNS zone
- ✅ Bicep Key Vault reference support

**Project Type:** Infrastructure Project (provides capabilities for other projects)

## Prerequisites

### Required Infrastructure
- Core infrastructure deployed (`rg-ai-core`)
- Shared services VNet (`vnet-ai-shared`) with `snet-private-endpoints` subnet
- Private DNS zone `privatelink.vaultcore.azure.net` in `rg-ai-core`
- VPN connection for private endpoint access

### Required Permissions
- **Subscription**: Contributor role
- **VNet**: Network Contributor on `vnet-ai-shared` in `rg-ai-core`

### Tools
- Azure CLI 2.50 or later
- Bicep CLI (bundled with Azure CLI)
- jq (for shell scripts)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    rg-ai-keyvault                               │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                                                            │ │
│  │  ┌──────────────────┐      ┌─────────────────────────────┐│ │
│  │  │    Key Vault     │◄─────│     Private Endpoint        ││ │
│  │  │ kv-ai-lab-<MMDD> │      │  kv-ai-lab-<MMDD>-pe       ││ │
│  │  │                  │      │                             ││ │
│  │  │  • RBAC enabled  │      │  ┌───────────────────────┐  ││ │
│  │  │  • Private only  │      │  │  DNS Zone Group       │  ││ │
│  │  │  • Soft-delete   │      │  │  (auto A-record)      │  ││ │
│  │  └──────────────────┘      │  └───────────┬───────────┘  ││ │
│  │                            └──────────────┼──────────────┘│ │
│  └───────────────────────────────────────────┼───────────────┘ │
└──────────────────────────────────────────────┼─────────────────┘
                                               │
                   References                  │
                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    rg-ai-core (EXISTING)                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Private DNS Zone                  │  Shared Services VNet │  │
│  │  privatelink.vaultcore.azure.net  │  vnet-ai-shared       │  │
│  │                                    │  └─ snet-private-     │  │
│  │  (A record auto-registered)        │     endpoints         │  │
│  │                                    │     10.1.0.0/26       │  │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Deployment

### Quick Start

```bash
# 1. Copy and customize parameter file
cp bicep/keyvault/main.parameters.example.json bicep/keyvault/main.parameters.json
# Edit main.parameters.json with your values

# 2. Validate prerequisites
./scripts/validate-keyvault.sh

# 3. Deploy (with what-if preview)
./scripts/deploy-keyvault.sh

# 4. Verify DNS resolution (requires VPN)
./scripts/validate-keyvault-dns.sh
```

### Deployment Scripts

| Script | Purpose |
|--------|---------|
| `deploy-keyvault.sh` | Deploy Key Vault with what-if preview |
| `validate-keyvault.sh` | Pre/post-deployment validation |
| `validate-keyvault-dns.sh` | DNS resolution verification |
| `cleanup-keyvault.sh` | Delete all Key Vault resources |
| `grant-keyvault-roles.sh` | Assign RBAC roles |

### Script Options

```bash
# Deploy with custom parameter file
./scripts/deploy-keyvault.sh --parameter-file ./custom.parameters.json

# Preview changes only (dry run)
./scripts/deploy-keyvault.sh --dry-run

# Automated deployment (CI/CD)
./scripts/deploy-keyvault.sh --auto-approve

# Validate deployed resources
./scripts/validate-keyvault.sh --deployed
```

## Configuration

### Parameter Reference

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `owner` | Yes | - | Owner identifier for tagging |
| `environment` | No | `dev` | Environment: dev, test, prod |
| `location` | No | `eastus2` | Azure region |
| `keyVaultNameSuffix` | No | `utcNow('MMdd')` | Unique suffix for vault name |
| `resourceGroupName` | No | `rg-ai-keyvault` | Key Vault resource group |
| `coreResourceGroupName` | No | `rg-ai-core` | Core infrastructure RG |
| `vnetName` | No | `vnet-ai-shared` | Shared services VNet |
| `privateEndpointSubnetName` | No | `PrivateEndpointSubnet` | PE subnet |
| `enablePurgeProtection` | No | `false` | Purge protection (enable for prod) |

### RBAC Roles

Key Vault uses Azure RBAC for access control. Common roles:

| Role | Permissions | Use Case |
|------|-------------|----------|
| Key Vault Secrets Officer | CRUD secrets | Developers managing secrets |
| Key Vault Secrets User | Read secrets | Applications consuming secrets |
| Key Vault Administrator | Full management | Infrastructure admins |
| Key Vault Crypto Officer | Key operations | CMK management |

#### Assign Roles

```bash
# Get your user ID
USER_ID=$(az ad signed-in-user show --query id -o tsv)

# Grant Secrets Officer role
./scripts/grant-keyvault-roles.sh \
  --principal-id "$USER_ID" \
  --role secrets-officer

# Grant to service principal
./scripts/grant-keyvault-roles.sh \
  --principal-id "$SP_OBJECT_ID" \
  --role secrets-user \
  --principal-type ServicePrincipal

# List current assignments
./scripts/grant-keyvault-roles.sh --list
```

## Testing

### Pre-Deployment Validation

```bash
./scripts/validate-keyvault.sh
```

Checks:
- ✅ Azure CLI login status
- ✅ Core infrastructure exists
- ✅ Parameter file valid
- ✅ No soft-deleted vault collision
- ✅ Template syntax valid

### Post-Deployment Validation

```bash
./scripts/validate-keyvault.sh --deployed
```

Checks:
- ✅ Key Vault provisioned
- ✅ RBAC authorization enabled (SR-002)
- ✅ Public network access disabled (SR-001)
- ✅ Soft-delete enabled (SR-003)
- ✅ Private endpoint active

### DNS Resolution (Requires VPN)

```bash
./scripts/validate-keyvault-dns.sh
```

Checks:
- ✅ DNS resolves to private IP (10.1.0.x)
- ✅ Resolution time < 100ms (NFR-003)
- ✅ Public access blocked

### Secret Operations Test

```bash
# Create test secret
az keyvault secret set \
  --vault-name "kv-ai-lab-0117" \
  --name "test-secret" \
  --value "test-value"

# Read test secret
az keyvault secret show \
  --vault-name "kv-ai-lab-0117" \
  --name "test-secret" \
  --query "value" -o tsv

# List secrets
az keyvault secret list \
  --vault-name "kv-ai-lab-0117" \
  --query "[].name" -o tsv

# Delete test secret
az keyvault secret delete \
  --vault-name "kv-ai-lab-0117" \
  --name "test-secret"
```

## Cleanup

### Standard Cleanup

```bash
./scripts/cleanup-keyvault.sh
```

This deletes the resource group. The Key Vault enters soft-deleted state for 90 days.

### Full Cleanup (Including Purge)

```bash
./scripts/cleanup-keyvault.sh --purge
```

**Warning**: Purging permanently deletes all secrets. Cannot be undone.

## Using Key Vault References in Bicep

### JSON Parameter File

Reference secrets without exposing values in source control:

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

### Bicep Parameter File (.bicepparam)

```bicep
using './main.bicep'

param adminPassword = az.getSecret(
  '<subscription-id>',
  'rg-ai-keyvault',
  'kv-ai-lab-0117',
  'admin-password'
)
```

### Requirements for Key Vault References

1. Key Vault must have `enabledForTemplateDeployment: true` (enabled by default)
2. Deploying identity needs permissions on the Key Vault
3. See [main.keyvault-ref.parameters.example.json](../../bicep/keyvault/main.keyvault-ref.parameters.example.json) for examples

## Troubleshooting

### Cannot Connect to Key Vault

**Symptom**: Commands timeout or fail with connection errors

**Solution**:
1. Verify VPN connection: `ip route | grep "10.1.0.0"`
2. Check DNS resolution: `nslookup kv-ai-lab-0117.vault.azure.net`
3. Ensure DNS resolver is working in core infrastructure

### Access Denied (403 Forbidden)

**Symptom**: `ForbiddenByRbac` error

**Solution**:
```bash
# Check your role assignments
az role assignment list \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-ai-keyvault/providers/Microsoft.KeyVault/vaults/<vault-name>" \
  --query "[].{role:roleDefinitionName, principal:principalName}" \
  -o table

# Grant necessary role
./scripts/grant-keyvault-roles.sh --principal-id "$(az ad signed-in-user show --query id -o tsv)" --role secrets-officer
```

### Deployment Fails - Vault Already Exists

**Symptom**: "Vault already exists" error during deployment

**Cause**: A soft-deleted vault with the same name exists

**Solution**:
```bash
# Option 1: Purge the soft-deleted vault
az keyvault purge --name "kv-ai-lab-0117" --location "eastus2"

# Option 2: Use different name suffix in parameters
# Edit main.parameters.json and set a different keyVaultNameSuffix
```

### DNS Resolves to Public IP

**Symptom**: `nslookup` returns public IP instead of 10.1.0.x

**Solution**:
1. Ensure VPN is connected
2. Check VPN DNS settings point to Azure DNS resolver
3. Verify private DNS zone is linked to VNet

### Bicep Reference Fails

**Symptom**: Deployment using Key Vault reference fails

**Solution**:
1. Verify `enabledForTemplateDeployment: true` on Key Vault
2. Ensure deploying identity has `Key Vault Secrets User` role minimum
3. Check secret name and Key Vault ID are correct

## References

- [Azure Key Vault documentation](https://learn.microsoft.com/en-us/azure/key-vault/)
- [Private endpoints for Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service)
- [Key Vault RBAC guide](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [Bicep Key Vault references](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/key-vault-parameter)
- [AI-Lab Constitution](../../.specify/memory/constitution.md)
