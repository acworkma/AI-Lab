# Azure API Management Standard v2 — Private

Deploy Azure API Management Standard v2 as a **fully private** API gateway with inbound private endpoint and public network access disabled.

## Overview

This Infrastructure Project deploys a private APIM instance that is the counterpart to the [public APIM variant](../apim/README.md). Unlike the public variant, this deployment has **no public network exposure**. API consumers must reach the gateway through the private endpoint within the VNet.

This project deploys:
- **APIM Standard v2 instance** with `publicNetworkAccess: Disabled`
- **Inbound private endpoint** (Gateway group) in the shared services VNet
- **Private DNS zone** (`privatelink.azure-api.net`) for name resolution
- **VNet integration subnet** for outbound backend connectivity
- **Power Platform delegated subnet** (for solution projects that connect Copilot Studio)
- **NSG** for APIM integration subnet traffic control

### Architecture

```
                                    ┌─────────────────────────────────────────┐
                                    │           Azure Cloud                   │
                                    │  ┌─────────────────────────────────┐    │
                                    │  │        rg-ai-apim-private       │    │
                                    │  │                                 │    │
                                    │  │  ┌─────────────────────────┐   │    │
                                    │  │  │   apim-ai-lab-private   │   │    │
                                    │  │  │   (Standardv2)          │   │    │
                                    │  │  │                         │   │    │
                                    │  │  │  publicNetworkAccess:   │   │    │
                                    │  │  │    Disabled             │   │    │
                                    │  │  └───────────┬─────────────┘   │    │
                                    │  └──────────────│─────────────────┘    │
                                    │                 │ VNet Integration      │
                                    │  ┌──────────────▼─────────────────────┐ │
                                    │  │        rg-ai-core                  │ │
                                    │  │                                    │ │
┌─────────────┐    VPN Tunnel       │  │  ┌─────────────────────────────┐  │ │
│ VPN Clients │ ◄──────────────────►│  │  │  vnet-ai-shared-services   │  │ │
└─────────────┘                     │  │  │                             │  │ │
                                    │  │  │  ┌─────────────────────┐   │  │ │
                                    │  │  │  │ PrivateEndpointSubnet│   │  │ │
                                    │  │  │  │   (10.1.0.0/26)     │   │  │ │
                                    │  │  │  │  ┌────────────────┐ │   │  │ │
                                    │  │  │  │  │ APIM PE        │ │   │  │ │
                                    │  │  │  │  │ (Gateway)      │ │   │  │ │
                                    │  │  │  │  └────────────────┘ │   │  │ │
                                    │  │  │  └─────────────────────┘   │  │ │
                                    │  │  │                             │  │ │
                                    │  │  │  ┌─────────────────────┐   │  │ │
                                    │  │  │  │ ApimPrivateIntegra- │   │  │ │
                                    │  │  │  │ tionSubnet          │   │  │ │
                                    │  │  │  │   (10.1.0.128/27)  │──►│ Private │
                                    │  │  │  └─────────────────────┘   │ Backends│
                                    │  │  │                             │  │ │
                                    │  │  │  ┌─────────────────────┐   │  │ │
                                    │  │  │  │ PowerPlatformSubnet │   │  │ │
                                    │  │  │  │   (10.1.1.0/27)    │   │  │ │
                                    │  │  │  │  Delegated to PP    │   │  │ │
                                    │  │  │  └─────────────────────┘   │  │ │
                                    │  │  └─────────────────────────────┘  │ │
                                    │  └────────────────────────────────────┘ │
                                    └─────────────────────────────────────────┘

DNS: privatelink.azure-api.net → private endpoint IP
```

### Key Difference from Public Variant

| Aspect | Public APIM | Private APIM (this) |
|--------|-------------------|---------------------|
| Gateway access | Public URL over internet | Private endpoint only |
| `publicNetworkAccess` | Enabled | **Disabled** |
| Inbound path | Internet → public IP | VNet → private endpoint |
| Resource group | `rg-ai-apim` | `rg-ai-apim-private` |
| PP subnet | Not included | **Included** (for solution projects) |

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Azure CLI | Version 2.50.0 or later |
| Azure Subscription | With Contributor access |
| Core Infrastructure | `rg-ai-core` with vWAN hub, shared services VNet, DNS resolver |
| jq | For JSON processing |

### Provider Registrations

```bash
az provider register --namespace Microsoft.ApiManagement
az provider register --namespace Microsoft.Network
```

## Quick Start

### 1. Create Parameter File

```bash
cp bicep/apim-private/main.parameters.example.json bicep/apim-private/main.parameters.json
```

Edit `bicep/apim-private/main.parameters.json`:
```json
{
  "parameters": {
    "publisherEmail": {
      "value": "your-email@your-domain.com"
    }
  }
}
```

### 2. Deploy

```bash
./scripts/deploy-apim-private.sh
```

> **Note**: APIM deployment takes approximately 15-20 minutes. The script deploys APIM, the private endpoint, DNS zone, and all subnets.

### 3. Validate

```bash
./scripts/validate-apim-private.sh
```

### 4. Post-Deployment

After the infrastructure is deployed, solution projects can deploy APIs into this APIM instance. See:
- [Private MCP Server Solution](../mcp-private/README.md) — MCP Server + Copilot Studio via PP VNet delegation

