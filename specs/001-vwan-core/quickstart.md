# Quickstart: Deploy Core Azure vWAN Infrastructure

**Feature**: Core Azure vWAN Infrastructure  
**Deployment Time**: ~25-30 minutes  
**Region**: East US 2  
**Prerequisites**: Azure CLI, Azure subscription, Contributor permissions

---

## Prerequisites

### Required Tools

1. **Azure CLI** (version 2.50.0 or later)
   ```bash
   az --version
   # If not installed: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
   ```

2. **Git** (for cloning repository)
   ```bash
   git --version
   ```

3. **Text Editor** (for parameter files)
   - VS Code, vim, nano, or any editor

### Required Permissions

- Azure subscription with **Contributor** role (or custom role with deployment permissions)
- **Key Vault Administrator** role (for initial Key Vault setup)

### Azure Subscription

```bash
# Login to Azure
az login

# Set subscription (if you have multiple)
az account set --subscription "Your Subscription Name or ID"

# Verify subscription
az account show --output table
```

---

## Step 1: Clone Repository

```bash
# Clone the AI-Lab repository
git clone https://github.com/acworkma/AI-Lab.git
cd AI-Lab

# Checkout the feature branch
git checkout 001-vwan-core
```

---

## Step 2: Review Project Structure

```bash
tree bicep/ docs/ scripts/
```

Expected structure:
```
bicep/
├── modules/
│   ├── resource-group.bicep
│   ├── vwan-hub.bicep
│   ├── vpn-gateway.bicep
│   └── key-vault.bicep
├── main.bicep
└── main.parameters.json

scripts/
├── deploy-core.sh
├── validate-core.sh
└── cleanup-core.sh

docs/
└── core-infrastructure/
    ├── README.md
    ├── architecture-diagram.png
    └── troubleshooting.md
```

---

## Step 3: Configure Parameters

### 3.1 Review Default Parameters

```bash
cat bicep/main.parameters.json
```

Default parameters deploy:
- Resource Group: `rg-ai-core`
- Region: `eastus2`
- Environment: `dev`
- vWAN: Standard tier with 10.0.0.0/16 hub address space
- VPN Gateway: 1 scale unit (500 Mbps)
- Key Vault: Standard SKU

### 3.2 Create Local Parameter Overrides (Optional)

Generate a unique Key Vault name (must be globally unique):
```bash
# Generate random suffix
RANDOM_SUFFIX=$(openssl rand -hex 2)
KV_NAME="kv-ai-core-${RANDOM_SUFFIX}"
echo "Key Vault Name: $KV_NAME"
```

Create local parameter file:
```bash
cat > bicep/main.local.parameters.json <<EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus2"
    },
    "environment": {
      "value": "dev"
    },
    "owner": {
      "value": "$(az account show --query user.name -o tsv)"
    },
    "keyVaultName": {
      "value": "$KV_NAME"
    }
  }
}
EOF
```

**Note**: `*.local.parameters.json` files are gitignored and safe for local customization.

---

## Step 4: Validate Deployment (What-If)

Run what-if analysis to preview changes:

```bash
chmod +x scripts/deploy-core.sh
scripts/deploy-core.sh --what-if
```

Expected output:
- Resource Group: Create
- Virtual WAN: Create
- Virtual Hub: Create
- VPN Gateway: Create
- Key Vault: Create

Review the output carefully:
- ✅ Green "+ Create" - new resources
- ⚠️ Yellow "~ Modify" - existing resource changes (should not see on first run)
- ❌ Red "- Delete" - resources being deleted (should not see)

---

## Step 5: Deploy Infrastructure

### 5.1 Run Deployment Script

```bash
scripts/deploy-core.sh
```

The script will:
1. Validate parameters against schema
2. Run what-if analysis
3. Prompt for confirmation
4. Deploy resources
5. Show deployment progress
6. Output resource IDs

### 5.2 Monitor Deployment

In another terminal, monitor deployment status:
```bash
# Watch deployment operations
az deployment sub show \
  --name deploy-core-infrastructure \
  --query properties.provisioningState

# Watch resource group creation
az group show \
  --name rg-ai-core \
  --query properties.provisioningState
```

### 5.3 Deployment Timeline

Approximate timing:
- **0-1 min**: Resource group creation
- **1-3 min**: Virtual WAN and Key Vault creation
- **3-8 min**: Virtual Hub creation
- **8-28 min**: VPN Gateway creation (longest step)
- **28-30 min**: Finalization and validation

**Total**: ~25-30 minutes

---

## Step 6: Verify Deployment

### 6.1 Run Validation Script

```bash
chmod +x scripts/validate-core.sh
scripts/validate-core.sh
```

Validation checks:
- ✅ Resource group exists with correct tags
- ✅ Virtual WAN is in "Succeeded" state
- ✅ Virtual Hub routing state is "Provisioned"
- ✅ VPN Gateway is operational
- ✅ Key Vault is accessible
- ✅ No configuration drift (what-if shows no changes)

### 6.2 Manual Verification

```bash
# Check resource group
az group show --name rg-ai-core --output table

# Check Virtual WAN
az network vwan show \
  --resource-group rg-ai-core \
  --name vwan-ai-hub \
  --query '{Name:name, State:provisioningState, Type:type, Sku:sku}' \
  --output table

# Check Virtual Hub
az network vhub show \
  --resource-group rg-ai-core \
  --name hub-ai-eastus2 \
  --query '{Name:name, RoutingState:routingState, AddressPrefix:addressPrefix}' \
  --output table

# Check VPN Gateway
az network vpn-gateway show \
  --resource-group rg-ai-core \
  --name vpngw-ai-hub \
  --query '{Name:name, State:provisioningState, ScaleUnit:vpnGatewayScaleUnit}' \
  --output table

# Check Key Vault
az keyvault show \
  --name $KV_NAME \
  --query '{Name:name, Sku:properties.sku.name, RbacEnabled:properties.enableRbacAuthorization}' \
  --output table
```

