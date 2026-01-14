# Quickstart: Azure API Management Standard v2

**Feature**: 006-apim-std-v2  
**Time to Complete**: ~25-30 minutes (deployment + verification)

## Prerequisites

Before deploying APIM, ensure:

- [ ] Azure CLI 2.50.0+ installed
- [ ] Logged in to Azure (`az login`)
- [ ] Core infrastructure deployed (`rg-ai-core` with vWAN hub and shared services VNet)
- [ ] `jq` installed for JSON parsing

```bash
# Verify prerequisites
az --version | head -1
az account show --query name -o tsv
az group show --name rg-ai-core --query provisioningState -o tsv
```

## Quick Deploy

### 1. Create Parameters File

```bash
cd AI-Lab

# Copy example parameters
cp bicep/apim/main.parameters.example.json bicep/apim/main.parameters.json

# Edit with your publisher email
nano bicep/apim/main.parameters.json
```

**Required parameter**: Set `publisherEmail` to a valid email address.

### 2. Deploy APIM

```bash
./scripts/deploy-apim.sh
```

Deployment takes approximately 15-20 minutes.

### 3. Verify Deployment

```bash
./scripts/validate-apim.sh
```

## Post-Deployment

### Publish Developer Portal

The developer portal is enabled but not published by default:

```bash
# Via Azure Portal:
# 1. Navigate to API Management > Portal overview
# 2. Click "Publish"

# Or via CLI (publish portal content):
az apim update --name apim-ai-lab --resource-group rg-ai-apim \
  --set developerPortalStatus=Enabled
```

### Access Endpoints

| Endpoint | URL |
|----------|-----|
| Gateway | https://apim-ai-lab.azure-api.net |
| Developer Portal | https://apim-ai-lab.developer.azure-api.net |
| Management | https://apim-ai-lab.management.azure-api.net |

### Test Gateway (Echo API)

APIM includes a built-in Echo API for testing:

```bash
# Get subscription key from Azure Portal or:
SUBSCRIPTION_KEY=$(az apim subscription show \
  --resource-group rg-ai-apim \
  --service-name apim-ai-lab \
  --subscription-id "master" \
  --query primaryKey -o tsv)

# Test Echo API
curl -H "Ocp-Apim-Subscription-Key: $SUBSCRIPTION_KEY" \
  https://apim-ai-lab.azure-api.net/echo/resource
```

## Next Steps

1. **Configure OAuth** - Set up Entra ID authentication for APIs
2. **Import APIs** - Add backend APIs from Solution Projects
3. **Apply Policies** - Configure rate limiting, caching, transformations
4. **Monitor** - Set up Azure Monitor dashboards

## Cleanup

To remove APIM and all related resources:

```bash
./scripts/cleanup-apim.sh
```

## Troubleshooting

### Deployment Fails with Subnet Error

Ensure the APIM subnet is properly delegated:

```bash
az network vnet subnet update \
  --resource-group rg-ai-core \
  --vnet-name vnet-ai-shared \
  --name ApimIntegrationSubnet \
  --delegations Microsoft.Web/serverFarms
```

### VNet Integration Not Working

Check VNet integration status:

```bash
az apim show --name apim-ai-lab --resource-group rg-ai-apim \
  --query "virtualNetworkConfiguration" -o json
```

### Cannot Reach Private Endpoints

Verify DNS resolution from VPN client:

```bash
nslookup <private-endpoint-fqdn>
```

If not resolving, check DNS resolver configuration in core infrastructure.
