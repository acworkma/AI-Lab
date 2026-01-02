# Contributing to AI-Lab

## Welcome

Thank you for contributing to the AI-Lab infrastructure project! This guide will help you add new spoke labs following our architecture patterns and constitutional principles.

## Prerequisites

Before contributing, ensure you have:
- ✅ Deployed core infrastructure (see [docs/core-infrastructure/README.md](docs/core-infrastructure/README.md))
- ✅ Read the [constitution](.specify/memory/constitution.md)
- ✅ Azure CLI installed and authenticated
- ✅ Basic knowledge of Bicep and Azure Virtual WAN

## Adding a New Spoke Lab

### Step 1: Plan Your Lab

1. **Choose a unique service identifier**: `rg-ai-{service}`
   - Examples: `rg-ai-storage`, `rg-ai-ml`, `rg-ai-databricks`
   - Follow kebab-case naming

2. **Allocate non-overlapping address space**:
   - Hub: `10.0.0.0/16` (reserved)
   - Available spoke ranges: `10.1.0.0/16` through `10.255.0.0/16`
   - Choose next available `/16` block

3. **Define lab purpose and scope**:
   - What Azure services will be deployed?
   - What dependencies on core infrastructure (Key Vault, etc.)?
   - Estimated cost and resource quotas

### Step 2: Create Project Structure

```bash
# From repository root
mkdir -p specs/{NNN}-{lab-name}
cd specs/{NNN}-{lab-name}

# Create specification files
touch spec.md plan.md research.md data-model.md tasks.md
mkdir -p checklists contracts
```

**Example**: For a storage lab:
```
specs/002-storage-lab/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── tasks.md
├── checklists/
│   └── requirements.md
└── contracts/
    └── deployment-contract.md
```

### Step 3: Write Specification

Follow the spec template at `.github/templates/spec-template.md`.

**Key sections for spoke labs**:
1. **User Scenarios**: What problems does this lab solve?
2. **Requirements**: 
   - Must connect to Virtual Hub
   - Must use Key Vault for secrets
   - Must follow naming convention
3. **Dependencies**: Reference to core infrastructure

**Example User Story**:
```markdown
### User Story 1 - Deploy Storage Lab (Priority: P1)

As a data engineer, I need a storage lab connected to the vWAN hub so that
I can experiment with Azure Storage services while maintaining secure network
connectivity to other labs.

**Acceptance Scenarios**:
1. Given core infrastructure is deployed, When I deploy storage lab, Then 
   VNet is connected to hub
2. Given lab is deployed, When I check routing, Then I can access resources
   in other spoke labs via hub
```

### Step 4: Create Bicep Infrastructure

**Spoke Lab Bicep Structure**:
```
bicep/{lab-name}/
├── modules/
│   ├── vnet.bicep           # Spoke VNet
│   ├── nsg.bicep            # Network Security Group
│   ├── storage.bicep        # Lab-specific resources
│   └── hub-connection.bicep # Connection to vWAN hub
├── main.bicep               # Orchestration
└── main.parameters.json     # Default parameters
```

**Required Parameters** (all spoke labs):
```bicep
@description('Spoke VNet address space (must not overlap with hub 10.0.0.0/16)')
param vnetAddressPrefix string = '10.X.0.0/16'  // Choose unique X

@description('Virtual Hub resource ID from core infrastructure')
param virtualHubId string

@description('Key Vault name for secrets (from core infrastructure)')
param keyVaultName string
```

**VNet Connection Pattern**:
```bicep
module hubConnection 'modules/hub-connection.bicep' = {
  name: 'deploy-hub-connection'
  scope: resourceGroup(coreResourceGroup)
  params: {
    vhubName: vhubName
    spokeVnetId: vnet.outputs.id
    connectionName: 'connection-to-${labName}'
  }
}
```

### Step 5: Follow Constitutional Principles

Validate your lab against all 7 principles:

#### Principle 1: Infrastructure as Code (IaC)
- ✅ All resources defined in Bicep
- ✅ No manual portal changes
- ✅ Version controlled in Git
- ✅ Parameters for environment-specific values

#### Principle 2: Hub-Spoke Network Architecture
- ✅ VNet connected to Virtual Hub
- ✅ Address space non-overlapping with hub and other spokes
- ✅ Traffic routes through hub

#### Principle 3: Resource Organization
- ✅ Resource group follows `rg-ai-{service}` pattern
- ✅ Required tags: environment, purpose, owner
- ✅ Logical separation from other labs

#### Principle 4: Security and Secrets Management
- ✅ NO SECRETS IN SOURCE CONTROL
- ✅ Use Key Vault references from core infrastructure
- ✅ Local parameter files (.local.parameters.json) gitignored

#### Principle 5: Deployment Standards
- ✅ Azure CLI deployment with what-if validation
- ✅ Deployment script with error handling
- ✅ Rollback documentation

#### Principle 6: Lab Modularity and Independence
- ✅ Can deploy without dependencies on other spoke labs
- ✅ Can delete cleanly without affecting core or other spokes
- ✅ Minimal dependencies (only on core infrastructure)

#### Principle 7: Documentation Standards
- ✅ README.md with all required sections (see constitution)
- ✅ Inline comments in Bicep
- ✅ Parameter documentation

### Step 6: Create Deployment Script

