# Private Azure Container Apps Environment

Deploy a VNet-injected Azure Container Apps environment with private endpoint connectivity, internal-only ingress, and integration with existing private DNS infrastructure for secure serverless container hosting.

## Overview

This project deploys a private Azure Container Apps (ACA) environment as an Infrastructure Project following the AI-Lab constitution patterns. The environment provides a secure, serverless container runtime that is only accessible via the private network.

**Key Features:**
- ✅ VNet-injected environment (infrastructure subnet /23)
- ✅ Private endpoint for management plane
- ✅ Internal-only ingress (no public access)
- ✅ DNS integration with existing private DNS zone
- ✅ Log Analytics workspace for monitoring
- ✅ Consumption workload profile

**Project Type:** Infrastructure Project (provides container hosting capabilities for other projects)

## Prerequisites

### Required Infrastructure
- Core infrastructure deployed (`rg-ai-core`)
- Shared services VNet (`vnet-ai-shared`) expanded to `/22` with:
  - `AcaEnvironmentSubnet` (`10.1.2.0/23`) with `Microsoft.App/environments` delegation
  - `PrivateEndpointSubnet` (`10.1.0.0/26`)
- Private DNS zone `privatelink.azurecontainerapps.io` in `rg-ai-core`
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
┌──────────────────────────────────────────────────────────────────────┐
│                         rg-ai-aca                                    │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                                                                │  │
│  │  ┌─────────────────────────┐   ┌────────────────────────────┐ │  │
│  │  │  Container Apps Env     │   │    Private Endpoint        │ │  │
│  │  │  cae-ai-lab             │   │    cae-ai-lab-pe           │ │  │
│  │  │                         │   │                            │ │  │
│  │  │  • VNet-injected        │   │  ┌──────────────────────┐  │ │  │
│  │  │  • Internal ingress     │   │  │  DNS Zone Group      │  │ │  │
│  │  │  • Consumption plan     │◄──│  │  (auto A-record)     │  │ │  │
│  │  │  • Static IP: 10.1.x.x │   │  └──────────┬───────────┘  │ │  │
│  │  └─────────────────────────┘   └─────────────┼──────────────┘ │  │
│  │                                              │                │  │
│  │  ┌─────────────────────────┐                 │                │  │
│  │  │  Log Analytics          │                 │                │  │
│  │  │  log-ai-aca             │                 │                │  │
│  │  │  (diagnostics/metrics)  │                 │                │  │
│  │  └─────────────────────────┘                 │                │  │
│  └──────────────────────────────────────────────┼────────────────┘  │
└─────────────────────────────────────────────────┼────────────────────┘
                                                  │
                    References                    │
                        ▼                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    rg-ai-core (EXISTING)                             │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  Private DNS Zone                    │  Shared Services VNet   │  │
│  │  privatelink.                        │  vnet-ai-shared         │  │
│  │    azurecontainerapps.io             │  10.1.0.0/22            │  │
│  │                                      │  ├─ PrivateEndpoint     │  │
│  │  (A record auto-registered)          │  │  Subnet 10.1.0.0/26 │  │
│  │                                      │  └─ AcaEnvironment     │  │
│  │                                      │     Subnet 10.1.2.0/23 │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

## Deployment

### Quick Start

```bash
# 1. Copy and customize parameter file
cp bicep/aca/main.parameters.example.json bicep/aca/main.parameters.json
# Edit main.parameters.json with your values

# 2. Validate prerequisites
./scripts/validate-aca.sh

# 3. Deploy (with what-if preview)
./scripts/deploy-aca.sh

# 4. Verify DNS resolution (requires VPN)
./scripts/validate-aca-dns.sh
```

### Deployment Scripts

| Script | Purpose |
|--------|---------|
| `deploy-aca.sh` | Deploy ACA environment with what-if preview |
| `validate-aca.sh` | Pre/post-deployment validation |
| `validate-aca-dns.sh` | DNS resolution verification |
| `cleanup-aca.sh` | Delete all ACA resources |

### Script Options

```bash
# Deploy with custom parameter file
./scripts/deploy-aca.sh --parameter-file ./custom.parameters.json

# Preview changes only (dry run)
./scripts/deploy-aca.sh --dry-run

# Automated deployment (CI/CD)
./scripts/deploy-aca.sh --auto-approve

# Validate deployed resources
./scripts/validate-aca.sh --deployed
```

