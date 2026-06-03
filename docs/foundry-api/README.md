# Foundry LLM API (Private)

## Overview

Exposes Azure AI Foundry's OpenAI-compatible endpoints through the private APIM gateway. Consumers access `gpt-4.1` (and other models) via a governed, private endpoint without needing direct Foundry credentials.

## Architecture

```
Consumer (VPN/VNet)
  → APIM Private Endpoint (apim-ai-lab-private.azure-api.net/openai)
  → Entra ID JWT validation
  → APIM managed identity acquires Cognitive Services token
  → Foundry Private Endpoint (fdryailabbzn6hg.cognitiveservices.azure.com)
  → gpt-4.1 model deployment
```

**Key design:**
- **No API keys** — APIM uses its system-assigned managed identity
- **Entra ID auth** — Consumers authenticate with OAuth 2.0 bearer tokens
- **SSE streaming** — Response buffering disabled for real-time chat streaming
- **Fully private** — All traffic stays on the VNet (no public endpoints)

## Prerequisites

- Private APIM deployed (`apim-ai-lab-private` in `rg-ai-apim-private`)
- Private Foundry deployed (`fdryailabbzn6hg` in `rg-ai-foundry`)
- APIM managed identity granted `Cognitive Services User` on the Foundry account
- VPN connected (for testing from client machines)

## Deploy

```bash
./scripts/deploy-foundry-api-private.sh
```

## API Endpoints

Base URL: `https://apim-ai-lab-private.azure-api.net/openai`

| Method | Path | Description |
|--------|------|-------------|
| POST | `/deployments/{deployment-id}/chat/completions` | Chat completions (streaming supported) |
| GET | `/models` | List available model deployments |

### Chat Completions Example

```bash
TOKEN=$(az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv)

curl -X POST "https://apim-ai-lab-private.azure-api.net/openai/deployments/gpt-4.1/chat/completions?api-version=2024-10-21" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'
```

### Streaming Example

```bash
curl -X POST "https://apim-ai-lab-private.azure-api.net/openai/deployments/gpt-4.1/chat/completions?api-version=2024-10-21" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -N \
  -d '{
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": true
  }'
```

## Authentication

Consumers must present a valid Entra ID bearer token with audience `https://cognitiveservices.azure.com` from tenant `38c1a7b0-f16b-45fd-a528-87d8720e868e`.

Acquire a token:
```bash
az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv
```

## Validate

```bash
./scripts/test-foundry-api.sh
```

## Cleanup

Remove the API from APIM:
```bash
az apim api delete --api-id foundry-llm-api \
  --resource-group rg-ai-apim-private \
  --service-name apim-ai-lab-private --yes
```
