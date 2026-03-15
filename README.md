# AI-Lab

Azure Infrastructure Lab for building and demonstrating Azure services using Infrastructure as Code (Bicep).

## 🎯 Overview

AI-Lab is a collection of modular Azure infrastructure projects, all connected through a centralized **Virtual WAN hub** for secure networking and remote access. Each project is independently deployable, fully documented, and follows Infrastructure as Code (IaC) best practices.

### Core Concept: Hub-Spoke Architecture

```
                    ┌───────────────────────┐
                    │  Remote VPN Clients   │
                    │   (Entra ID Auth)     │
                    └─────────┬─────────────┘
                              │
                    ┌─────────▼─────────────┐
                    │   Virtual WAN Hub     │
                    │     (rg-ai-core)      │
                    │  • P2S VPN Gateway    │
                    │  • DNS Resolver       │
                    └─────────┬─────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
         ┌────▼────┐    ┌─────▼────┐    ┌────▼────┐
         │ Project │    │ Project  │    │ Project │
         │   #1    │    │   #2     │    │   #3    │
         │ (Spoke) │    │ (Spoke)  │    │ (Spoke) │
         └─────────┘    └──────────┘    └─────────┘
```

**Benefits**:
- 🔒 **Centralized Security**: Single VPN gateway for all projects
- 🔌 **Easy Connectivity**: New projects auto-connect to the hub
- 🧩 **Modular Design**: Deploy/delete projects independently
- 🎛️ **Simplified Management**: One hub to rule them all

## 📚 Projects

### 🏗️ Core Infrastructure (Foundation)

**Status**: ✅ Ready  
**Location**: [`docs/core-infrastructure/`](docs/core-infrastructure/)

The foundational Virtual WAN hub that all other projects connect to. Includes:
- Virtual WAN hub with Point-to-Site VPN
- Microsoft Entra ID authentication for remote access
- Private DNS Resolver for cross-network name resolution
- Private DNS Zones for private endpoint resolution
- Network routing for spoke connectivity

**[📖 Full Documentation →](docs/core-infrastructure/README.md)**

**Quick Deploy**:
```bash
./scripts/deploy-core.sh
```

---

### 🔧 Infrastructure Projects

Infrastructure projects deploy foundational capabilities that other projects consume. Each deploys to its own dedicated resource group.

- **[Private Azure Key Vault](docs/keyvault/README.md)**  
  Deploy a private Key Vault with RBAC authorization, private endpoint, and DNS integration for secure centralized secrets management. Supports Bicep Key Vault references for consuming secrets in other deployments.

- **[Private Storage Account](docs/storage-infra/README.md)**  
  Deploy a private Azure Storage Account with RBAC-only authentication (shared keys disabled), private endpoint, and DNS integration. Enforces TLS 1.2 minimum and provides comprehensive validation scripts.

- **[Private Azure Container Registry](docs/registry/README.md)**  
  Deploy a private ACR with private endpoint integration for secure container image storage and management. Follows core infrastructure patterns with parameterized Bicep, RBAC, and VPN access via the hub network.

- **[Azure API Management Standard v2](docs/apim/README.md)**  
  Deploy Azure API Management Standard v2 as a centralized API gateway with public frontend and VNet-integrated backend for exposing internal APIs externally. Includes developer portal and VNet integration.

- **[Private Azure Kubernetes Service](docs/aks/README.md)**  
  Deploy a private AKS cluster with 3 nodes across availability zones, Azure Linux (CBL-Mariner) OS, Azure CNI Overlay networking, and ACR integration via managed identity. Accessible only via VPN.

- **[Private Azure Container Apps](docs/aca/README.md)**  
  Deploy a VNet-injected Container Apps environment with private endpoint, internal-only ingress, and Log Analytics integration for secure serverless container hosting. Consumption workload profile, accessible only via VPN.

- **[Private Foundry](docs/foundry/README.md)**  
  Deploy Private Foundry network-secured infrastructure with delegated agent subnet, private endpoint subnet, centralized private DNS integration, and strict capability-host/account purge cleanup flow.

---

### 🧩 Solution Projects

Solution projects consume deployed infrastructure to accomplish specific use cases. Each deploys to its own dedicated resource group.

