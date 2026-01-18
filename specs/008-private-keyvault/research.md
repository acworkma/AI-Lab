# Research: Private Azure Key Vault Infrastructure

**Feature**: 008-private-keyvault  
**Phase**: 0 - Research & Decision Log  
**Date**: 2025-01-17

## Overview

Research findings for implementing Azure Key Vault with private endpoint connectivity, RBAC authorization, and integration with existing private DNS infrastructure. This document resolves all research tasks identified in the implementation plan and documents key decisions.

## Research Tasks Completed

1. **Key Vault Naming Strategy** - Unique suffix for soft-delete collision avoidance
2. **Private Endpoint Configuration** - DNS zone group setup patterns
3. **RBAC Roles** - Required roles for deployment and operations
4. **Bicep Key Vault References** - Parameter file syntax for secrets
5. **Soft-Delete and Purge Protection** - Configuration options

---

## Decision 1: Key Vault Naming Strategy

### Decision
Use naming pattern `kv-ai-lab-<4-digit-suffix>` where suffix is derived from deployment date (MMDD format)

### Rationale
- **Global Uniqueness**: Key Vault names must be globally unique across Azure
- **Soft-Delete Collision**: Soft-deleted vaults retain their names for 7-90 days, blocking reuse
- **Predictability**: Date-based suffix is human-readable and traceable to deployment
- **Spec Alignment**: Clarification session confirmed unique suffix approach
- **Existing Pattern**: Similar to storage account naming in 005-storage-cmk

### Naming Examples
- `kv-ai-lab-0117` (deployed January 17)
- `kv-ai-lab-0315` (deployed March 15)

### Implementation
```bicep
// Default suffix based on deployment date
param keyVaultNameSuffix string = utcNow('MMdd')
var keyVaultName = 'kv-ai-lab-${keyVaultNameSuffix}'
```

### Alternatives Considered
- **UniqueString()**: Harder to identify/trace, less human-readable
- **Random characters**: Unpredictable, harder to document
- **No suffix**: Would fail on redeployment if soft-deleted vault exists

### References
- [Key Vault naming constraints](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftkeyvault)
- Spec clarification session 2026-01-17

---

## Decision 2: Private Endpoint Configuration

### Decision
Create private endpoint with DNS zone group linking to existing `privatelink.vaultcore.azure.net` in rg-ai-core

### Rationale
- **Infrastructure Ready**: Core deployment already has the private DNS zone for Key Vault
- **Zero DNS Duplication**: Reuse existing zone instead of creating new one
- **Constitution Alignment**: Principle 6 - modularity, leverage core infrastructure
- **Automatic DNS Registration**: Private endpoint creates A record in linked DNS zone

### Configuration Details
```bicep
// Private endpoint for Key Vault
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${keyVaultName}-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId  // snet-private-endpoints in vnet-ai-shared
    }
    privateLinkServiceConnections: [{
      name: '${keyVaultName}-plsc'
      properties: {
        privateLinkServiceId: keyVault.id
        groupIds: ['vault']  // Key Vault subresource
      }
    }]
  }
}

// DNS zone group for automatic A record registration
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'keyvault-dns'
      properties: {
        privateDnsZoneId: privateDnsZoneId  // privatelink.vaultcore.azure.net in rg-ai-core
      }
    }]
  }
}
```

### Network Settings
- **Public Network Access**: `'Disabled'` - enforces private-only access
- **Network ACLs**: `defaultAction: 'Deny'`, `bypass: 'None'`
- **Subnet**: `snet-private-endpoints` (10.1.0.0/26) in shared services VNet

### References
- [Azure Key Vault private endpoint](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service)
- [Private endpoint DNS integration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)

---

## Decision 3: RBAC Authorization Model

### Decision
Use **RBAC authorization** (not legacy access policies) with specific roles for deployment and operations

### Rationale
- **Security Best Practice**: RBAC provides finer-grained control than access policies
- **Constitution Alignment**: Principle 4 - use Azure RBAC for access control
- **Recommended by Microsoft**: Access policies are legacy; RBAC is preferred
- **Auditability**: RBAC assignments are tracked in Azure Activity Log

### Required Roles

#### For Deployment (Control Plane)
| Role | Purpose | Role ID |
|------|---------|---------|
| **Contributor** | Deploy Key Vault resource | `b24988ac-6180-42a0-ab88-20f7382dd24c` |
| **Network Contributor** | Create private endpoint on shared VNet | `4d97b98b-1d4f-4787-a291-c67834d212e7` |

#### For Operations (Data Plane)
| Role | Purpose | Role ID |
|------|---------|---------|
| **Key Vault Administrator** | Full access to all data plane operations | `00482a5a-887f-4fb3-b363-3b7fe8e74483` |
| **Key Vault Secrets Officer** | Create, read, update, delete secrets | `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` |
| **Key Vault Secrets User** | Read secret values only | `4633458b-17de-408a-b874-0445c86b69e6` |
| **Key Vault Crypto User** | Perform cryptographic operations | `12338af0-0e69-4776-bea7-57ae8d297424` |

### Implementation
```bicep
// Enable RBAC authorization
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    enableRbacAuthorization: true  // REQUIRED - enables RBAC model
    accessPolicies: []              // EMPTY - not using legacy model
    // ... other properties
  }
}
```

### Alternatives Considered
- **Access Policies**: Legacy model, harder to manage at scale
  - Rejected: Microsoft recommends RBAC for new deployments
- **Hybrid (RBAC + Access Policies)**: Possible but complex
  - Rejected: Adds confusion, stick with single model