```bash
#!/usr/bin/env bash
# scripts/deploy-{lab-name}.sh

set -euo pipefail

RESOURCE_GROUP="rg-ai-{lab-name}"
TEMPLATE_FILE="bicep/{lab-name}/main.bicep"
PARAMETER_FILE="bicep/{lab-name}/main.parameters.json"

# Get Virtual Hub ID from core infrastructure
VHUB_ID=$(az network vhub show \
    --resource-group rg-ai-core \
    --name hub-ai-eastus2 \
    --query id -o tsv)

# Deploy
az deployment sub create \
    --name "deploy-{lab-name}-$(date +%Y%m%d-%H%M%S)" \
    --location eastus2 \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETER_FILE" \
    --parameters virtualHubId="$VHUB_ID"
```

### Step 7: Test Spoke-to-Spoke Connectivity

After deployment, verify connectivity:

```bash
# From a VM in spoke 1 (e.g., 10.1.0.4)
ping 10.2.0.4  # VM in spoke 2

# Check effective routes include hub-learned routes
az network nic show-effective-route-table \
    --resource-group rg-ai-{lab-name} \
    --name {vm-nic-name} \
    --query "value[?source=='VirtualNetworkGateway']"
```

### Step 8: Documentation

Create `docs/{lab-name}/README.md` with:

1. **Overview**: Purpose and architecture
2. **Prerequisites**: 
   - Core infrastructure deployed
   - Required Azure quotas
3. **Architecture**: Diagram showing connection to hub
4. **Deployment**: Step-by-step instructions
5. **Configuration**: Post-deployment steps
6. **Testing**: Validation of connectivity and lab functionality
7. **Cleanup**: Safe deletion instructions
8. **Troubleshooting**: Common issues

### Step 9: Submit Pull Request

1. **Create feature branch**:
   ```bash
   git checkout -b feature/{lab-name}
   ```

2. **Commit changes**:
   ```bash
   git add .
   git commit -m "Add {lab-name} spoke lab"
   ```

3. **Run validation**:
   ```bash
   # Scan for secrets
   ./scripts/scan-secrets.sh
   
   # Validate Bicep
   az bicep build --file bicep/{lab-name}/main.bicep
   ```

4. **Push and create PR**:
   ```bash
   git push origin feature/{lab-name}
   # Create pull request on GitHub
   ```

5. **PR Description should include**:
   - Purpose of the lab
   - Address space allocation (e.g., 10.X.0.0/16)
   - Screenshot of architecture diagram
   - Checklist confirming constitutional compliance

## Spoke Lab Examples

### Example 1: Storage Lab (Simple)

**Address Space**: `10.1.0.0/16`

**Resources**:
- Spoke VNet with 3 subnets (data, compute, management)
- Storage Account (from Key Vault connection string)
- Blob containers for lab data
- Private endpoint for storage account

**Connection to Core**:
- VNet peered to Virtual Hub
- Uses Key Vault (kv-ai-core-*) for storage connection string
- Routes to other spokes via hub

### Example 2: Machine Learning Lab (Complex)

**Address Space**: `10.2.0.0/16`

**Resources**:
- Spoke VNet with 4 subnets (compute, data, ml, management)
- Azure Machine Learning workspace
- Compute cluster (VMs in spoke VNet)
- Azure Data Factory (orchestration)
- Private endpoints for all PaaS services

**Connection to Core**:
- VNet peered to Virtual Hub
- Uses Key Vault for ML workspace secrets, data store credentials
- Can access storage lab (10.1.0.0/16) for training data
- Isolated compute within spoke VNet

## Address Space Registry

**Current Allocations**:

| Spoke Lab | Resource Group | Address Space | Status |
|-----------|---------------|---------------|--------|
| Core Hub | rg-ai-core | 10.0.0.0/16 | ✅ Deployed |
| (Available) | - | 10.1.0.0/16 - 10.255.0.0/16 | 🟢 Free |

**When adding a new lab**: Update this table in your PR.

## Troubleshooting Spoke Labs

### Issue: VNet connection fails

**Symptom**: `Virtual hub is not in a valid state`

**Solution**: 
```bash
# Verify hub routing state is "Provisioned"
az network vhub show \
    --resource-group rg-ai-core \
    --name hub-ai-eastus2 \
    --query routingState
```

### Issue: Cannot reach other spoke

**Symptom**: Ping fails from spoke 1 to spoke 2

**Solution**:
1. Verify `allowBranchToBranchTraffic` enabled on Virtual WAN
2. Check NSG rules allow traffic
3. Verify routing table shows hub-learned routes

### Issue: Key Vault access denied from spoke

**Symptom**: `Access denied` when spoke deployment tries to read secret

**Solution**:
```bash
# Grant deployment identity access to Key Vault
az role assignment create \
    --role "Key Vault Secrets User" \
    --assignee <deployment-identity> \
    --scope /subscriptions/.../resourceGroups/rg-ai-core/providers/Microsoft.KeyVault/vaults/kv-ai-core-*
```

## Getting Help

- **Questions**: Open a GitHub Discussion
- **Bugs**: Open a GitHub Issue with spoke lab tag
- **Documentation**: Update this CONTRIBUTING.md with lessons learned

---

**Happy Contributing!** 🚀

For questions, contact the AI-Lab maintainers.
