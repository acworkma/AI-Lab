# Deployment Contract: Core Azure vWAN Infrastructure

**Version**: 1.0.0  
**Date**: 2025-12-31  
**Feature**: Core Azure vWAN Infrastructure

## Purpose

This contract defines the interface between the Bicep deployment templates and deployment operators (manual or automated). It specifies inputs, outputs, and deployment guarantees.

---

## Input Contract

### Required Parameters

All deployments MUST provide these parameters:

| Parameter | Type | Description | Validation |
|-----------|------|-------------|------------|
| `location` | string | Azure region | Must be valid Azure region (default: eastus2) |
| `environment` | string | Environment tag | Must be: dev, test, or prod |
| `owner` | string | Owner identifier | 1-100 characters |

### Optional Parameters (with defaults)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `resourceGroupName` | string | "rg-ai-core" | Resource group name (fixed per constitution) |
| `vwanName` | string | "vwan-ai-hub" | Virtual WAN name |
| `vhubName` | string | "hub-ai-eastus2" | Virtual Hub name |
| `vhubAddressPrefix` | string | "10.0.0.0/16" | Hub address space (CIDR) |
| `vpnGatewayName` | string | "vpngw-ai-hub" | VPN Gateway name |
| `vpnGatewayScaleUnit` | integer | 1 | VPN scale units (1-20) |
| `keyVaultName` | string | (required) | Key Vault name (globally unique, 3-24 chars) |
| `keyVaultSku` | string | "standard" | Key Vault SKU (standard or premium) |
| `enablePurgeProtection` | boolean | false | Enable purge protection (true for prod) |
| `deployedBy` | string | "manual" | Deployment method tag |
| `tags` | object | {} | Additional custom tags |

### Parameter File Format

**main.parameters.json** (no secrets):
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
      "value": "platform-team"
    },
    "keyVaultName": {
      "value": "kv-ai-core-a1b2"
    }
  }
}
```

**main.local.parameters.json** (gitignored, for local overrides):
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "owner": {
      "value": "john-doe"
    },
    "keyVaultName": {
      "value": "kv-ai-core-dev123"
    }
  }
}
```

---

## Output Contract

Deployment MUST provide these outputs upon successful completion:

| Output | Type | Description | Usage |
|--------|------|-------------|-------|
| `resourceGroupName` | string | Resource group name | Reference for spoke deployments |
| `resourceGroupId` | string | Resource group resource ID | RBAC scope |
| `vwanId` | string | Virtual WAN resource ID | Future vWAN configuration |
| `vhubId` | string | Virtual Hub resource ID | Spoke VNet connection target |
| `vhubName` | string | Virtual Hub name | CLI commands for spoke connections |
| `vpnGatewayId` | string | VPN Gateway resource ID | VPN connection configuration |
| `keyVaultId` | string | Key Vault resource ID | RBAC assignments |
| `keyVaultUri` | string | Key Vault URI | Secret references (https://...) |
| `keyVaultName` | string | Key Vault name | CLI commands and parameter files |

**Output Format** (JSON):
```json
{
  "resourceGroupName": "rg-ai-core",
  "resourceGroupId": "/subscriptions/{sub-id}/resourceGroups/rg-ai-core",
  "vwanId": "/subscriptions/{sub-id}/resourceGroups/rg-ai-core/providers/Microsoft.Network/virtualWans/vwan-ai-hub",
  "vhubId": "/subscriptions/{sub-id}/resourceGroups/rg-ai-core/providers/Microsoft.Network/virtualHubs/hub-ai-eastus2",
  "vhubName": "hub-ai-eastus2",
  "vpnGatewayId": "/subscriptions/{sub-id}/resourceGroups/rg-ai-core/providers/Microsoft.Network/vpnGateways/vpngw-ai-hub",
  "keyVaultId": "/subscriptions/{sub-id}/resourceGroups/rg-ai-core/providers/Microsoft.KeyVault/vaults/kv-ai-core-a1b2",
  "keyVaultUri": "https://kv-ai-core-a1b2.vault.azure.net/",
  "keyVaultName": "kv-ai-core-a1b2"
}
```

---

## Deployment Guarantees

### Idempotency

- Running deployment multiple times with same parameters produces same result
- No errors if resources already exist with matching configuration
- What-if mode shows "no changes" on subsequent runs

### Atomicity

- If deployment fails, resources in partially created state
- Failed resources marked with provisioningState: "Failed"
- Operator must either:
  1. Fix issue and re-run deployment (idempotent), OR
  2. Delete resource group and start fresh

### Validation Gates

Deployment scripts MUST:
1. Validate parameter schema against `main.parameters.schema.json`
2. Run `az deployment sub what-if` before applying
3. Check what-if output for destructive changes
4. Prompt for confirmation if destructive changes detected
5. Abort if validation fails

### Rollback Procedures

**If deployment fails**:
1. Check deployment errors: `az deployment sub show --name {deployment-name}`
2. Review specific resource errors in portal or CLI
3. Common fixes:
   - **Key Vault name conflict**: Change `keyVaultName` parameter (must be globally unique)
   - **Quota exceeded**: Request quota increase or reduce scale units
   - **Network overlap**: Adjust `vhubAddressPrefix` to avoid conflicts
4. Re-run deployment after fixing (idempotent)

**If deployed resources need deletion**:
1. Delete spoke connections first (if any): `az network vhub connection delete`
2. Delete resource group: `az group delete --name rg-ai-core --yes`
3. Wait for soft-deleted Key Vault purge (90 days) OR purge manually: `az keyvault purge --name {vault-name}`

---

## Success Criteria Validation

Post-deployment validation MUST confirm:

| Criterion | Validation Method | Expected Result |
|-----------|------------------|-----------------|
| Resources exist | `az group show --name rg-ai-core` | Provisioning state: Succeeded |
| vWAN hub operational | `az network vhub show --name hub-ai-eastus2 --resource-group rg-ai-core` | routingState: Provisioned |
| VPN Gateway ready | `az network vpn-gateway show --name vpngw-ai-hub --resource-group rg-ai-core` | provisioningState: Succeeded |
| Key Vault accessible | `az keyvault secret set --vault-name {kv-name} --name test --value test` | Secret created successfully |
| Tags applied | `az group show --name rg-ai-core --query tags` | environment, purpose, owner present |
| No config drift | `az deployment sub what-if` | No changes detected |
| Deployment time | Measure from start to completion | < 30 minutes |

---

## Security Contract

### Secrets Management

Deployments MUST NOT:
- Include secrets in parameter files committed to Git
- Log secrets to console or files
- Hardcode secrets in Bicep templates

Deployments MUST:
- Store secrets in Key Vault only
- Use Key Vault references in parameter files for sensitive values
- Exclude `*.local.parameters.json` from version control (.gitignore)

### Access Control

Deploying principal MUST have:
- Subscription Contributor (or custom role with deployment permissions)
- Key Vault Administrator (for initial Key Vault setup)

Post-deployment:
- Spoke lab deployments need "Key Vault Secrets User" role on Key Vault
- Spoke lab deployments need "Reader" role on vWAN hub for connection creation

---

## Versioning

This contract follows semantic versioning:
- **Major**: Breaking changes to input/output interface
- **Minor**: Backward-compatible additions (new optional parameters, new outputs)
- **Patch**: Bug fixes, documentation updates

**Current Version**: 1.0.0
- Initial contract for core infrastructure deployment

---

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-12-31 | Initial deployment contract |

---

## Contact

For questions or issues with this deployment contract:
- Review: [spec.md](../spec.md) for feature requirements
- Review: [data-model.md](../data-model.md) for resource details
- Review: [quickstart.md](../quickstart.md) for deployment guide
