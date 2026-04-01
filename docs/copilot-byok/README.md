# GitHub Copilot BYOK (Bring Your Own Key)

Enable GitHub Copilot Enterprise to use a custom Azure AI Foundry model by exposing it through APIM with subscription key authentication.

## Overview

This Solution Project deploys:
- **Chat model** (`gpt-5.2`) on the existing Foundry account
- **APIM API** with native Foundry URL pattern for OpenAI-compatible chat/completions
- **APIM product** ("GitHub Copilot") with subscription key requirement
- **RBAC assignment** — APIM managed identity → Cognitive Services OpenAI User on Foundry
- **Rate limiting** — 60 requests/minute per subscription key

### Architecture

```
┌──────────────────────┐
│   GitHub Copilot     │
│   Enterprise         │
│                      │
│  Model: custom       │
│  Provider: Foundry   │
└──────────┬───────────┘
           │ HTTPS + api-key header
           │ (APIM subscription key)
           ▼
┌──────────────────────────────────────────────────────┐
│                    Azure Cloud                        │
│                                                       │
│  ┌────────────────────────────────────┐               │
│  │          rg-ai-apim                │               │
│  │                                    │               │
│  │  ┌──────────────────────────────┐  │               │
│  │  │   apim-ai-lab (Standardv2)  │  │               │
│  │  │                              │  │               │
│  │  │  Product: "GitHub Copilot"   │  │               │
│  │  │  API: copilot-byok-api       │  │               │
│  │  │  Rate limit: 60 req/min      │  │               │
│  │  │                              │  │               │
│  │  │  Policy:                     │  │               │
│  │  │  1. Validate subscription key│  │               │
│  │  │  2. Acquire MI token         │  │               │
│  │  │  3. Forward to Foundry       │  │               │
│  │  └──────────────┬───────────────┘  │               │
│  └─────────────────│──────────────────┘               │
│                    │ VNet Integration                  │
│  ┌─────────────────▼──────────────────────────────┐   │
│  │          rg-ai-core                             │   │
│  │  ┌──────────────────────────────────────────┐  │   │
│  │  │  vnet-ai-shared                          │  │   │
│  │  │                                          │  │   │
│  │  │  ApimIntegrationSubnet ──► PE Subnet     │  │   │
│  │  │                           │              │  │   │
│  │  └───────────────────────────│──────────────┘  │   │
│  └──────────────────────────────│──────────────────┘   │
│                                 │ Private Endpoint      │
│  ┌──────────────────────────────▼──────────────────┐   │
│  │          rg-ai-foundry                           │   │
│  │                                                  │   │
│  │  ┌──────────────────────────────────────────┐   │   │
│  │  │  fdryailab{suffix}                       │   │   │
│  │  │  (AI Services, S0)                       │   │   │
│  │  │                                          │   │   │
│  │  │  Models:                                 │   │   │
│  │  │  ├── gpt-4.1 (existing, untouched)       │   │   │
│  │  │  └── gpt-5.2 (new, 30 TPM)   │   │   │
│  │  └──────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

### Auth Flow

1. **GitHub → APIM**: GitHub Copilot sends requests with the APIM subscription key in the `api-key` header
2. **APIM validates**: Subscription key checked against the "GitHub Copilot" product
3. **APIM → Foundry**: APIM acquires an Azure AD token via its managed identity for the `https://cognitiveservices.azure.com/` audience
4. **Foundry processes**: Request forwarded to the `gpt-5.2` model deployment
5. **Response**: Model response flows back through APIM to GitHub Copilot

**Key security properties**:
- GitHub never receives direct Foundry credentials
- Foundry remains private (no public access)
- APIM managed identity is the only authorized caller
- Subscription key can be rotated independently

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Azure CLI | Version 2.50.0+ |
| jq | For JSON processing |
| Core Infrastructure | `rg-ai-core` with VNet, DNS, VPN |
| Foundry | `rg-ai-foundry` with Foundry account deployed |
| APIM | `rg-ai-apim` with APIM Standard v2 deployed |
| GitHub Enterprise | With Copilot Enterprise subscription |

## Quick Start

### 1. Deploy

```bash
./scripts/deploy-copilot-byok.sh
```

This deploys the Foundry model, RBAC, and APIM resources in sequence. On success, it writes the subscription key and gateway URL to `.env`.

### 2. Verify