### References
- [Key Vault RBAC guide](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [Azure built-in roles for Key Vault](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/security#key-vault-administrator)

---

## Decision 4: Bicep Key Vault Reference Syntax

### Decision
Document and support **Key Vault reference syntax** in Bicep parameter files for other projects

### Rationale
- **Spec Requirement**: User Story 3 requires Bicep reference integration
- **Security**: Secrets never stored in source control
- **Azure Pattern**: Standard approach for secure parameter passing

### Reference Syntax (JSON Parameter File)
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "adminPassword": {
      "reference": {
        "keyVault": {
          "id": "/subscriptions/{subscription-id}/resourceGroups/rg-ai-keyvault/providers/Microsoft.KeyVault/vaults/kv-ai-lab-0117"
        },
        "secretName": "admin-password"
      }
    }
  }
}
```

### Reference Syntax (Bicep Parameter File - .bicepparam)
```bicep
using './main.bicep'

param adminPassword = az.getSecret(
  '<subscription-id>',
  'rg-ai-keyvault',
  'kv-ai-lab-0117',
  'admin-password'
)
```

### Required Permissions
- Deploying user needs `Microsoft.KeyVault/vaults/deploy/action` permission
- Built-in roles with this permission: Owner, Contributor
- Custom role can be created for minimal access

### References
- [Key Vault parameter references in Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/key-vault-parameter)
- [Bicep functions - getSecret](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-resource#getsecret)

---

## Decision 5: Soft-Delete and Purge Protection

### Decision
Enable **soft-delete with 90-day retention**; **purge protection disabled** for lab environment

### Rationale
- **Soft-Delete Required**: Azure enforces soft-delete on all new Key Vaults (cannot be disabled)
- **90-Day Default**: Standard retention period, sufficient for accidental deletion recovery
- **Purge Protection Off**: Allows complete cleanup in lab scenarios without waiting
- **Spec Alignment**: Purge protection should be configurable (disabled for lab, enabled for prod)

### Configuration
```bicep
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    enableSoftDelete: true          // Always enabled (Azure default)
    softDeleteRetentionInDays: 90   // Standard retention
    enablePurgeProtection: enablePurgeProtection  // Configurable, default false for lab
    // ... other properties
  }
}
```

### Lab vs Production Settings
| Setting | Lab (default) | Production |
|---------|---------------|------------|
| Soft-Delete | Enabled | Enabled |
| Retention Days | 90 | 90 |
| Purge Protection | **Disabled** | **Enabled** |

### Warning
Once purge protection is enabled, it **cannot be disabled**. Only enable for production workloads where secrets cannot be permanently lost.

### Alternatives Considered
- **Purge Protection On**: More secure but blocks cleanup
  - Rejected for lab: Creates issues with soft-deleted vault name collision
- **7-Day Retention**: Minimum allowed
  - Rejected: 90 days is reasonable safety net

### References
- [Key Vault soft-delete](https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview)
- [Key Vault purge protection](https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview#purge-protection)

---

## Decision 6: Key Vault SKU

### Decision
Use **Standard SKU** (not Premium)

### Rationale
- **Lab Context**: No requirement for HSM-backed keys
- **Cost Optimization**: Standard SKU is significantly cheaper
- **Feature Sufficiency**: Standard supports all required features:
  - Secrets management ✓
  - RBAC authorization ✓
  - Private endpoints ✓
  - Soft-delete ✓
- **Spec Alignment**: "Standard SKU; Premium deferred unless HSM required"

### SKU Comparison
| Feature | Standard | Premium |
|---------|----------|---------|
| Secrets | ✓ | ✓ |
| Keys (Software) | ✓ | ✓ |
| Keys (HSM-backed) | ✗ | ✓ |
| Private Endpoints | ✓ | ✓ |
| Price | Lower | Higher |

### Alternatives Considered
- **Premium SKU**: Required only for HSM-backed keys
  - Rejected: No current requirement for HSM

### References
- [Key Vault pricing](https://azure.microsoft.com/en-us/pricing/details/key-vault/)
- [Key Vault SKU comparison](https://learn.microsoft.com/en-us/azure/key-vault/general/overview#key-vault-pricing)

---

## Verification from Core Infrastructure

### Existing Resources (deployed in rg-ai-core)
```bash
# Private DNS zone for Key Vault (already exists)
az network private-dns zone show \
  --name "privatelink.vaultcore.azure.net" \
  --resource-group "rg-ai-core"

# VNet link to shared services VNet (already exists)
az network private-dns link vnet show \
  --name "vnet-ai-shared-link" \
  --resource-group "rg-ai-core" \
  --zone-name "privatelink.vaultcore.azure.net"

# Private endpoint subnet (already exists)
az network vnet subnet show \
  --name "snet-private-endpoints" \
  --vnet-name "vnet-ai-shared" \
  --resource-group "rg-ai-core"
```

### DNS Resolution Flow
1. VPN client queries `kv-ai-lab-0117.vault.azure.net`
2. DNS Resolver (10.1.0.68) receives query
3. Resolver forwards to Azure DNS which checks private zone link
4. `privatelink.vaultcore.azure.net` zone returns A record with private IP
5. Client connects to Key Vault via private IP (10.1.0.x)

---

## Summary of Key Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Naming | `kv-ai-lab-<MMDD>` with date-based suffix |
| 2 | Private Endpoint | Use existing DNS zone in rg-ai-core |
| 3 | Authorization | RBAC only (no access policies) |
| 4 | Bicep References | Document JSON and .bicepparam syntax |
| 5 | Soft-Delete | Enabled, 90 days, purge protection off |
| 6 | SKU | Standard (Premium deferred) |

---

## Unresolved Issues

**None** - All research tasks completed and decisions documented.