### 6.3 Test Key Vault Access

```bash
# Store a test secret
az keyvault secret set \
  --vault-name $KV_NAME \
  --name test-secret \
  --value "test-value"

# Retrieve the secret
az keyvault secret show \
  --vault-name $KV_NAME \
  --name test-secret \
  --query value \
  --output tsv

# Delete the test secret
az keyvault secret delete \
  --vault-name $KV_NAME \
  --name test-secret
```

---

## Step 7: Save Deployment Outputs

Capture resource IDs for future spoke lab deployments:

```bash
# Get Virtual Hub ID (needed for spoke connections)
VHUB_ID=$(az network vhub show \
  --resource-group rg-ai-core \
  --name hub-ai-eastus2 \
  --query id \
  --output tsv)
echo "Virtual Hub ID: $VHUB_ID"

# Get Key Vault URI (needed for parameter files)
KV_URI=$(az keyvault show \
  --name $KV_NAME \
  --query properties.vaultUri \
  --output tsv)
echo "Key Vault URI: $KV_URI"

# Save to file for future reference
cat > deployment-outputs.txt <<EOF
Resource Group: rg-ai-core
Virtual Hub ID: $VHUB_ID
Key Vault Name: $KV_NAME
Key Vault URI: $KV_URI
Deployment Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo "Outputs saved to deployment-outputs.txt"
```

---

## Next Steps

### Connect Spoke Labs

With core infrastructure deployed, you can now:

1. **Create Spoke Labs**: Deploy service-specific resource groups (e.g., rg-ai-storage, rg-ai-ml)
2. **Connect to Hub**: Use Virtual Hub ID to create spoke connections
3. **Use Key Vault**: Reference Key Vault in spoke deployment parameter files

Example spoke connection:
```bash
az network vhub connection create \
  --name spoke-to-hub \
  --remote-vnet /subscriptions/{sub-id}/resourceGroups/rg-ai-storage/providers/Microsoft.Network/virtualNetworks/vnet-storage \
  --vhub-name hub-ai-eastus2 \
  --resource-group rg-ai-core
```

### Configure VPN Access

To enable remote VPN access:

1. **Create VPN Site**: Define on-premises or remote site
2. **Configure VPN Connection**: Connect site to VPN Gateway
3. **Download VPN Config**: Get configuration for VPN client

See: [docs/core-infrastructure/README.md](../../docs/core-infrastructure/README.md)

---

## Troubleshooting

### Common Issues

**1. Key Vault name already exists**
```
Error: The vault name 'kv-ai-core-1234' is already in use.
```
**Solution**: Key Vault names are globally unique. Generate a new name:
```bash
RANDOM_SUFFIX=$(openssl rand -hex 2)
# Update main.local.parameters.json with new name
```

**2. Insufficient permissions**
```
Error: The client does not have authorization to perform action.
```
**Solution**: Request Contributor role on subscription:
```bash
az role assignment create \
  --assignee $(az account show --query user.name -o tsv) \
  --role Contributor \
  --scope /subscriptions/$(az account show --query id -o tsv)
```

**3. VPN Gateway deployment timeout**
```
Error: Long running operation failed with status 'Failed'.
```
**Solution**: VPN Gateway deployment can take 20-30 minutes. Check status:
```bash
az network vpn-gateway show \
  --resource-group rg-ai-core \
  --name vpngw-ai-hub \
  --query provisioningState
```
If "Failed", delete and redeploy:
```bash
az network vpn-gateway delete \
  --resource-group rg-ai-core \
  --name vpngw-ai-hub
# Re-run deployment script
```

**4. Address space conflict**
```
Error: The address space 10.0.0.0/16 overlaps with existing VNet.
```
**Solution**: Change `vhubAddressPrefix` parameter to non-overlapping range:
```json
"vhubAddressPrefix": {
  "value": "10.10.0.0/16"
}
```

### More Troubleshooting

See: [docs/core-infrastructure/troubleshooting.md](../../docs/core-infrastructure/troubleshooting.md)

---

## Cleanup (Optional)

To delete all core infrastructure:

```bash
chmod +x scripts/cleanup-core.sh
scripts/cleanup-core.sh
```

**Warning**: This will:
1. Delete all resources in rg-ai-core
2. Soft-delete Key Vault (recoverable for 90 days)
3. Disconnect any spoke labs (if connected)

To fully purge Key Vault:
```bash
az keyvault purge --name $KV_NAME
```

---

## Success Criteria

✅ Deployment complete when:
- All resources show "Succeeded" provisioning state
- Virtual Hub routing state is "Provisioned"
- Key Vault is accessible (test secret created/retrieved)
- What-if analysis shows "no changes"
- Deployment completed in under 30 minutes
- All tags present (environment, purpose, owner)

✅ Ready for spoke labs when:
- Virtual Hub ID captured
- Key Vault URI captured
- No errors in validation script
- Documentation reviewed

---

## Support

For issues or questions:
- Review: [spec.md](spec.md) - Feature specification
- Review: [data-model.md](data-model.md) - Resource details
- Review: [contracts/deployment-contract.md](contracts/deployment-contract.md) - Deployment interface
- Check: [docs/core-infrastructure/troubleshooting.md](../../docs/core-infrastructure/troubleshooting.md)
