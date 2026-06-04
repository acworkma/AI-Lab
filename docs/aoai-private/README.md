# Private Azure OpenAI (Legacy)

## Overview

This project deploys a legacy Azure OpenAI service (`kind=OpenAI`) with full private networking. It provides direct model access without the Foundry platform overhead — useful for scenarios that only need chat completions / embeddings.

This implementation includes:
- Azure OpenAI account (kind=OpenAI, S0) with public access disabled
- gpt-4.1 model deployment (Standard SKU)
- Private endpoint in shared VNet (PrivateEndpointSubnet)
- DNS zone group linking to centralized `privatelink.openai.azure.com`

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ rg-ai-aoai                                          │
│                                                     │
│  ┌─────────────────────┐   ┌─────────────────────┐ │
│  │ oai-ailab-private    │   │ pe-oai-ailab-private │ │
│  │ (OpenAI, S0)        │◄──│ (Private Endpoint)   │ │
│  │ gpt-4.1 deployment  │   └──────────┬──────────┘ │
│  │ Public: Disabled     │              │            │
│  └─────────────────────┘              │            │
└────────────────────────────────────────┼────────────┘
                                         │
┌────────────────────────────────────────┼────────────┐
│ rg-ai-core                             │            │
│  vnet-ai-shared (10.1.0.0/22)         │            │
│  └── PrivateEndpointSubnet ◄───────────┘            │
│                                                     │
│  privatelink.openai.azure.com (DNS zone)            │
│  └── oai-ailab-private → 10.1.0.21                 │
└─────────────────────────────────────────────────────┘
```

## Prerequisites

- Core infrastructure deployed (`rg-ai-core`, `vnet-ai-shared`, DNS zones)
- Azure CLI logged in
- `privatelink.openai.azure.com` DNS zone exists in `rg-ai-core`

## Deploy

```bash
./scripts/deploy-aoai-private.sh
```

Options:
- `--skip-whatif` — Skip the what-if preview
- `--auto-approve` — No confirmation prompt
- `--what-if` — Preview only, no deployment

## Validate

```bash
./scripts/validate-aoai-private.sh
./scripts/validate-aoai-private.sh --ops   # includes inference test
```

## Cleanup

```bash
./scripts/cleanup-aoai-private.sh
./scripts/cleanup-aoai-private.sh --auto-approve
```

## Resources Deployed

| Resource | Name | Type |
|----------|------|------|
| Resource Group | `rg-ai-aoai` | Microsoft.Resources/resourceGroups |
| OpenAI Account | `oai-ailab-private` | Microsoft.CognitiveServices/accounts (kind=OpenAI) |
| Model Deployment | `gpt-4.1` | Microsoft.CognitiveServices/accounts/deployments |
| Private Endpoint | `pe-oai-ailab-private` | Microsoft.Network/privateEndpoints |
| DNS Zone Group | default | Microsoft.Network/privateEndpoints/privateDnsZoneGroups |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `location` | eastus2 | Azure region |
| `resourceGroupName` | rg-ai-aoai | Resource group name |
| `accountName` | oai-ailab-private | OpenAI account name |
| `modelName` | gpt-4.1 | Model to deploy |
| `modelVersion` | 2025-04-14 | Model version |
| `deploymentCapacity` | 10 | TPM in thousands |
| `coreResourceGroupName` | rg-ai-core | Shared infra RG |
| `vnetName` | vnet-ai-shared | Shared VNet |
| `privateEndpointSubnetName` | PrivateEndpointSubnet | PE subnet |

## Comparison with Foundry

| Feature | This Project (Legacy AOAI) | Foundry |
|---------|---------------------------|---------|
| Service Kind | OpenAI | AIServices |
| Complexity | Low (account + model only) | High (project, agents, search, storage) |
| Capabilities | Chat, completions, embeddings | Full platform (agents, RAG, tools) |
| Deploy Time | ~2 minutes | ~15 minutes |
| Use Case | Simple LLM access | Full AI platform |
