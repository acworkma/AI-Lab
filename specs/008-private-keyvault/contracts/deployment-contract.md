# Deployment Contract: Private Azure Key Vault

**Feature**: 008-private-keyvault  
**Phase**: 1 - Design  
**Date**: 2025-01-17

## Overview

This document defines the Bicep module interface contract for deploying Azure Key Vault with private endpoint. It establishes the expected parameters, outputs, and behaviors that consumers can rely on.

---

## Module: `bicep/modules/key-vault.bicep`

### Purpose
Reusable Bicep module for creating Azure Key Vault with:
- RBAC authorization (no access policies)
- Private endpoint connectivity
- Soft-delete enabled
- Public network access disabled

### Scope
Resource Group

---

## Parameters

### Required Parameters

| Parameter | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `keyVaultName` | `string` | Name of the Key Vault | 3-24 chars, alphanumeric + hyphens |
| `location` | `string` | Azure region for deployment | Valid Azure region |
| `privateEndpointSubnetId` | `string` | Resource ID of subnet for private endpoint | Must be valid subnet ID |
| `privateDnsZoneId` | `string` | Resource ID of `privatelink.vaultcore.azure.net` zone | Must exist |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `skuName` | `'standard' \| 'premium'` | `'standard'` | Key Vault SKU |
| `enablePurgeProtection` | `bool` | `false` | Enable purge protection |
| `softDeleteRetentionDays` | `int` | `90` | Soft-delete retention (7-90) |
| `enabledForTemplateDeployment` | `bool` | `true` | Allow Bicep/ARM references |
| `enabledForDeployment` | `bool` | `false` | Allow VM certificate retrieval |
| `enabledForDiskEncryption` | `bool` | `false` | Allow Azure Disk Encryption |
| `tags` | `object` | `{}` | Resource tags |

---

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `name` | `string` | Key Vault name |
| `id` | `string` | Key Vault resource ID |
| `uri` | `string` | Key Vault URI (https://...) |
| `privateEndpointId` | `string` | Private endpoint resource ID |
| `privateEndpointIp` | `string` | Private IP address |

---

## Usage Example

### Basic Usage
```bicep
module keyVault 'modules/key-vault.bicep' = {
  name: 'deploy-key-vault'
  scope: resourceGroup('rg-ai-keyvault')
  params: {
    keyVaultName: 'kv-ai-lab-0117'
    location: 'eastus2'
    privateEndpointSubnetId: subnet.id
    privateDnsZoneId: privateDnsZone.id
    tags: {
      environment: 'dev'
      owner: 'infrastructure-team'
    }
  }
}
```

### Production Usage (with Purge Protection)
```bicep
module keyVault 'modules/key-vault.bicep' = {
  name: 'deploy-key-vault-prod'
  scope: resourceGroup('rg-ai-keyvault')
  params: {
    keyVaultName: 'kv-ai-prod-0117'
    location: 'eastus2'
    privateEndpointSubnetId: subnet.id
    privateDnsZoneId: privateDnsZone.id
    enablePurgeProtection: true  // CANNOT be disabled once enabled
    skuName: 'premium'           // If HSM keys needed
    tags: {
      environment: 'prod'
      owner: 'infrastructure-team'
    }
  }
}
```

---

## Orchestration: `bicep/keyvault/main.bicep`

### Purpose
Subscription-scoped orchestration template that:
1. Creates dedicated resource group `rg-ai-keyvault`
2. Retrieves references to existing core infrastructure
3. Deploys Key Vault module with private endpoint

### Scope
Subscription

---

## Orchestration Parameters

### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `owner` | `string` | Owner identifier for tagging |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | `string` | `'eastus2'` | Azure region |
| `environment` | `'dev' \| 'test' \| 'prod'` | `'dev'` | Environment tag |
| `keyVaultNameSuffix` | `string` | `utcNow('MMdd')` | Unique suffix |
| `resourceGroupName` | `string` | `'rg-ai-keyvault'` | Key Vault RG |
| `coreResourceGroupName` | `string` | `'rg-ai-core'` | Core infrastructure RG |
| `vnetName` | `string` | `'vnet-ai-shared'` | Shared services VNet |
| `privateEndpointSubnetName` | `string` | `'PrivateEndpointSubnet'` | PE subnet |
| `privateDnsZoneName` | `string` | `'privatelink.vaultcore.azure.net'` | DNS zone |
| `enablePurgeProtection` | `bool` | `false` | Enable purge protection |
| `deployedBy` | `string` | `'manual'` | Deployment method tag |

---

## Orchestration Outputs

| Output | Type | Description |
|--------|------|-------------|
| `resourceGroupName` | `string` | Created resource group name |
| `keyVaultName` | `string` | Key Vault name |
| `keyVaultUri` | `string` | Key Vault URI |
| `keyVaultId` | `string` | Key Vault resource ID |
| `privateEndpointIp` | `string` | Private IP for DNS verification |

---

## Parameter File: `main.parameters.json`

### Example Configuration
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "owner": {
      "value": "infrastructure-team"
    },
    "environment": {
      "value": "dev"
    },
    "keyVaultNameSuffix": {
      "value": "0117"
    }
  }
}
```

---

## Behaviors

### Idempotent Deployment
- Re-running deployment with same parameters should succeed
- Key Vault properties will be updated if changed
- Private endpoint will be recreated only if subnet changes

### Soft-Delete Handling
- If Key Vault with same name exists in soft-deleted state, deployment will **fail**
- Use unique suffix (date-based) to avoid collision
- Manually purge soft-deleted vault if reusing name is required

### DNS Registration
- Private endpoint automatically creates A record in linked DNS zone
- Record format: `<vault-name>.privatelink.vaultcore.azure.net`
- Propagation typically completes within 1-2 minutes

---

## Validation Script: `scripts/validate-keyvault.sh`

### Pre-Deployment Checks
1. Azure CLI logged in
2. Subscription set correctly
3. Core infrastructure exists (VNet, DNS zone)
4. Parameter file exists and is valid
5. No soft-deleted vault with same name

### Post-Deployment Checks
1. Key Vault exists in resource group
2. Public network access is disabled
3. RBAC authorization is enabled
4. Private endpoint is provisioned
5. DNS resolution returns private IP

---

## Deployment Script: `scripts/deploy-keyvault.sh`

### Usage
```bash
# Standard deployment
./scripts/deploy-keyvault.sh

# Custom parameter file
./scripts/deploy-keyvault.sh --parameter-file bicep/keyvault/main.parameters.prod.json

# Skip what-if (not recommended)
./scripts/deploy-keyvault.sh --skip-whatif

# Automated deployment (CI/CD)
./scripts/deploy-keyvault.sh --auto-approve
```

### Exit Codes
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Prerequisites check failed |
| 2 | What-if analysis failed |
| 3 | Deployment failed |
| 4 | Post-deployment validation failed |

---

## Key Vault Reference Pattern

### For Other Bicep Deployments

#### JSON Parameter File
```json
{
  "parameters": {
    "secretValue": {
      "reference": {
        "keyVault": {
          "id": "[outputs.keyVaultId]"
        },
        "secretName": "my-secret-name"
      }
    }
  }
}
```

#### Bicep Parameter File (.bicepparam)
```bicep
param secretValue = az.getSecret(
  '<subscription-id>',
  'rg-ai-keyvault',
  '<keyVaultName>',
  'my-secret-name'
)
```

### Permissions Required
- Deploying identity needs `Microsoft.KeyVault/vaults/deploy/action`
- Key Vault must have `enabledForTemplateDeployment: true`