- **[Private Storage Account with Customer Managed Key](docs/storage-cmk/README.md)**  
  Enable customer-managed encryption key (CMK) on an existing private Storage Account using a key stored in the private Key Vault. Includes managed identity, RBAC setup, and key rotation policy.

- **[Storage API via APIM with OAuth](docs/storage-api/README.md)**  
  OAuth-protected REST API for Azure Blob Storage operations through API Management. Uses APIM managed identity to authenticate to storage, with JWT validation for client access. Supports upload, list, download, and delete operations.

- **[MCP Server on ACA](docs/mcp-server/README.md)**  
  Demo MCP (Model Context Protocol) server deployed as a container app in the private ACA environment. Exposes tools over streamable HTTP (SSE) transport, built via `az acr build` into private ACR, with Python-based functional validation. Phase 1 of MCP → ACA → APIM → Copilot Studio pipeline.

---

## 🚀 Getting Started

### Prerequisites

- **Azure CLI** 2.50.0+ ([Install](https://aka.ms/azure-cli))
- **Azure Subscription** with Contributor access
- **jq** for JSON parsing (used in scripts)

### 1️⃣ Deploy Core Infrastructure (Required)

The core infrastructure must be deployed first as it provides networking and security for all projects.

```bash
# Clone repository
git clone https://github.com/acworkma/AI-Lab.git
cd AI-Lab

# Login to Azure
az login

# Create your parameters file from the template
cp bicep/main.parameters.example.json bicep/main.parameters.json

# Edit parameters (set your Entra tenant ID)
nano bicep/main.parameters.json

# Deploy (takes ~25-30 minutes)
./scripts/deploy-core.sh
```

📖 **Detailed Instructions**: [docs/core-infrastructure/README.md](docs/core-infrastructure/README.md)

### 2️⃣ Configure VPN Access (Optional)

Set up VPN client access to connect to your Azure resources:

📖 **VPN Setup Guide**: [docs/core-infrastructure/vpn-client-setup.md](docs/core-infrastructure/vpn-client-setup.md)

### 3️⃣ Deploy Spoke Projects

Once the core is deployed, you can add any spoke projects independently. Each project has its own deployment instructions in its documentation folder.

## 🏛️ Governance & Principles

All infrastructure follows the **7 Constitutional Principles** defined in [CONTRIBUTING.md](CONTRIBUTING.md):

1. **Infrastructure as Code First** - No manual changes, 100% Bicep
2. **Modular & Reusable** - DRY principle, reusable modules
3. **Resource Organization** - Consistent naming, tagging, grouping
4. **Security by Default** - No secrets in code, RBAC over keys
5. **Cost Conscious** - Right-sizing, auto-shutdown, monitoring
6. **Documentation Required** - Every resource documented
7. **Validation & Testing** - Pre-deployment validation mandatory

## 📁 Repository Structure

```
AI-Lab/
├── bicep/                          # Infrastructure as Code
│   ├── modules/                    # Reusable Bicep modules
│   │   ├── vwan-hub.bicep
│   │   ├── vpn-gateway.bicep
│   │   ├── vpn-server-configuration.bicep
│   │   └── key-vault.bicep
│   ├── main.bicep                  # Core infrastructure template
│   └── main.parameters.example.json # Parameter template
│
├── scripts/                        # Deployment automation
│   ├── deploy-core.sh              # Deploy core infrastructure
│   ├── validate-core.sh            # Validate deployment
│   └── cleanup-core.sh             # Delete resources
│
├── docs/                           # Documentation by project
│   └── core-infrastructure/        # Core hub documentation
│       ├── README.md               # Main guide
│       ├── vpn-client-setup.md     # VPN setup guide
│       ├── architecture-diagram.md # Architecture details
│       └── troubleshooting.md      # Common issues
│
├── specs/                          # Project specifications
│   └── 001-vwan-core/              # Core infrastructure spec
│
├── README.md                       # This file
└── CONTRIBUTING.md                 # Development guidelines
```

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Development workflow
- Constitutional principles
- Branch naming conventions
- Pull request guidelines

## 📄 License

This project is licensed under the terms specified in the repository.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/acworkma/AI-Lab/issues)
- **Documentation**: Check project-specific docs in [`docs/`](docs/)
- **Troubleshooting**: See individual project troubleshooting guides

---
