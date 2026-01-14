# Azure API Management Standard v2

Deploy Azure API Management Standard v2 as a centralized API gateway with public frontend and VNet-integrated backend for exposing internal APIs externally.

## Overview

This Infrastructure Project deploys:
- **APIM Standard v2 instance** with system-assigned managed identity
- **VNet integration** to shared services subnet for private backend access
- **Public gateway** for external API consumers
- **Developer portal** for API documentation and testing

### Architecture

```
                                    ┌─────────────────────────────────────────┐
                                    │           Azure Cloud                   │
                                    │  ┌─────────────────────────────────┐    │
                                    │  │        rg-ai-apim               │    │
┌─────────────┐                     │  │                                 │    │
│  External   │    HTTPS/443        │  │  ┌─────────────────────────┐   │    │
│  Consumers  │ ───────────────────►│  │  │   apim-ai-lab           │   │    │
└─────────────┘                     │  │  │   (Standardv2)          │   │    │
                                    │  │  │                         │   │    │
                                    │  │  │  Gateway URL (public)   │   │    │
                                    │  │  │  Dev Portal (public)    │   │    │
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
                                    │  │  │  │ ApimIntegrationSubnet│   │  │ │
                                    │  │  │  │   (10.1.0.64/26)    │   │  │ │
                                    │  │  │  └─────────────────────┘   │  │ │
                                    │  │  │                             │  │ │
                                    │  │  │  ┌─────────────────────┐   │  │ │
                                    │  │  │  │ PrivateEndpointSubnet│   │  │ │
                                    │  │  │  │   (10.1.0.0/26)     │──►│ Private │
                                    │  │  │  └─────────────────────┘   │ Backends│
                                    │  │  └─────────────────────────────┘  │ │
                                    │  └────────────────────────────────────┘ │
                                    └─────────────────────────────────────────┘
```

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Azure CLI | Version 2.50.0 or later |
| Azure Subscription | With Contributor access |
| Core Infrastructure | `rg-ai-core` deployed with vWAN hub and shared services VNet |
| jq | For JSON processing |

### Provider Registrations

Ensure these providers are registered:
```bash
az provider register --namespace Microsoft.ApiManagement
az provider register --namespace Microsoft.Web
```

## Quick Start

### 1. Create Parameter File

```bash
cp bicep/apim/main.parameters.example.json bicep/apim/main.parameters.json
```

Edit `bicep/apim/main.parameters.json`:
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
./scripts/deploy-apim.sh
```

> **Note**: APIM deployment takes approximately 15-20 minutes.

### 3. Validate

```bash
./scripts/validate-apim.sh
```

### 4. Post-Deployment

Publish the developer portal:
```bash
az apim portalsetting update \
  --resource-group rg-ai-apim \
  --service-name apim-ai-lab
```

## Configuration

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `apimName` | `apim-ai-lab` | APIM instance name (globally unique) |
| `location` | `eastus2` | Azure region |
| `publisherEmail` | *required* | Publisher email address |
| `publisherName` | `AI-Lab` | Publisher organization name |
| `sku` | `Standardv2` | APIM pricing tier |
| `skuCapacity` | `1` | Number of scale units |
| `sharedServicesVnetName` | `vnet-ai-shared-services` | VNet for integration |
| `sharedServicesVnetResourceGroup` | `rg-ai-core` | VNet resource group |
| `apimSubnetPrefix` | `10.1.0.64/26` | APIM subnet CIDR |
| `vpnClientAddressPool` | `172.16.0.0/24` | VPN client CIDR for NSG |
| `enableVnetIntegration` | `true` | Enable VNet integration |

### Deployment Outputs

| Output | Description |
|--------|-------------|
| `apimName` | Deployed APIM instance name |
| `gatewayUrl` | Public gateway URL |
| `developerPortalUrl` | Developer portal URL |
| `managementUrl` | Management API URL |
| `principalId` | Managed identity principal ID |
| `apimSubnetId` | Integration subnet resource ID |

## Usage

### Import an API

1. Navigate to Azure Portal > API Management > APIs
2. Click "Add API" > Choose import method (OpenAPI, WSDL, etc.)
3. Configure backend URL pointing to private endpoint or internal service
4. Test from developer portal or gateway URL

### Apply Policies

Apply JWT validation for OAuth protection:

```xml
<policies>
    <inbound>
        <validate-jwt header-name="Authorization" 
                      failed-validation-httpcode="401" 
                      require-expiration-time="true">
            <openid-config url="https://login.microsoftonline.com/{tenant}/.well-known/openid-configuration" />
            <audiences>
                <audience>{your-api-audience}</audience>
            </audiences>
        </validate-jwt>
    </inbound>
