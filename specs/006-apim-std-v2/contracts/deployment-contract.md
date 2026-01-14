# Deployment Contract: Azure API Management Standard v2

**Feature**: 006-apim-std-v2  
**Date**: 2026-01-14  
**Purpose**: Define deployment interface and parameter schema

## Deployment Overview

| Aspect | Value |
|--------|-------|
| **Deployment Scope** | Resource Group |
| **Target Resource Group** | `rg-ai-apim` |
| **Deployment Script** | `./scripts/deploy-apim.sh` |
| **Estimated Duration** | 15-20 minutes |
| **Idempotent** | Yes |

## Prerequisites

### Required Deployments
- Core infrastructure (`rg-ai-core`) with vWAN hub and shared services VNet
- DNS resolver infrastructure (for private endpoint resolution)

### Required Permissions
- `Contributor` on subscription (for resource group creation)
- `Network Contributor` on shared services VNet (for subnet creation)
- `Microsoft.Web/serverFarms/join/action` on subnet (for delegation)

### Required Provider Registrations
- `Microsoft.ApiManagement`
- `Microsoft.Web` (for subnet delegation)

## Parameter Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "apimName": {
      "type": "string",
      "description": "Name of the API Management instance (must be globally unique)",
      "default": "apim-ai-lab",
      "pattern": "^[a-zA-Z][a-zA-Z0-9-]{0,48}[a-zA-Z0-9]$"
    },
    "location": {
      "type": "string",
      "description": "Azure region for deployment",
      "default": "australiaeast"
    },
    "publisherEmail": {
      "type": "string",
      "format": "email",
      "description": "Email address of the API publisher (required)"
    },
    "publisherName": {
      "type": "string",
      "description": "Name of the API publisher organization",
      "default": "AI-Lab"
    },
    "sku": {
      "type": "string",
      "enum": ["Standardv2"],
      "default": "Standardv2",
      "description": "APIM pricing tier"
    },
    "skuCapacity": {
      "type": "integer",
      "minimum": 1,
      "maximum": 10,
      "default": 1,
      "description": "Number of scale units"
    },
    "sharedServicesVnetName": {
      "type": "string",
      "description": "Name of the shared services VNet for integration",
      "default": "vnet-ai-shared-services"
    },
    "sharedServicesVnetResourceGroup": {
      "type": "string",
      "description": "Resource group containing the shared services VNet",
      "default": "rg-ai-core"
    },
    "apimSubnetPrefix": {
      "type": "string",
      "description": "CIDR prefix for APIM integration subnet",
      "default": "10.1.0.64/26"
    },
    "vpnClientAddressPool": {
      "type": "string",
      "description": "VPN client address pool for NSG rules",
      "default": "172.16.0.0/24"
    },
    "tags": {
      "type": "object",
      "description": "Resource tags",
      "default": {
        "environment": "dev",
        "purpose": "API Management Gateway",
        "owner": "platform-team"
      }
    }
  },
  "required": ["publisherEmail"]
}
```

## Deployment Outputs

| Output | Type | Description |
|--------|------|-------------|
| `apimName` | string | Name of the deployed APIM instance |
| `apimResourceId` | string | Full resource ID of APIM |
| `gatewayUrl` | string | Public gateway URL |
| `developerPortalUrl` | string | Developer portal URL |
| `managementUrl` | string | Management API URL |
| `principalId` | string | System-assigned managed identity principal ID |
| `apimSubnetId` | string | Resource ID of the integration subnet |

## Deployment Commands

### Deploy
```bash
./scripts/deploy-apim.sh
```

### Validate (What-If)
```bash
./scripts/deploy-apim.sh --what-if
```

### Cleanup
```bash
./scripts/cleanup-apim.sh
```

## Post-Deployment Steps

1. **Publish Developer Portal**
   ```bash
   az apim portalsetting update --resource-group rg-ai-apim --service-name apim-ai-lab
   # Or via Azure Portal: API Management > Portal overview > Publish
   ```

2. **Verify VNet Integration**
   ```bash
   az apim show --name apim-ai-lab --resource-group rg-ai-apim \
     --query "virtualNetworkConfiguration"
   ```

3. **Test Gateway Connectivity**
   ```bash
   curl -I https://apim-ai-lab.azure-api.net/status-0123456789abcdef
   ```

## Rollback Procedure

1. Delete APIM resource group:
   ```bash
   az group delete --name rg-ai-apim --yes --no-wait
   ```

2. Remove APIM subnet from shared services VNet (if needed):
   ```bash
   az network vnet subnet delete \
     --resource-group rg-ai-core \
     --vnet-name vnet-ai-shared-services \
     --name ApimIntegrationSubnet
   ```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| `SubnetDelegationRequired` | Subnet not delegated | Add delegation to `Microsoft.Web/serverFarms` |
| `SubnetInUse` | Subnet used by another resource | Use different subnet or remove conflicting resource |
| `NameNotAvailable` | APIM name already taken | Choose different globally unique name |
| `QuotaExceeded` | Subscription limit reached | Request quota increase or delete unused APIM instances |
| `VNetNotFound` | Shared services VNet missing | Deploy core infrastructure first |
