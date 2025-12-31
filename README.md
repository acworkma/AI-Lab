# AI-Lab

Azure Infrastructure Lab for building and demonstrating Azure services using Infrastructure as Code (Bicep).

## 🎯 Overview

This repository contains modular Azure infrastructure deployed as independent labs, all connected through a centralized Virtual WAN hub with **Microsoft Entra Global Secure Access** integration. All infrastructure is defined using Bicep templates following Infrastructure as Code (IaC) best practices.

### Key Features

- ✅ **Hub-Spoke Network Topology**: Centralized vWAN hub with spoke virtual networks
- ✅ **Global Secure Access**: Security Service Edge (SSE) integration for zero-trust access
- ✅ **Infrastructure as Code**: 100% Bicep, no manual portal changes
- ✅ **Centralized Secrets**: Azure Key Vault with RBAC for all labs
- ✅ **Modular Labs**: Independently deployable and deletable spoke labs
- ✅ **Constitutional Governance**: 7 core principles enforced across all infrastructure

## 🏗️ Architecture

**Hub-Spoke Network Topology**:
- **Core Hub** (`rg-ai-core`): Virtual WAN hub with site-to-site VPN Gateway for Global Secure Access integration
- **Spoke Labs**: Independent service labs (e.g., `rg-ai-storage`, `rg-ai-ml`) connected to the hub
- **Centralized Security**: Azure Key Vault in core for secrets management across all labs

### Global Secure Access Integration

The core infrastructure integrates with **Microsoft Entra Global Secure Access** to provide Security Service Edge (SSE) capabilities:
- **Private Access**: Secure access to private Azure resources
- **Internet Access**: Secure web access with threat protection
- **Microsoft 365 Access**: Optimized connectivity to Microsoft services
- **Zero Trust**: Conditional access policies and continuous evaluation

**Architecture Diagram**: See [docs/core-infrastructure/architecture-diagram.md](docs/core-infrastructure/architecture-diagram.md)

## 🚀 Quick Start

### Prerequisites