</policies>
```

See [bicep/apim/policies/jwt-validation.xml](../bicep/apim/policies/jwt-validation.xml) for a template.

### Backend Connectivity

APIM can access backends through:
- **Private Endpoints**: Services in the shared services VNet
- **VNet Injection**: VMs or containers in connected VNets
- **Hub-Spoke Routing**: Resources in spoke VNets via vWAN hub

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy-apim.sh` | Deploy APIM with what-if validation |
| `validate-apim.sh` | Validate deployment status |
| `cleanup-apim.sh` | Remove APIM resources |

### Script Options

```bash
# What-if only (no deployment)
./scripts/deploy-apim.sh --what-if

# Skip confirmation
./scripts/deploy-apim.sh --auto-approve

# Custom parameter file
./scripts/deploy-apim.sh --parameter-file bicep/apim/main.parameters.prod.json

# Full cleanup including subnet
./scripts/cleanup-apim.sh --include-subnet
```

## Troubleshooting

### Deployment Failures

**APIM provisioning stuck or failed**
- Check Azure Activity Log for detailed errors
- Ensure subnet has correct delegation (`Microsoft.Web/serverFarms`)
- Verify NSG allows required outbound traffic

**Subnet delegation error**
```
The subnet 'ApimIntegrationSubnet' is not delegated to Microsoft.Web/serverFarms
```
Solution: The APIM-subnet module applies this delegation automatically. If upgrading, delete and recreate the subnet.

**Publisher email validation error**
```
Publisher email must be set
```
Solution: Set a valid email in the parameter file (not a placeholder).

### VNet Integration Issues

**APIM cannot reach backend services**
1. Verify APIM shows VNet integration in Azure Portal
2. Check NSG outbound rules allow VNet traffic
3. Ensure backend service allows inbound from APIM subnet

**DNS resolution failing**
1. Verify DNS resolver is deployed in core infrastructure
2. Check private DNS zones are linked to shared services VNet
3. Test resolution from APIM diagnostic console

### Gateway Errors

**504 Gateway Timeout**
- Backend service is not responding
- Check backend health and NSG rules

**401 Unauthorized**
- OAuth/JWT validation policy may be blocking requests
- Verify token format and audience

### VPN Access Issues

**Cannot access developer portal from VPN**
1. Verify VPN connection is established
2. Check NSG allows inbound from VPN client pool
3. Ensure developer portal is published

## Related Documentation

- [Core Infrastructure](../core-infrastructure/README.md)
- [VPN Client Setup](../core-infrastructure/vpn-client-setup.md)
- [DNS Resolver Setup](../core-infrastructure/dns-resolver-setup.md)

## Cost Estimation

| Resource | SKU | Estimated Monthly Cost |
|----------|-----|------------------------|
| API Management | Standardv2 (1 unit) | ~$175 USD |

*Costs vary by region and usage. Use Azure Pricing Calculator for accurate estimates.*

## Security Considerations

- ✅ TLS 1.2+ enforced (older protocols disabled)
- ✅ System-assigned managed identity for Azure service access
- ✅ NSG restricts outbound to required Azure services only
- ✅ OAuth/Entra ID for API authentication (post-deployment)
- ⚠️ Developer portal is public by default - consider access restrictions
