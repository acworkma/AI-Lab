# AI-Lab Azure Infrastructure Constitution

## Purpose
This constitution defines the governing principles for building and managing Azure infrastructure in the AI-Lab repository. All infrastructure is designed as modular, independently deployable labs centered around a shared vWAN hub.

## Project Types

AI-Lab distinguishes between two types of projects:

### Infrastructure Projects
Deploy foundational capabilities that other projects consume. Examples include container registries, networking extensions, and shared services.

- **Purpose**: Provide reusable infrastructure capabilities
- **Resource Group**: Dedicated `rg-ai-[service]` (e.g., `rg-ai-registry`)
- **Consumers**: Other Infrastructure Projects and Solution Projects
- **Examples**: Private ACR, future shared databases, messaging services

### Solution Projects
Consume deployed infrastructure to accomplish a specific use case. Examples include secure storage configurations, ML workloads, and application deployments.

- **Purpose**: Implement specific business or technical solutions
- **Resource Group**: Dedicated `rg-ai-[service]` (e.g., `rg-ai-storage`)
- **Dependencies**: Core infrastructure + relevant Infrastructure Projects
- **Examples**: Storage with CMK, future ML labs, application hosting

---

## Core Principles

### 1. Infrastructure as Code (IaC)
- **Bicep Only**: All Azure resources MUST be defined in Bicep templates
- **No Manual Changes**: Portal modifications without corresponding Bicep updates are prohibited
- **Version Control**: All infrastructure code is tracked in Git with meaningful commit messages
- **Parameterization**: Bicep modules must be reusable with parameters for environment-specific values
- **Modularity**: Create reusable modules for common patterns (networking, storage, compute)

### 2. Hub-Spoke Network Architecture
- **Core Lab (Hub)**: Resource group `rg-ai-core` contains vWAN hub, VPN Gateway, and shared Key Vault
- **Satellite Labs (Spokes)**: Each service deployed in `rg-ai-[service]` resource group
- **Mandatory Connectivity**: All spoke labs MUST connect to the vWAN hub
- **Network Isolation**: Labs are isolated by default unless explicitly peered
- **Core First**: vWAN hub infrastructure must be deployed before any spoke labs

### 3. Resource Organization
- **Naming Convention**: 
  - Resource Groups: `rg-ai-[service]` (e.g., `rg-ai-storage`, `rg-ai-ml`)
  - Core infrastructure: `rg-ai-core`
- **Tagging Requirements**: All resources must include:
  - `environment`: (dev, test, prod)
  - `purpose`: Brief description of the lab/service
  - `owner`: Responsible team or individual
- **Separation of Concerns**: One resource group per logical service/lab

### 4. Security and Secrets Management
- **NO SECRETS IN SOURCE CONTROL**: API keys, connection strings, passwords, certificates, and any sensitive data are STRICTLY PROHIBITED from being committed to GitHub
- **Centralized Key Vault**: All secrets MUST be stored in Azure Key Vault located in `rg-ai-core`
- **Secure Parameter Passing**: Use Key Vault references in Bicep deployments for sensitive parameters
- **Access Control**: Implement least-privilege access using Azure RBAC
- **Network Security**: Apply Network Security Groups (NSGs) and consider private endpoints where appropriate
- **.gitignore**: Ensure local parameter files with secrets are excluded from version control

### 5. Deployment Standards
- **Azure Deploy**: All deployments use Azure CLI (`az deployment`)
- **What-If Analysis**: Run `--what-if` before applying changes to production resources
- **Validation**: Deployment validation gates must pass before applying
- **Rollback Procedures**: Document rollback steps for each deployment
- **Deployment Logs**: Maintain deployment history and troubleshooting notes

### 6. Lab Modularity and Independence
- **Independent Deployment**: Each lab can be deployed without dependencies on other labs (except vWAN hub and Key Vault in core)
- **Clean Deletion**: Labs can be deleted without impacting other services
- **Minimal Dependencies**: Reduce cross-lab dependencies; shared resources live in `rg-ai-core`
- **Self-Contained**: Each lab includes its own README with deployment instructions
- **Project Type Awareness**: Infrastructure Projects provide capabilities consumed by Solution Projects; document these relationships in each project's README

### 7. Documentation Standards
- **README Template**: Each lab MUST include a README.md with the following sections:
  - **Overview**: Purpose and description of the lab/service
  - **Prerequisites**: Required resources (including core infrastructure), tools, and permissions
  - **Architecture**: Diagram or description of resources and connectivity to vWAN hub
  - **Deployment**: Step-by-step instructions to deploy the Bicep templates
  - **Configuration**: Post-deployment configuration steps and Key Vault secret setup
  - **Testing**: Validation steps to verify the deployment and connectivity
  - **Cleanup**: Instructions to safely delete the lab resources
  - **Troubleshooting**: Common issues and solutions
- **Bicep Comments**: Include inline comments explaining complex logic or design decisions
- **Parameter Files**: Document all parameters with descriptions and example values
- **EntraID**: Always refer to EntraID not Azure AD

## Governance

### Constitution Changes
- Constitution updates require explicit documentation
- Changes must be committed to version control
- Breaking changes require review of dependent labs

### New Lab Additions
- **Declare Project Type**: Specify whether new lab is an Infrastructure Project or Solution Project
- Verify compatibility with vWAN hub configuration
- Follow naming and tagging conventions
- Include connectivity validation tests
- Document deployment and cleanup procedures
- Document dependencies on core and other Infrastructure Projects

### Continuous Improvement
- Regular review of optimization opportunities
- Update Bicep modules with Azure best practices
- Maintain up-to-date documentation
- Share learnings across labs

## Enforcement
Violations of these principles, especially security requirements around secrets management, must be immediately remediated. All contributors are responsible for upholding these standards.

**Version**: 1.0.0 | **Ratified**: 2025-12-31 | **Last Amended**: 2025-12-31
