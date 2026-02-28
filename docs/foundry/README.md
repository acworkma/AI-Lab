# Private Foundry

## Overview

This project deploys Private Foundry infrastructure aligned with Azure AI Foundry Agent Service network-secured deployment guidance. The design follows AI-Lab patterns while preserving strict Learn/sample cleanup behavior.

This implementation includes:
- Foundry account (AIServices) with model deployment
- Foundry project and AAD connections to dedicated Search/Storage/Cosmos
- Dedicated private endpoints for Foundry, Search, Storage, Cosmos
- Centralized private DNS zone-group integration in core DNS resource group
- RBAC assignments required for capability-host and data access workflows
- Account and project capability host deployment (Agents)
- Strict cleanup/caphost helper scripts

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
./scripts/validate-foundry.sh --ops
./scripts/validate-foundry.sh --ops --strict
./scripts/validate-foundry-dns.sh <fqdn1> <fqdn2> ...
./scripts/test-foundry-inference.sh --prompt "Say hello from private Foundry"
```

Validation script checks include:
- Delegated subnet + PE subnet configuration
- Required private DNS zones in core resource group
- Foundry account + project resources
- Account and project capability hosts
- Dedicated Search/Storage/Cosmos resources
- Public network access disabled on all key resources
- Minimum private endpoint count

Operational (`--ops`) checks include:
- Account/project capability host API state and configured connection bindings
- RBAC assignments on Search/Storage/Cosmos account scope
- Post-capability-host RBAC signals (Storage Data Owner, Cosmos SQL role assignment)
- Private endpoint provisioning state consistency

Inference probe checks (`test-foundry-inference.sh`):
- Auto-discovers Foundry account + model deployment (or accepts explicit overrides)
- Verifies endpoint DNS resolution (private IP by default)
- Acquires Azure AD token and calls chat completions data-plane endpoint
- Prints model response and exits non-zero on network/auth/inference errors

Strict mode (`--strict`):
- Treats warnings as failures for CI/pipeline enforcement
- Passes strict behavior through to operational checks when `--ops` is used

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

