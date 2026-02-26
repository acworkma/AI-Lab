# Private Foundry (Phase 2 In Progress)

## Overview

This project introduces Private Foundry infrastructure aligned with Azure AI Foundry Agent Service network-secured deployment guidance. The design follows AI-Lab patterns while preserving strict Learn/sample cleanup behavior.

Current implementation status:
- Phase 1 complete: dedicated Foundry networking primitives in shared VNet
- Phase 2 baseline complete:
  - Foundry account (AIServices) with model deployment
  - Foundry project and AAD connections to dedicated Search/Storage/Cosmos
  - Dedicated private endpoints for Foundry, Search, Storage, Cosmos
  - Centralized private DNS zone-group integration in core DNS resource group
  - Pre-capability-host RBAC assignments for Search, Storage, Cosmos account scope
- Strict cleanup/caphost helper scripts added

## Prerequisites

- Core infrastructure deployed (`rg-ai-core`, `vnet-ai-shared`, centralized private DNS)
- Azure CLI and jq installed
- Required providers registered:
  - Microsoft.KeyVault
  - Microsoft.CognitiveServices
  - Microsoft.Storage
  - Microsoft.MachineLearningServices
  - Microsoft.Search
  - Microsoft.Network
  - Microsoft.App
  - Microsoft.ContainerService

## Deploy

```bash
./scripts/deploy-foundry.sh
```

## Validate

```bash
./scripts/validate-foundry.sh
./scripts/validate-foundry-dns.sh <fqdn1> <fqdn2> ...
```

## Cleanup (Strict Learn/Sample Order)

1. Delete project capability host
2. Delete account capability host
3. Delete and purge account
4. Wait for unlink completion (up to ~20 minutes)
5. Delete Foundry resource group
6. Delete Foundry subnets only after unlink (optional)

```bash
./scripts/cleanup-foundry.sh \
  --subscription-id <sub-id> \
  --account-name <foundry-account-name> \
  --project-caphost-name <project-caphost-name> \
  --account-caphost-name <account-caphost-name> \
  --delete-network
```

## Next Implementation Steps

- Add capability host deployment sequencing in Bicep for project-level host
- Add post-capability-host RBAC for storage containers and Cosmos SQL containers
- Add richer operational validation (agent create/run workflow checks)