## Configuration

### Parameter Reference

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `owner` | Yes | - | Owner identifier for tagging |
| `environment` | No | `dev` | Environment: dev, test, prod |
| `location` | No | `eastus2` | Azure region |
| `environmentName` | No | `cae-ai-lab` | ACA environment name |
| `resourceGroupName` | No | `rg-ai-aca` | ACA resource group |
| `coreResourceGroupName` | No | `rg-ai-core` | Core infrastructure RG |
| `vnetName` | No | `vnet-ai-shared` | Shared services VNet |
| `acaSubnetName` | No | `AcaEnvironmentSubnet` | ACA VNet injection subnet |
| `privateEndpointSubnetName` | No | `PrivateEndpointSubnet` | PE subnet |
| `privateDnsZoneName` | No | `privatelink.azurecontainerapps.io` | DNS zone |
| `zoneRedundant` | No | `false` | Zone redundancy (enable for prod) |
| `existingLogAnalyticsWorkspaceId` | No | `''` | Existing LA workspace ID |
| `logAnalyticsRetentionDays` | No | `30` | Log retention (30-730 days) |

## Testing

### Pre-Deployment Validation

```bash
./scripts/validate-aca.sh
```

Checks:
- ✅ Azure CLI login status
- ✅ Core infrastructure exists
- ✅ ACA subnet exists with delegation
- ✅ Parameter file valid
- ✅ Template syntax valid

### Post-Deployment Validation

```bash
./scripts/validate-aca.sh --deployed
```

Checks:
- ✅ ACA environment provisioned
- ✅ Internal-only ingress configured
- ✅ VNet injection active
- ✅ Private endpoint active
- ✅ Log Analytics connected

### DNS Resolution (Requires VPN)

```bash
./scripts/validate-aca-dns.sh
```

Checks:
- ✅ DNS resolves to private IP (10.1.x.x)
- ✅ Resolution time
- ✅ Public access blocked

### Deploy a Test Container App

```bash
# Deploy a simple test app to verify the environment
az containerapp create \
  --name test-app \
  --resource-group rg-ai-aca \
  --environment cae-ai-lab \
  --image mcr.microsoft.com/k8se/quickstart:latest \
  --target-port 80 \
  --ingress internal \
  --min-replicas 0 \
  --max-replicas 1

# Check app status
az containerapp show \
  --name test-app \
  --resource-group rg-ai-aca \
  --query "{Name:name, FQDN:properties.configuration.ingress.fqdn, Status:properties.provisioningState}" \
  -o table

# Test connectivity (requires VPN)
curl https://<app-fqdn>

# Clean up test app
az containerapp delete \
  --name test-app \
  --resource-group rg-ai-aca \
  --yes
```

## Cleanup

### Standard Cleanup

```bash
./scripts/cleanup-aca.sh
```

This deletes the ACA resource group and all contained resources.

### Automated Cleanup

```bash
./scripts/cleanup-aca.sh --force
```

**Warning**: This permanently deletes all resources. Cannot be undone.

### What's Preserved

Core infrastructure resources are NOT affected by cleanup:
- VNet and subnets in `rg-ai-core`
- Private DNS zones in `rg-ai-core`
- VPN gateway and connections

## Networking Details

### Subnet Requirements

| Subnet | CIDR | Purpose |
|--------|------|---------|
| `AcaEnvironmentSubnet` | `10.1.2.0/23` | VNet injection (min /23 required) |
| `PrivateEndpointSubnet` | `10.1.0.0/26` | Private endpoint NIC |

### NSG Rules

The ACA subnet NSG includes:
- VPN client inbound (10.0.0.0/24 → ACA subnet) for management access
- Default Azure rules for VNet-to-VNet communication

### DNS Flow

```
VPN Client → Private DNS Zone → Private Endpoint IP → ACA Environment
(10.0.0.x)   privatelink.        (10.1.0.x)           (10.1.2.x)
              azurecontainerapps.io
```

## Related Projects

| Project | Relationship |
|---------|-------------|
| [Core Infrastructure](../core-infrastructure/) | Provides VNet, DNS zones |
| [Private ACR](../registry/) | Container registry for images |
| [Private AKS](../aks/) | Alternative container hosting |
| [Key Vault](../keyvault/) | Secrets management |