- Azure CLI 2.50.0 or later ([Install](https://aka.ms/azure-cli))
- Azure subscription with Contributor role
- jq (for JSON parsing in scripts)

### Deploy Core Infrastructure

```bash
# 1. Clone repository
git clone https://github.com/acworkma/AI-Lab.git
cd AI-Lab

# 2. Login to Azure
az login

# 3. Customize parameters
nano bicep/main.parameters.json
# Change keyVaultName to a globally unique value

# 4. Deploy core infrastructure (25-30 minutes)
./scripts/deploy-core.sh

# 5. Validate deployment
./scripts/validate-core.sh
```

**Full Documentation**: [docs/core-infrastructure/README.md](docs/core-infrastructure/README.md)

### Configure Global Secure Access (Optional)

Follow the step-by-step guide to integrate with Microsoft Entra Global Secure Access:

[docs/core-infrastructure/global-secure-access.md](docs/core-infrastructure/global-secure-access.md)

### Deploy Spoke Labs

After core infrastructure is deployed, add spoke labs following the contributing guide:

[CONTRIBUTING.md](CONTRIBUTING.md)

## 📁 Project Structure

```
bicep/                      # Bicep Infrastructure as Code
├── modules/               # Reusable Bicep modules
│   ├── resource-group.bicep
│   ├── vwan-hub.bicep
│   ├── vpn-gateway.bicep
│   └── key-vault.bicep
├── main.bicep            # Main orchestration template
└── main.parameters.json  # Default parameters

scripts/                   # Deployment automation
├── deploy-core.sh        # Deploy core infrastructure
├── validate-core.sh      # Validate deployment
└── cleanup-core.sh       # Clean up resources

docs/                      # Documentation
└── core-infrastructure/  # Core hub documentation
    ├── README.md
    ├── architecture-diagram.md
    ├── global-secure-access.md
    └── troubleshooting.md

specs/                     # Feature specifications (Speckit)
└── 001-vwan-core/        # Core vWAN feature
    ├── spec.md
    ├── plan.md
    ├── tasks.md
    └── ...
```

## Quick Start

### Prerequisites

- Azure CLI installed (`az --version`)
- Azure subscription with Contributor permissions
- Git for cloning repository

### Deploy Core Infrastructure

```bash
# Clone repository
git clone https://github.com/acworkma/AI-Lab.git
cd AI-Lab

# Login to Azure
az login

# Deploy core hub infrastructure
./scripts/deploy-core.sh

# Validate deployment
./scripts/validate-core.sh
```

See [docs/core-infrastructure/README.md](docs/core-infrastructure/README.md) for detailed deployment instructions.

## Governance

This project follows strict Infrastructure as Code principles defined in the [Constitution](.specify/memory/constitution.md):

1. **Bicep Only**: All Azure resources defined in Bicep templates
2. **No Manual Changes**: Portal modifications prohibited
3. **Version Control**: All infrastructure tracked in Git
4. **No Secrets in Source**: Secrets stored in Azure Key Vault only
5. **Hub-Spoke Architecture**: Core hub deployed first, spoke labs connect to hub
6. **Modular Design**: Each lab independently deployable and deletable

## Resource Naming Convention

- Resource Groups: `rg-ai-[service]` (e.g., `rg-ai-core`, `rg-ai-storage`)
- Required Tags: `environment`, `purpose`, `owner`

## 📖 Documentation

- **[Core Infrastructure Guide](docs/core-infrastructure/README.md)**: Complete deployment and configuration guide
- **[Architecture Diagram](docs/core-infrastructure/architecture-diagram.md)**: Network topology and data flow
- **[Global Secure Access Integration](docs/core-infrastructure/global-secure-access.md)**: SSE configuration steps
- **[Troubleshooting Guide](docs/core-infrastructure/troubleshooting.md)**: Common issues and solutions
- **[Contributing Guide](CONTRIBUTING.md)**: How to add new spoke labs
- **[Constitution](.specify/memory/constitution.md)**: Governance principles and standards

## 🛠️ Available Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `deploy-core.sh` | Deploy core infrastructure | `./scripts/deploy-core.sh` |
| `validate-core.sh` | Validate deployment | `./scripts/validate-core.sh` |
| `cleanup-core.sh` | Delete all resources | `./scripts/cleanup-core.sh` |
| `scan-secrets.sh` | Scan for hardcoded secrets | `./scripts/scan-secrets.sh` |

## 💡 Common Tasks

### Validate Deployment

```bash
# Check all resources and configuration
./scripts/validate-core.sh

# Check for secrets in repository
./scripts/scan-secrets.sh
```

### Store Secret in Key Vault

```bash
# Example: VPN shared key
az keyvault secret set \
  --vault-name kv-ai-core-lab1 \
  --name vpn-shared-key \
  --value "$(openssl rand -base64 32)"
```

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on adding new spoke labs.

**Before submitting a PR**:
1. ✅ Follow the [constitution](.specify/memory/constitution.md)
2. ✅ Run `./scripts/scan-secrets.sh` (must pass)
3. ✅ Validate Bicep with `az bicep build`
4. ✅ Document address space allocation

## 📝 License

[MIT License](LICENSE) - Feel free to use this infrastructure pattern for your own projects.

## 🙋 Support

- **Documentation**: See [docs/core-infrastructure/](docs/core-infrastructure/)
- **Issues**: Open a [GitHub Issue](https://github.com/acworkma/AI-Lab/issues)
- **Discussions**: Join [GitHub Discussions](https://github.com/acworkma/AI-Lab/discussions)

---

**Built with ❤️ using Bicep and Azure Virtual WAN**

**Status**: ✅ Production Ready | **Version**: 1.0.0 | **Last Updated**: 2025-12-31
- Virtual WAN: `vwan-ai-hub`
- Virtual Hub: `hub-ai-eastus2`
- VPN Gateway: `vpngw-ai-hub`
- Key Vault: `kv-ai-core-{random}`

## Security

**Critical**: Never commit secrets, passwords, API keys, or connection strings to this repository.

- Secrets must be stored in Azure Key Vault (`kv-ai-core-*`)
- Local parameter files (`*.local.parameters.json`) are gitignored
- Parameter files use Key Vault references for sensitive values
- Review [Security Guidelines](docs/core-infrastructure/README.md#security) before deployment

## Deployment Workflow

1. **Core Infrastructure**: Deploy vWAN hub, VPN Gateway, and Key Vault (required first)
2. **Global Secure Access**: Configure Microsoft Entra Global Secure Access integration
3. **Spoke Labs**: Deploy individual service labs that connect to hub
4. **Validation**: Run validation scripts to verify configuration

## Contributing

New lab deployments should:
1. Create new resource group: `rg-ai-[service-name]`
2. Deploy resources in separate resource group
3. Connect to vWAN hub via VNet connection
4. Reference Key Vault for secrets: `kv-ai-core-*`
5. Follow naming conventions and tagging requirements

See CONTRIBUTING.md for detailed guidelines.

## Troubleshooting

Common issues and solutions:
- [Core Infrastructure Troubleshooting](docs/core-infrastructure/troubleshooting.md)
- [Global Secure Access Integration](docs/core-infrastructure/global-secure-access.md)

## License

This project is for demonstration and learning purposes.

## Resources

- [Azure Virtual WAN Documentation](https://learn.microsoft.com/en-us/azure/virtual-wan/)
- [Microsoft Entra Global Secure Access](https://learn.microsoft.com/en-us/entra/global-secure-access/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Project Constitution](.specify/memory/constitution.md)
