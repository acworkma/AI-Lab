# Phase 0: Research - Core Azure vWAN Infrastructure with Global Secure Access

**Date**: 2025-12-31  
**Feature**: Core Azure vWAN Infrastructure with Global Secure Access  
**Updated**: 2025-12-31 (Refactored for Global Secure Access)
**Purpose**: Research Azure Virtual WAN architecture, Microsoft Entra Global Secure Access integration, Bicep best practices, and site-to-site VPN deployment patterns for hub-spoke topology with SSE capabilities

## Research Topics

### 1. Azure Virtual WAN Hub Architecture with Global Secure Access

**Decision**: Deploy Standard Virtual WAN with site-to-site VPN Gateway in East US 2 for Microsoft Entra Global Secure Access integration

**Rationale**: 
- Standard tier supports site-to-site VPN Gateway required for Microsoft Entra Global Secure Access
- Global Secure Access provides Security Service Edge (SSE) capabilities:
  - **Private Access**: Secure access to private corporate resources
  - **Internet Access**: Secure web access with threat protection
  - **Microsoft 365 Access**: Optimized access to Microsoft services
- Site-to-site VPN is the required connection type for Global Secure Access to Azure vWAN
- Supports spoke virtual network connections (core requirement)
- Enables zero trust network access (ZTNA) policies from Microsoft Entra
- BGP support for dynamic routing with Global Secure Access

**Alternatives Considered**:
- **Point-to-Site VPN**: Designed for individual client connections, NOT compatible with Global Secure Access → Rejected
- **Basic Virtual WAN**: Doesn't support required VPN features for Global Secure Access → Rejected
- **Traditional Hub-Spoke with VNet Peering**: No Global Secure Access integration → Rejected
- **Azure Firewall + Route Tables**: Additional complexity, doesn't replace SSE capabilities → Can be added later

**Key Configuration**:
- Virtual WAN: Standard SKU
- Hub address space: 10.0.0.0/16 (65,536 addresses for hub services)
- VPN Gateway: **Site-to-site** configuration (not point-to-site)
- VPN Gateway scale units: 1 (500 Mbps aggregate, scalable to 20 units)
- BGP: **Enabled** for dynamic routing with Global Secure Access
- Routing: Default route table for spoke connections

**Global Secure Access Integration Requirements**:
1. Site-to-site VPN Gateway deployed in vWAN hub
2. BGP enabled on VPN Gateway for dynamic routing
3. Microsoft Entra Global Secure Access tenant configured
4. VPN site created in Global Secure Access pointing to vWAN hub
5. Conditional access policies configured in Microsoft Entra admin center
6. Traffic forwarding profiles defined for Private/Internet/M365 access

**Documentation References**:
- Microsoft Learn: "What is Global Secure Access"
- Microsoft Learn: "How to connect Global Secure Access to an Azure Virtual WAN"
- Microsoft Learn: "Configure Private Access with Azure Virtual WAN"

### 2. Azure Key Vault Best Practices

**Decision**: Deploy Key Vault with Azure RBAC permission model (not Access Policies)

**Rationale**:
- RBAC provides consistent permissions across all Azure resources
- Integrates with Azure AD for identity management
- Follows principle of least privilege more granularly
- Microsoft recommends RBAC for new deployments (Access Policies in maintenance mode)
- Easier to audit and manage at scale

**Alternatives Considered**:
- **Vault Access Policies**: Legacy model, still supported but not recommended for new deployments → Rejected
- **Dedicated Key Vault per lab**: Higher cost, management overhead → Rejected in favor of centralized model per constitution
- **Azure Managed HSM**: Significantly higher cost ($1.45/hour), overkill for lab environment → Reserved for production if needed

**Key Configuration**:
- Enable RBAC authorization model
- Enable soft-delete (90-day retention, cannot be disabled per Azure policy)
- Enable purge protection for production environments
- Network access: Allow all networks initially (can restrict to vWAN subnet later)
- Diagnostic settings: Send logs to Log Analytics workspace (future enhancement)

### 3. Bicep Module Design Patterns

**Decision**: Use modular Bicep files with single responsibility, composition in main.bicep

