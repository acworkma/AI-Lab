# Azure OpenAI Legacy API (Private APIM)

Private APIM endpoint exposing the legacy Azure OpenAI service (`kind=OpenAI`) through managed identity authentication.

## Architecture

```
Client → Entra ID JWT → APIM (/aoai/...) → Managed Identity → Azure OpenAI (private) → gpt-4.1
```

| Component | Resource | Location |
|-----------|----------|----------|
| APIM Gateway | `apim-ai-lab-private` | rg-ai-apim-private |
| Azure OpenAI | `oai-ailab-private` | rg-ai-aoai (eastus2) |
| Private Endpoint | `pe-oai-ailab-private` | rg-ai-aoai |
| DNS Zone | `privatelink.openai.azure.com` | rg-ai-core |

## Endpoints

Base URL: `https://apim-ai-lab-private.azure-api.net/aoai`

| Operation | Method | Path |
|-----------|--------|------|
| Chat Completions | POST | `/deployments/{deployment-id}/chat/completions?api-version=2024-10-21` |
| List Models | GET | `/models?api-version=2024-10-21` |

## Authentication

Consumers authenticate with an Entra ID bearer token scoped to `https://cognitiveservices.azure.com`:

```bash
TOKEN=$(az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv)
```

APIM validates the JWT, then uses its own managed identity to call the backend. No API keys involved.

## Usage Examples

### PowerShell (Chat-AOAI.ps1)

```powershell
# Single message
.\scripts\Chat-AOAI.ps1 "What is Azure OpenAI?"

# Streaming
.\scripts\Chat-AOAI.ps1 -Stream "Tell me a joke"

# Interactive
.\scripts\Chat-AOAI.ps1
```

### curl

```bash
TOKEN=$(az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv)

curl -s https://apim-ai-lab-private.azure-api.net/aoai/deployments/gpt-4.1/chat/completions?api-version=2024-10-21 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"max_tokens":100}'
```

## Comparison with Foundry Path

| Feature | Foundry (`/openai`) | Legacy AOAI (`/aoai`) |
|---------|--------------------|-----------------------|
| Service Kind | AIServices (Foundry) | OpenAI (legacy) |
| Account | `fdryailabbzn6hg` | `oai-ailab-private` |
| Model | gpt-4.1 | gpt-4.1 |
| Auth | Managed Identity | Managed Identity |
| Network | Private Endpoint | Private Endpoint |
| Extra Features | Agents, Search, Storage | Model access only |

## Deployment

### Infrastructure

```bash
az deployment sub create \
  --location eastus2 \
  --template-file bicep/aoai-private/main.bicep \
  --parameters @bicep/aoai-private/main.parameters.json
```

### APIM API

```bash
az deployment group create \
  --resource-group rg-ai-apim-private \
  --template-file bicep/aoai-api-private/main.bicep
```

### RBAC (one-time)

```bash
APIM_ID=$(az apim show -n apim-ai-lab-private -g rg-ai-apim-private --query identity.principalId -o tsv)
AOAI_ID=$(az cognitiveservices account show -n oai-ailab-private -g rg-ai-aoai --query id -o tsv)
az role assignment create --role "Cognitive Services User" --assignee-object-id $APIM_ID --assignee-principal-type ServicePrincipal --scope $AOAI_ID
```