## Configuration

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `apimName` | `apim-ai-lab-private` | APIM instance name (globally unique) |
| `location` | `eastus2` | Azure region |
| `publisherEmail` | *required* | Publisher email address |
| `publisherName` | `AI-Lab` | Publisher organization name |
| `sku` | `Standardv2` | APIM pricing tier |
| `skuCapacity` | `1` | Number of scale units |
| `sharedServicesVnetName` | `vnet-ai-shared` | Shared services VNet |
| `sharedServicesVnetResourceGroup` | `rg-ai-core` | VNet resource group |
| `apimSubnetPrefix` | `10.1.0.128/27` | APIM integration subnet CIDR |
| `ppSubnetPrefix` | `10.1.1.0/27` | Power Platform subnet CIDR |
| `privateEndpointSubnetName` | `PrivateEndpointSubnet` | Existing PE subnet |
| `vpnClientAddressPool` | `172.16.0.0/24` | VPN client CIDR for NSG |
| `enableVnetIntegration` | `true` | Enable VNet integration |

### Deployment Outputs

| Output | Description |
|--------|-------------|
| `apimName` | Deployed APIM instance name |
| `gatewayUrl` | Private gateway URL (resolves via privatelink DNS) |
| `principalId` | Managed identity principal ID |
| `privateEndpointIp` | Private endpoint IP address |
| `ppSubnetId` | Power Platform subnet resource ID |
| `resourceGroupName` | APIM resource group name |

## File Structure

```
AI-Lab/
├── bicep/
│   ├── modules/
│   │   ├── apim-private.bicep         # APIM + PE + DNS zone group
│   │   ├── pp-subnet.bicep            # Power Platform delegated subnet
│   │   └── private-dns-zone.bicep     # Reusable single DNS zone module
│   ├── apim-private/
│   │   ├── main.bicep                 # Orchestration (subscription-scoped)
│   │   └── main.parameters.example.json
├── scripts/
│   ├── deploy-apim-private.sh         # Deploy private APIM infrastructure
│   ├── validate-apim-private.sh       # Validate deployment
│   └── cleanup-apim-private.sh        # Cleanup resources
├── docs/apim-private/
│   └── README.md                      # This file
└── specs/015-apim-private/
    └── spec.md                        # Feature specification
```

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy-apim-private.sh` | Deploy APIM with private endpoint and subnets |
| `validate-apim-private.sh` | Validate deployment status |
| `cleanup-apim-private.sh` | Remove APIM resources |

### Script Options

```bash
# What-if only (no deployment)
./scripts/deploy-apim-private.sh --what-if

# Skip confirmation
./scripts/deploy-apim-private.sh --auto-approve

# Full cleanup including subnets and DNS zone
./scripts/cleanup-apim-private.sh --include-networking

# Skip confirmation for cleanup
./scripts/cleanup-apim-private.sh --auto-approve
```

## Troubleshooting

### Deployment Failures

**APIM provisioning stuck or failed**
- Check Azure Activity Log for detailed errors
- Ensure APIM integration subnet has correct delegation (`Microsoft.Web/serverFarms`)
- Verify NSG allows required APIM management traffic (ports 3443, 443)

**Private endpoint stuck in Pending state**
```
Connection state: Pending
```
Solution: Approve the private endpoint connection from the APIM resource in the Azure Portal. The Bicep template should auto-approve, but manual approval may be needed if deploying to a different subscription.

**Publisher email validation error**
```
Publisher email must be set
```
Solution: Set a valid email in the parameter file (not a placeholder).

### Private Endpoint / DNS Issues

**Cannot resolve APIM URL from VPN**
1. Verify VPN is connected
2. Check `privatelink.azure-api.net` zone exists and is linked to the VNet:
   ```bash
   az network private-dns zone show --name privatelink.azure-api.net -g rg-ai-core
   az network private-dns link vnet list --zone-name privatelink.azure-api.net -g rg-ai-core -o table
   ```
3. Verify DNS resolver is deployed in core infrastructure
4. Test resolution:
   ```bash
   nslookup apim-ai-lab-private.azure-api.net
   # Should return 10.1.0.x (private IP), NOT a public IP
   ```

**APIM still accessible from public internet**
- Verify `publicNetworkAccess` is `Disabled`:
  ```bash
  az apim show -n apim-ai-lab-private -g rg-ai-apim-private \
    --query "publicNetworkAccess" -o tsv
  ```
- If it shows `Enabled`, redeploy. The Bicep template sets this to `Disabled`.

### VNet Integration Issues

**APIM cannot reach backend services**
1. Verify APIM shows VNet integration in Azure Portal
2. Check NSG outbound rules allow VNet traffic
3. Ensure backend service allows inbound from APIM subnet

**DNS resolution failing for backends**
1. Verify DNS resolver is deployed in core infrastructure
2. Check private DNS zones are linked to shared services VNet
3. Test resolution from APIM diagnostic console

## Related Documentation

- [Public APIM Deployment](../apim/README.md)
- [Private MCP Server Solution](../mcp-private/README.md)
- [Core Infrastructure](../core-infrastructure/README.md)
- [ACA Environment](../aca/README.md)
- [Azure APIM Private Endpoint](https://learn.microsoft.com/en-us/azure/api-management/private-endpoint)
- [Power Platform VNet Support](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)

## Cost Estimation

| Resource | SKU | Estimated Monthly Cost |
|----------|-----|------------------------|
| API Management | Standard v2 (1 unit) | ~$175 USD |
| Private Endpoint | Per endpoint | ~$7.30 USD |
| Private DNS Zone | Per zone | ~$0.50 USD |

*Costs vary by region and usage. Use Azure Pricing Calculator for accurate estimates.*

## Security Considerations

- ✅ `publicNetworkAccess: Disabled` — gateway is not reachable from the internet
- ✅ Inbound private endpoint — all API traffic stays within the VNet
- ✅ System-assigned managed identity for Azure service access
- ✅ TLS 1.2+ enforced
- ✅ NSG restricts traffic on APIM integration subnet
- ✅ Power Platform delegated subnet ready for solution project use
