# Deployment Contract: Private Azure Storage Account Infrastructure

**Feature**: 009-private-storage  
**Phase**: 1 - Design & Contracts  
**Date**: 2026-01-17

## Overview

This contract defines the interface for deploying the Private Azure Storage Account infrastructure. It specifies inputs, outputs, and behaviors that the implementation must satisfy.

---

## Bicep Module: storage-account.bicep

**Path**: `bicep/modules/storage-account.bicep`

### Parameters

```bicep
@description('Azure region for deployment')
param location string = 'eastus2'

@description('Environment tag value')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Owner tag value - required')
param owner string

@description('Unique suffix for storage account name (default: MMDD)')
param storageNameSuffix string = utcNow('MMdd')

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param skuName string = 'Standard_LRS'

@description('Enable blob soft-delete')
param enableBlobSoftDelete bool = true

@description('Soft-delete retention in days')
@minValue(1)
@maxValue(365)
param softDeleteRetentionDays int = 7

@description('Resource ID of subnet for private endpoint')
param privateEndpointSubnetId string

@description('Resource ID of privatelink.blob.core.windows.net DNS zone')
param privateDnsZoneId string

@description('Principal ID to assign Storage Blob Data Contributor role (optional)')
param adminPrincipalId string = ''
```

### Outputs

```bicep
@description('Resource ID of the storage account')
output storageAccountId string = storageAccount.id

@description('Name of the storage account')
output storageAccountName string = storageAccount.name

@description('Blob service endpoint URL')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Resource ID of the private endpoint')
output privateEndpointId string = privateEndpoint.id

@description('Private IP address of the private endpoint')
output privateIpAddress string = privateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
```

### Behavior Contract

| Behavior | Requirement |
|----------|-------------|
| **Naming** | Storage account name = `stailab${storageNameSuffix}` |
| **RBAC** | `allowSharedKeyAccess` MUST be `false` |
| **TLS** | `minimumTlsVersion` MUST be `TLS1_2` |
| **Transfer** | `supportsHttpsTrafficOnly` MUST be `true` |
| **Network** | `publicNetworkAccess` MUST be `Disabled` |
| **Private Endpoint** | GroupIds MUST include `blob` |
| **DNS** | Zone group MUST link to provided DNS zone ID |
| **Soft-Delete** | Configurable via parameters (default enabled, 7 days) |
| **RBAC Assignment** | If `adminPrincipalId` provided, assign Storage Blob Data Contributor |

---

## Orchestration Template: main.bicep

**Path**: `bicep/storage-infra/main.bicep`

### Deployment Scope

```bicep
targetScope = 'subscription'
```

### Parameters

```bicep
@description('Azure region for deployment')
param location string = 'eastus2'

@description('Environment tag value')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Owner tag value')
param owner string

@description('Unique suffix for storage account name')
param storageNameSuffix string = utcNow('MMdd')

@description('Core infrastructure resource group name')
param coreResourceGroupName string = 'rg-ai-core'

@description('Shared services VNet name')
param vnetName string = 'vnet-ai-shared'

@description('Private endpoint subnet name')
param subnetName string = 'PrivateEndpointSubnet'

@description('Principal ID to assign Storage Blob Data Contributor role')
param adminPrincipalId string = ''
```

### Resource Group

```bicep
resource storageResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-ai-storage'
  location: location
  tags: {
    environment: environment
    purpose: 'Private Storage Account infrastructure'
    owner: owner
    deployedBy: 'bicep'
  }
}
```

### Module Invocation

```bicep
module storageAccount '../modules/storage-account.bicep' = {
  scope: storageResourceGroup
  name: 'storage-account-deployment'
  params: {
    location: location
    environment: environment
    owner: owner
    storageNameSuffix: storageNameSuffix
    privateEndpointSubnetId: existingSubnet.id
    privateDnsZoneId: existingDnsZone.id
    adminPrincipalId: adminPrincipalId
  }
}
```

---

## Parameter File: main.parameters.json

**Path**: `bicep/storage-infra/main.parameters.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus2"
    },
    "environment": {
      "value": "dev"
    },
    "owner": {
      "value": "ai-lab-team"
    },
    "storageNameSuffix": {
      "value": "0117"
    },
    "coreResourceGroupName": {
      "value": "rg-ai-core"
    },
    "vnetName": {
      "value": "vnet-ai-shared"
    },
    "subnetName": {
      "value": "PrivateEndpointSubnet"
    }
  }
}
```