```bash
# Infrastructure validation
./scripts/validate-copilot-byok.sh

# End-to-end API test
./scripts/validate-copilot-byok.sh --e2e
```

### 3. Configure GitHub Enterprise

1. Navigate to your [GitHub Enterprise](https://github.com/settings/enterprises) → **AI controls** → **Copilot**
2. Click **Configure allowed models** → **Custom models** tab
3. Click **Add API key**
4. Fill in:
   - **Provider**: Microsoft Foundry
   - **Name**: AI-Lab Codex (or your preferred display name)
   - **API Key**: `source .env && echo $APIM_SUBSCRIPTION_KEY`
   - **Deployment URL**: `source .env && echo "https://$APIM_GATEWAY_URL/openai/deployments"`
5. Under **Available models**, type `gpt-5.2` and click **Add model**
6. Click **Save**
7. Optionally configure organization access under the **Access** tab

> **Reference**: [GitHub Docs — Using your LLM provider API keys with Copilot](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-for-enterprise/use-your-own-api-keys)

## Configuration

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `foundryAccountName` | *auto-discovered* | Existing Foundry account name |
| `apimName` | `apim-ai-lab-0115` | Existing APIM instance name |
| `modelName` | `gpt-5.2` | Codex model deployment name |
| `modelCapacity` | `30` | TPM (tokens per minute) capacity |
| `modelSkuName` | `GlobalStandard` | Model SKU tier |
| `apiPath` | `openai` | APIM API path prefix |
| `productDisplayName` | `GitHub Copilot` | APIM product display name |

### Rate Limiting

Rate limiting is configured at 60 requests per minute per subscription key. To adjust:

1. Edit `bicep/copilot-byok/policies/managed-identity-auth.xml`
2. Change the `calls` attribute on the `rate-limit-by-key` element
3. Re-deploy: `./scripts/deploy-copilot-byok.sh --auto-approve`

### Model Capacity

The default capacity is 30 TPM (GlobalStandard). To scale:

```bash
az cognitiveservices account deployment show \
    --name <foundry-account> \
    --resource-group rg-ai-foundry \
    --deployment-name gpt-5.2

# Update capacity via Azure Portal or redeploy with modified parameter
```

## Deployment Outputs

| Output | Description |
|--------|-------------|
| `APIM_SUBSCRIPTION_KEY` | Subscription key for the GitHub Copilot product (written to `.env`) |
| `APIM_GATEWAY_URL` | APIM public gateway hostname (written to `.env`) |
| `FOUNDRY_DEPLOYMENT_NAME` | Model deployment name (`gpt-5.2`) |
| `deploymentUrl` | Full deployment URL for GitHub Enterprise configuration |

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy-copilot-byok.sh` | Full deployment (model + RBAC + APIM), outputs to `.env` |
| `validate-copilot-byok.sh` | Validate all resources and optionally test end-to-end |

### Script Options

```bash
# Deploy with auto-approve (no confirmation prompt)
./scripts/deploy-copilot-byok.sh --auto-approve

# What-if analysis only (no actual deployment)
./scripts/deploy-copilot-byok.sh --what-if

# Validate with end-to-end API test
./scripts/validate-copilot-byok.sh --e2e

# Strict mode (warnings = failures)
./scripts/validate-copilot-byok.sh --strict
```

## Security Considerations

| Area | Approach |
|------|----------|
| **Foundry access** | Remains private — no public network access. Only APIM can reach it via VNet + private endpoint. |
| **Authentication to Foundry** | APIM managed identity with `Cognitive Services OpenAI User` role. No shared keys or secrets. |
| **Inbound authentication** | APIM subscription key validated per-request. GitHub sends this as the `api-key` header. |
| **Key storage** | Subscription key stored in `.env` (gitignored). `.env.example` template is checked in. |
| **Rate limiting** | 60 req/min per subscription key to prevent abuse and control costs. |
| **Key rotation** | Regenerate the APIM subscription key via Azure Portal or CLI. Update in GitHub Enterprise settings. |
| **Network path** | GitHub → APIM (public gateway) → VNet integration → private endpoint → Foundry. No direct Foundry exposure. |

### Subscription Key Rotation

```bash
# Regenerate primary key
az rest --method post \
    --uri "/subscriptions/{sub-id}/resourceGroups/rg-ai-apim/providers/Microsoft.ApiManagement/service/apim-ai-lab-0115/subscriptions/github-copilot-byok/regeneratePrimaryKey?api-version=2023-09-01-preview"

# Get the new key
az rest --method post \
    --uri "/subscriptions/{sub-id}/resourceGroups/rg-ai-apim/providers/Microsoft.ApiManagement/service/apim-ai-lab-0115/subscriptions/github-copilot-byok/listSecrets?api-version=2023-09-01-preview" \
    --query "primaryKey" -o tsv

# Update .env and GitHub Enterprise settings with the new key
```

## Cost Estimation

| Resource | SKU | Estimated Monthly Cost |
|----------|-----|----------------------|
| APIM Standard v2 | 1 unit (existing) | $0 incremental (shared) |
| Foundry model | GlobalStandard, 30 TPM | Pay-per-token (usage-based) |
| RBAC assignment | — | Free |
| Subscription | — | Free |

> **Note**: The primary cost driver is token consumption on the Foundry model. APIM costs are shared with other APIs on the same instance.

## Troubleshooting

### Deployment Issues

**Foundry model deployment fails**
```
Model 'gpt-5.2' is not available in region 'eastus2'
```
Solution: Check model availability in your region via `az cognitiveservices model list --location eastus2`. You may need a different model version or region.

**RBAC assignment conflict**
```
The role assignment already exists
```
This is safe to ignore — the Bicep template uses a deterministic GUID, so redeployment will detect the existing assignment.

### Runtime Issues

**401 Unauthorized (no key)**
- GitHub is not sending the subscription key
- Verify the API key is configured correctly in GitHub Enterprise settings

**401 Unauthorized (invalid key)**
- Subscription key has been rotated or is incorrect
- Regenerate and update in GitHub Enterprise settings

**502 Bad Gateway**
- APIM managed identity cannot authenticate to Foundry
- Check: `az role assignment list --assignee <apim-principal-id> --scope <foundry-id>`
- Solution: Re-run `deploy-copilot-byok.sh` to reassign RBAC

**429 Too Many Requests**
- Rate limit exceeded (60 req/min)
- Wait for the `Retry-After` period or increase the limit in the policy XML

**504 Gateway Timeout**
- Foundry is not responding or network path is broken
- Check Foundry deployment status: `az cognitiveservices account deployment list --name <account> --resource-group rg-ai-foundry`
- Verify VNet routing: APIM subnet → PE subnet → Foundry private endpoint

**DNS resolution failure**
- Private DNS zone for `cognitiveservices.azure.com` may not be linked to VNet
- Validate: `./scripts/validate-foundry-dns.sh`

### GitHub Configuration Issues

**Model not appearing in Copilot Chat picker**
- Ensure the model is in "Enabled" state in GitHub Enterprise settings
- Check organization access — the model may need to be allowed for specific orgs
- It may take a few minutes for changes to propagate

**"Error connecting to model" in Copilot Chat**
- Verify the deployment URL is correct: `https://<apim-gateway-url>/openai/deployments`
- Verify the API key is the APIM subscription key (not a Foundry key)
- Test the endpoint manually with curl (see Quick Start step 2)

## Cleanup

To remove the BYOK solution without affecting other infrastructure:

```bash
# Remove APIM resources (API, product, subscription)
az apim api delete --resource-group rg-ai-apim --service-name apim-ai-lab-0115 --api-id copilot-byok-api --yes
az apim product delete --resource-group rg-ai-apim --service-name apim-ai-lab-0115 --product-id github-copilot --yes --delete-subscriptions

# Remove Foundry model deployment
az cognitiveservices account deployment delete \
    --name <foundry-account> \
    --resource-group rg-ai-foundry \
    --deployment-name gpt-5.2

# Remove RBAC assignment (optional — harmless to leave)
az role assignment delete --assignee <apim-principal-id> --scope <foundry-account-id> --role "Cognitive Services OpenAI User"

# Remove .env
rm -f .env
```

> **Note**: Don't forget to also remove the API key from GitHub Enterprise settings.

## Related Documentation

- [APIM Infrastructure](../apim/README.md)
- [Foundry Infrastructure](../foundry/README.md)
- [Core Infrastructure](../core-infrastructure/README.md)
- [GitHub Docs — BYOK with Copilot](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-for-enterprise/use-your-own-api-keys)
