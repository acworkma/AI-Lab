# Data Model: Azure API Management Standard v2

**Feature**: 006-apim-std-v2  
**Date**: 2026-01-14  
**Purpose**: Define Azure resources and their relationships for APIM deployment

## Resource Entities

### 1. Resource Group

| Attribute | Value |
|-----------|-------|
| **Name** | `rg-ai-apim` |
| **Location** | `eastus2` |
| **Purpose** | Container for all APIM-related resources |
| **Tags** | environment, purpose, owner |

---

### 2. API Management Instance

| Attribute | Value |
|-----------|-------|
| **Name** | `apim-ai-lab` |
| **SKU** | `Standardv2` |
| **Capacity** | `1` |
| **Location** | `eastus2` |
| **Identity** | System-assigned managed identity |
| **VNet Type** | `None` (integration configured separately) |

**Relationships**:
- Belongs to: `rg-ai-apim`
- VNet Integration: `ApimIntegrationSubnet` in `vnet-ai-shared-services`
- DNS Resolution: Via Azure DNS + private DNS zones in `rg-ai-core`

**Outputs**:
- Gateway URL: `https://apim-ai-lab.azure-api.net`
- Developer Portal URL: `https://apim-ai-lab.developer.azure-api.net`
- Management URL: `https://apim-ai-lab.management.azure-api.net`
- Principal ID: For RBAC assignments

---

### 3. APIM Integration Subnet

| Attribute | Value |
|-----------|-------|
| **Name** | `ApimIntegrationSubnet` |
| **VNet** | `vnet-ai-shared-services` |
| **Address Prefix** | `10.1.0.64/26` |
| **Delegation** | `Microsoft.Web/serverFarms` |
| **NSG** | `nsg-apim-integration` |

**Relationships**:
- Parent: `vnet-ai-shared-services` in `rg-ai-core`
- Associated NSG: `nsg-apim-integration`
- Hub Connectivity: Via existing hub connection of shared-services-vnet

---

### 4. Network Security Group (APIM)

| Attribute | Value |
|-----------|-------|
| **Name** | `nsg-apim-integration` |
| **Location** | `eastus2` |
| **Purpose** | Control traffic for APIM VNet integration subnet |

**Rules**:

| Priority | Name | Direction | Source | Destination | Port | Action |
|----------|------|-----------|--------|-------------|------|--------|
| 100 | AllowStorageOutbound | Outbound | VirtualNetwork | Storage | 443 | Allow |
| 110 | AllowKeyVaultOutbound | Outbound | VirtualNetwork | AzureKeyVault | 443 | Allow |
| 120 | AllowVNetOutbound | Outbound | VirtualNetwork | VirtualNetwork | * | Allow |
| 4096 | DenyAllOutbound | Outbound | * | Internet | * | Deny |

**Relationships**:
- Associated with: `ApimIntegrationSubnet`

---

## Resource Dependency Graph

```
rg-ai-core (existing)
├── vnet-ai-shared-services (existing)
│   ├── PrivateEndpointSubnet (existing, 10.1.0.0/26)
│   └── ApimIntegrationSubnet (NEW, 10.1.0.64/26) ──┐
│                                                    │
rg-ai-apim (NEW)                                     │
├── nsg-apim-integration ────────────────────────────┤
└── apim-ai-lab ─────────────────────────────────────┘
    └── VNet Integration ────────────────────────────┘
```

## State Transitions

### APIM Deployment States

```
Not Deployed
    │
    ▼ (deploy-apim.sh)
Provisioning (~10-15 min)
    │
    ▼
Running (VNet Integration Active)
    │
    ├── Portal Published (manual step)
    │
    └── OAuth Configured (manual/script step)
```

## Validation Rules

1. **Subnet delegation**: Must be `Microsoft.Web/serverFarms` before APIM deployment
2. **Subnet size**: Must be at least /27 (32 addresses)
3. **NSG association**: Required before APIM deployment
4. **Microsoft.Web provider**: Must be registered in subscription
5. **Unique name**: APIM name must be globally unique
6. **Publisher email**: Must be valid email format
7. **VNet location**: Must match APIM location (eastus2)