**Rationale**:
- Each module (resource group, vWAN, VPN Gateway, Key Vault) is independently testable
- Modules can be reused across future lab deployments
- Easier to maintain and troubleshoot than monolithic templates
- Follows IaC best practices: DRY (Don't Repeat Yourself), separation of concerns
- Bicep native modules are more idiomatic than ARM JSON imports

**Alternatives Considered**:
- **Single monolithic main.bicep**: Simpler for small deployments but harder to maintain and reuse → Rejected
- **Bicep Registry modules**: Public modules available but less customizable for our naming conventions → Considered for future, custom modules for now
- **ARM JSON templates**: Legacy format, less readable than Bicep → Constitution mandates Bicep only

**Module Structure**:
```bicep
// Pattern: Each module accepts parameters, returns outputs
module rg 'modules/resource-group.bicep' = {
  name: 'deploy-rg-ai-core'
  params: {
    name: 'rg-ai-core'
    location: 'eastus2'
    tags: tags
  }
}
```

### 4. Parameter Management and Secrets

**Decision**: Use separate parameter files with Key Vault references for secrets

**Rationale**:
- Keeps secrets out of source control (constitutional requirement)
- Parameter files in JSON format easier to validate and version
- Key Vault references resolved at deployment time by Azure
- Supports multiple environments (dev, test, prod) with different parameter files
- Local parameter files (*.local.parameters.json) gitignored for developer overrides

**Alternatives Considered**:
- **Inline parameters in deployment script**: Less maintainable, parameters scattered → Rejected
- **Environment variables**: Not portable across deployment tools, harder to document → Rejected
- **Hardcoded defaults in Bicep**: Security risk for sensitive values → Constitution prohibits

**Pattern**:
```json
{
  "parameters": {
    "vpnSharedKey": {
      "reference": {
        "keyVault": {
          "id": "/subscriptions/{sub-id}/resourceGroups/rg-ai-core/providers/Microsoft.KeyVault/vaults/{vault-name}"
        },
        "secretName": "vpn-shared-key"
      }
    }
  }
}
```

### 5. Deployment Automation with Azure CLI

**Decision**: Bash scripts with `az deployment sub create` for subscription-level deployment

**Rationale**:
- Subscription-level deployment allows creating resource group and resources in single operation
- What-if mode (`--what-if`) enables validation before apply (constitutional requirement)
- Bash scripts portable across Linux/macOS/Windows (Git Bash, WSL)
- Azure CLI widely available, well-documented, actively maintained
- Exit codes and error handling enable CI/CD integration

**Alternatives Considered**:
- **Azure PowerShell**: Windows-centric, less common in cloud-native environments → Rejected for Bash
- **Terraform**: Different state management model, not Bicep → Constitution mandates Bicep
- **Azure DevOps Pipelines**: Adds complexity for initial setup, better for CI/CD later → Manual scripts for MVP
- **GitHub Actions**: Future enhancement for automated deployments → Manual for initial deployment

**Deployment Flow**:
1. Validate parameters (check required values present)
2. Run `az deployment sub what-if` to preview changes
3. Prompt user for confirmation
4. Run `az deployment sub create` to apply
5. Validate deployment success
6. Output resource IDs and next steps

### 6. Region Selection: East US 2

**Decision**: Deploy all core infrastructure in East US 2 region

**Rationale**:
- User specified East US 2 as target region
- Supports all required services (vWAN, VPN Gateway, Key Vault)
- Paired region (Central US) for disaster recovery if needed
- Consistent region for all spoke labs simplifies networking

**Alternatives Considered**:
- **Multi-region deployment**: Higher cost, added complexity for lab environment → Future enhancement
- **Other US regions**: No specific advantage over East US 2 for lab purposes → User preference honored

### 7. Resource Naming Conventions

**Decision**: Follow Azure naming best practices within constitutional constraints

**Rationale**:
- Constitution specifies `rg-ai-core` for resource group
- Apply consistent pattern to child resources: `{resource-type}-ai-{descriptor}`
- Examples:
  - Resource Group: `rg-ai-core`
  - Virtual WAN: `vwan-ai-hub`
  - VPN Gateway: `vpngw-ai-hub`
  - Key Vault: `kv-ai-core-{random}` (globally unique required)
- Lowercase with hyphens for readability and Azure compatibility
- Avoid abbreviations that are unclear (e.g., use `vpngw` not `gw` for VPN Gateway)

**Key Vault Naming**:
- Must be globally unique across all Azure
- 3-24 characters, alphanumeric and hyphens
- Use `kv-ai-core-{4-char-random}` pattern (e.g., `kv-ai-core-a1b2`)
- Random suffix generated during deployment or provided as parameter

### 8. Tagging Strategy

**Decision**: Implement mandatory tags per constitution, add optional operational tags

**Rationale**:
- **environment**: `dev` (changeable to `test`, `prod` via parameters)
- **purpose**: `Core hub infrastructure for AI labs`
- **owner**: Deployment principal or specified owner parameter
- **deployedBy**: Track deployment automation vs manual
- **deployedDate**: ISO 8601 timestamp for auditing
- Tags applied at resource group level, inherited by child resources
- Enables cost tracking, lifecycle management, and governance

## Summary of Technical Decisions

| Decision Area | Choice | Justification |
|--------------|--------|---------------|
| Virtual WAN Tier | Standard | Required for spoke connections and future expansion |
| Key Vault Permissions | RBAC | Modern, consistent with Azure AD, recommended by Microsoft |
| Bicep Structure | Modular | Reusability, maintainability, testability |
| Parameter Management | JSON files + Key Vault refs | Secrets stay out of source control, version-controlled config |
| Deployment Tool | Azure CLI (Bash) | Portable, what-if support, CI/CD ready |
| Region | East US 2 | User specified, supports all services |
| Naming | `{type}-ai-{descriptor}` | Constitutional compliance, readability, uniqueness |
| Tagging | Mandatory + operational | Governance, cost tracking, lifecycle management |

## Next Steps

Proceed to Phase 1 to create:
- **data-model.md**: Resource relationships and dependencies
- **contracts/**: Parameter schemas and deployment contracts
- **quickstart.md**: Step-by-step deployment guide
