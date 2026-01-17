# AI-Lab Development Guidelines

Auto-generated from all feature plans. Last updated: 2025-12-31

## Active Technologies
- Bicep (Azure IaC) + Azure CLI 2.50.0+, jq (006-apim-std-v2)
- N/A (stateless gateway) (006-apim-std-v2)
- Bicep (Azure Resource Manager) + Azure CLI ≥2.50, Bicep CLI (bundled), Core infrastructure (rg-ai-core) (008-private-keyvault)
- N/A (Key Vault is the storage layer for secrets) (008-private-keyvault)
- Azure Storage Account (StorageV2, Standard_LRS, blob only) (009-private-storage)

- Bicep (latest stable version compatible with Azure CLI) + Azure CLI (az deployment), Azure Virtual WAN, Azure VPN Gateway, Azure Key Vault (001-vwan-core)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for Bicep (latest stable version compatible with Azure CLI)

## Code Style

Bicep (latest stable version compatible with Azure CLI): Follow standard conventions

## Recent Changes
- 009-private-storage: Added Bicep (Azure Resource Manager) + Azure CLI ≥2.50, Bicep CLI (bundled), Core infrastructure (rg-ai-core)
- 008-private-keyvault: Added Bicep (Azure Resource Manager) + Azure CLI ≥2.50, Bicep CLI (bundled), Core infrastructure (rg-ai-core)
- 006-apim-std-v2: Added Bicep (Azure IaC) + Azure CLI 2.50.0+, jq


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