---

## Deployment Script Contract: deploy-storage-infra.sh

**Path**: `scripts/deploy-storage-infra.sh`

### Input Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `-p, --parameters` | No | `main.parameters.json` | Parameter file path |
| `-y, --yes` | No | false | Skip confirmation prompts |
| `-h, --help` | No | - | Show usage |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Deployment successful |
| 1 | Validation failed (pre-deployment) |
| 2 | What-if failed |
| 3 | Deployment failed |
| 4 | Post-deployment validation failed |

### Behavior Contract

1. **Pre-flight checks**:
   - Verify Azure CLI logged in
   - Verify core infrastructure exists (rg-ai-core)
   - Verify private DNS zone exists
   - Verify VNet/subnet exists
   - Check storage account name availability

2. **What-if analysis**:
   - Run `az deployment sub what-if`
   - Display changes
   - Prompt for confirmation (unless `-y`)

3. **Deployment**:
   - Run `az deployment sub create`
   - Capture deployment time
   - Display outputs

4. **Post-deployment validation**:
   - Verify storage account created
   - Verify private endpoint provisioned
   - Verify DNS resolution

### Example Output

```
[INFO] Starting Private Storage Account deployment
[INFO] Pre-flight checks...
[OK] Azure CLI authenticated
[OK] Core infrastructure exists (rg-ai-core)
[OK] Private DNS zone exists (privatelink.blob.core.windows.net)
[OK] Subnet exists (PrivateEndpointSubnet)
[OK] Storage account name 'stailab0117' is available

[INFO] Running what-if analysis...
Resource changes:
  + Microsoft.Resources/resourceGroups (rg-ai-storage)
  + Microsoft.Storage/storageAccounts (stailab0117)
  + Microsoft.Network/privateEndpoints (stailab0117-pe)

Proceed with deployment? [y/N]: y

[INFO] Deploying...
[OK] Deployment completed in 47 seconds

[INFO] Post-deployment validation...
[OK] Storage account created: stailab0117
[OK] Private endpoint provisioned: stailab0117-pe
[OK] DNS resolution: stailab0117.blob.core.windows.net -> 10.1.0.8

=== Deployment Summary ===
Storage Account: stailab0117
Blob Endpoint: https://stailab0117.blob.core.windows.net/
Private IP: 10.1.0.8
Deployment Time: 47s
```

---

## Validation Script Contract: validate-storage-infra.sh

**Path**: `scripts/validate-storage-infra.sh`

### Checks Performed

| Check | Pass Criteria |
|-------|---------------|
| Storage account exists | Resource found in rg-ai-storage |
| Shared key disabled | `allowSharedKeyAccess == false` |
| Public access disabled | `publicNetworkAccess == Disabled` |
| TLS 1.2 enforced | `minimumTlsVersion == TLS1_2` |
| Private endpoint exists | Resource found with `Succeeded` state |
| DNS resolution | FQDN resolves to 10.1.0.x |

---

## DNS Validation Script Contract: validate-storage-infra-dns.sh

**Path**: `scripts/validate-storage-infra-dns.sh`

### Checks Performed

| Check | Pass Criteria |
|-------|---------------|
| DNS zone exists | `privatelink.blob.core.windows.net` in rg-ai-core |
| A record exists | Record for storage account FQDN |
| Resolution works | `nslookup` returns private IP |
| Latency acceptable | Resolution < 100ms |

---

## RBAC Script Contract: grant-storage-infra-roles.sh

**Path**: `scripts/grant-storage-infra-roles.sh`

### Input Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--principal-id` | Yes | Azure AD principal ID |
| `--role` | No | Role name (default: Storage Blob Data Contributor) |

### Supported Roles

| Role | GUID |
|------|------|
| Storage Blob Data Contributor | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` |
| Storage Blob Data Reader | `2a2b9908-6ea1-4ae2-8e65-a410df84e7d1` |
| Storage Blob Data Owner | `b7e6dc6d-f1e8-4753-8033-0f276bb0955b` |

---

## Cleanup Script Contract: cleanup-storage-infra.sh

**Path**: `scripts/cleanup-storage-infra.sh`

### Behavior

1. Confirm deletion (unless `--yes`)
2. Delete resource group `rg-ai-storage`
3. Wait for deletion to complete
4. Verify cleanup

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Cleanup successful |
| 1 | Cleanup failed |
| 2 | User cancelled |
