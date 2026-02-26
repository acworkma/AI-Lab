# Private Foundry (In Progress)

## Overview

This project introduces Private Foundry infrastructure aligned with Azure AI Foundry Agent Service network-secured deployment guidance. The design follows AI-Lab patterns while preserving strict Learn/sample cleanup behavior.

Current implementation status:
- Phase 1 baseline complete: dedicated Foundry networking primitives in shared VNet
- Delegated subnet for agent infrastructure (`Microsoft.App/environments`)
- Dedicated private endpoint subnet for Foundry dependencies
- Validation scripts and strict cleanup/caphost helper scripts added

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

- Add Foundry account/project resources (AIServices + project)
- Add dedicated Search/Storage/Cosmos deployments for Foundry
- Add private endpoints and DNS group associations
- Add RBAC sequencing (pre/post capability host) from sample module flow
