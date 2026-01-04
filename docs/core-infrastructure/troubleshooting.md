# Troubleshooting Guide: Core Azure vWAN Infrastructure

## Common Issues and Solutions

### Deployment Issues

#### 1. Key Vault Name Already Exists

**Symptom**:
```
ERROR: The vault name 'kv-ai-core-lab1' is already in use.
```

**Cause**: Key Vault names must be globally unique across all of Azure. Either:
- Someone else is using this name
- You previously deleted a vault with this name (soft-deleted vaults reserve the name for 90 days)

**Solution A - Use Different Name**:
```bash
# Edit parameter file with unique name
nano bicep/main.parameters.json

# Change keyVaultName value:
{
  "keyVaultName": {
    "value": "kv-ai-core-UNIQUE"  // Replace UNIQUE with random chars
  }
}
```

**Solution B - Purge Soft-Deleted Vault**:
```bash
# Check if vault is soft-deleted
az keyvault list-deleted --query "[?name=='kv-ai-core-lab1']"

# Purge permanently (WARNING: cannot be undone)
az keyvault purge --name kv-ai-core-lab1

# Redeploy
./scripts/deploy-core.sh
```

---

#### 2. Deployment Timeout or Stuck

**Symptom**:
- Deployment running for >40 minutes
- VPN Gateway provisioning state stuck at "Updating"

**Cause**: VPN Gateway can take 15-25 minutes to deploy. Azure resource contention may cause delays.

**Diagnosis**:
```bash
# Check deployment status
az deployment sub show \
  --name deploy-ai-core-TIMESTAMP \
  --query 'properties.provisioningState'

# Check VPN Gateway state
az network vpn-gateway show \
  --resource-group rg-ai-core \
  --name vpngw-ai-hub \
  --query provisioningState -o tsv
```

**Solution**:
```bash
# If truly stuck (>45 minutes), cancel and retry
az deployment sub cancel --name deploy-ai-core-TIMESTAMP

# Clean up partial deployment
az group delete --name rg-ai-core --yes

# Retry deployment
./scripts/deploy-core.sh
```

---

#### 3. Insufficient Permissions

**Symptom**:
```
ERROR: The client 'user@domain.com' does not have authorization to perform action 
'Microsoft.Network/virtualWans/write' over scope '/subscriptions/.../resourceGroups/rg-ai-core'
```

**Cause**: User lacks required Azure RBAC roles

**Diagnosis**:
```bash
# Check current role assignments
az role assignment list \
  --assignee $(az account show --query user.name -o tsv) \
  --all -o table
```

**Solution**:
```bash
# Request Contributor role from subscription administrator
# Or use Owner/Contributor account for deployment

# Verify permissions before deployment
az account show --query user
az role assignment list --assignee <user-principal-id>
```

---

#### 4. What-If Shows Unexpected Deletions

**Symptom**:
```
Resource will be deleted:
  - /subscriptions/.../resourceGroups/rg-ai-core/providers/Microsoft.KeyVault/vaults/kv-ai-core-lab1
```

**Cause**: Parameter mismatch between current deployment and new parameters

**Diagnosis**:
```bash
# Compare current parameters vs new
az deployment sub show --name deploy-ai-core-PREVIOUS --query properties.parameters
cat bicep/main.parameters.json
```

**Solution**:
```bash
# Review parameter differences carefully
# If deletion is unintended, restore previous parameter values
# If manual portal changes were made, update Bicep to match (or revert manual changes)
```

---

### Post-Deployment Issues

#### 5. Key Vault Access Denied

**Symptom**:
```
ERROR: The user, group or application 'appid=...' does not have secrets get permission
```

**Cause**: RBAC role not assigned to user/service principal

**Solution**:
```bash
# Get Key Vault resource ID
VAULT_ID=$(az keyvault show --name kv-ai-core-lab1 --query id -o tsv)

# Get current user ID
USER_ID=$(az ad signed-in-user show --query id -o tsv)

# Assign Key Vault Secrets Officer role
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee $USER_ID \
  --scope $VAULT_ID

# Test access
az keyvault secret set --vault-name kv-ai-core-lab1 --name test --value "success"
```

**Alternative Roles**:
- `Key Vault Secrets User` - Read-only access
- `Key Vault Administrator` - Full admin access (use cautiously)

---

#### 6. Virtual Hub Routing State Not "Provisioned"

**Symptom**:
```
routingState: None
```

**Cause**: Hub still provisioning or VPN Gateway not fully attached

**Diagnosis**:
```bash
# Check hub state
az network vhub show \
  --resource-group rg-ai-core \
  --name hub-ai-eastus2 \
  --query '{state:provisioningState,routing:routingState}'
```

**Solution**:
```bash
# Wait 5-10 more minutes after VPN Gateway succeeds
# Hub routing provisions after VPN Gateway completes

# Force refresh (if stuck >1 hour)
az network vhub update \
  --resource-group rg-ai-core \
  --name hub-ai-eastus2 \
  --set tags.forceRefresh="$(date +%s)"
```

---

#### 7. Spoke Connection Fails

**Symptom**:
```
ERROR: Virtual hub is not in a valid state for virtual network connection
```

**Cause**: Hub routing state not "Provisioned" yet

**Solution**:
```bash
# Verify hub routing state
az network vhub show \
  --resource-group rg-ai-core \
  --name hub-ai-eastus2 \
  --query routingState -o tsv

# Should output: Provisioned
# If not, wait for hub to finish provisioning
# Then retry spoke connection
```

---

### VPN Tunnel Issues

#### 8. VPN Tunnel Not Establishing

**Symptom**: VPN connection shows as "Disconnected" or unable to establish tunnel

**Cause**: BGP settings mismatch or firewall blocking IPSec/IKE

**Diagnosis**:
```bash
# Verify BGP settings
az network vpn-gateway show \
  --resource-group rg-ai-core \
  --name vpngw-ai-hub \
  --query 'bgpSettings.{ASN:asn,PeeringAddress:bgpPeeringAddresses[0].defaultBgpIpAddresses[0]}'
```

**Solution**:
1. **Verify BGP ASN matches** on both Azure and VPN endpoints
2. **Check firewall rules** allow:
   - UDP 500 (IKE)
   - UDP 4500 (IPSec NAT-T)
   - ESP protocol (IP protocol 50)
3. **Verify shared key** matches on both sides
4. **Review connection logs** in Azure portal

---

#### 9. BGP Routes Not Propagating

**Symptom**: Effective routes don't show BGP-learned routes from VPN endpoint

**Diagnosis**:
```bash
# Check effective routes on hub
az network vhub get-effective-routes \
  --resource-group rg-ai-core \
  --name hub-ai-eastus2 \
  --query "value[?nextHopType=='VPN Gateway']"
```

**Solution**:
```bash
# Verify BGP is enabled on both sides
# Check BGP session status in Azure portal:
# rg-ai-core > vpngw-ai-hub > Connections > <connection> > BGP Status

# If BGP peer down, check:
# 1. BGP peering addresses match
# 2. No firewall blocking BGP (TCP 179)
# 3. VPN tunnel is up (prerequisite for BGP)
```
---

### Validation Script Issues

**Symptom**:
```
./scripts/validate-core.sh: line 123: jq: command not found
```

**Solution**:
```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y jq

# macOS
brew install jq

# Windows (Git Bash)
# Download from: https://stedolan.github.io/jq/download/
```

---

#### 11. Validation Shows Configuration Drift

**Symptom**:
```
[⚠ WARN] Configuration drift detected - manual changes may have been made
```

**Cause**: Resources modified manually in Azure Portal (violates constitution)

**Solution**:
```bash
# Run detailed what-if to see changes
az deployment sub what-if \
  --name validate-drift \
  --location eastus2 \
  --template-file bicep/main.bicep \
  --parameters @bicep/main.parameters.json

# Option A: Revert manual changes in portal to match Bicep
# Option B: Update Bicep template to match current state (if changes were intentional)
# Option C: Redeploy to force alignment (WARNING: may cause downtime)
./scripts/deploy-core.sh
```

---

## Debugging Commands Reference

### Resource Provisioning States

```bash
# All resources in resource group
az resource list --resource-group rg-ai-core \
  --query "[].{Name:name,Type:type,State:provisioningState}" -o table

# Specific resource types
az network vwan list --resource-group rg-ai-core --query '[].{Name:name,State:provisioningState}' -o table
az network vhub list --resource-group rg-ai-core --query '[].{Name:name,State:provisioningState,Routing:routingState}' -o table
az network vpn-gateway list --resource-group rg-ai-core --query '[].{Name:name,State:provisioningState}' -o table
az keyvault list --resource-group rg-ai-core --query '[].{Name:name,Location:location}' -o table
```

### Deployment History

```bash
# List all subscription-level deployments
az deployment sub list --query '[].{Name:name,State:properties.provisioningState,Timestamp:properties.timestamp}' -o table

# Show specific deployment details
az deployment sub show --name deploy-ai-core-TIMESTAMP

# Show deployment errors
az deployment sub show --name deploy-ai-core-TIMESTAMP --query properties.error
```

### Activity Logs

```bash
# Recent errors in resource group
az monitor activity-log list \
  --resource-group rg-ai-core \
  --max-events 50 \
  --query "[?level=='Error'].{Time:eventTimestamp,Operation:operationName.localizedValue,Status:status.localizedValue}" -o table

# Filter by time range
az monitor activity-log list \
  --resource-group rg-ai-core \
  --start-time 2025-12-31T00:00:00Z \
  --end-time 2025-12-31T23:59:59Z \
  --query "[?level=='Error']"
```

### Network Diagnostics

```bash
# Hub effective routes
az network vhub get-effective-routes \
  --resource-group rg-ai-core \
  --name hub-ai-eastus2

# VPN Gateway BGP peers
az network vpn-gateway show \
  --resource-group rg-ai-core \
  --name vpngw-ai-hub \
  --query 'bgpSettings.bgpPeeringAddresses'

# Check spoke connections
az network vhub connection list \
  --resource-group rg-ai-core \
  --vhub-name hub-ai-eastus2 -o table
```

### Key Vault Diagnostics

```bash
# List all secrets (requires read permission)
az keyvault secret list --vault-name kv-ai-core-lab1 -o table

# Check soft-deleted secrets
az keyvault secret list-deleted --vault-name kv-ai-core-lab1 -o table

# View RBAC permissions
az role assignment list --scope /subscriptions/<sub-id>/resourceGroups/rg-ai-core/providers/Microsoft.KeyVault/vaults/kv-ai-core-lab1
```

### DNS Private Resolver Issues

For detailed DNS resolver troubleshooting, see [dns-resolver-setup.md](dns-resolver-setup.md#troubleshooting).

**Quick Diagnostics**:

```bash
# Check resolver exists
az resource show \
  --resource-group rg-ai-core \
  --resource-type Microsoft.Network/dnsResolvers \
  --name dnsr-ai-shared \
  --query "{name:name, state:properties.provisioningState}"

# Get resolver inbound endpoint IP
RESOLVER_ID=$(az resource show -g rg-ai-core --resource-type Microsoft.Network/dnsResolvers -n dnsr-ai-shared --query id -o tsv)
az rest --method get --uri "${RESOLVER_ID}/inboundEndpoints?api-version=2022-07-01" \
  --query "value[0].properties.ipConfigurations[0].privateIpAddress" -o tsv

# Test DNS resolution from P2S client
nslookup acraihubk2lydtz5uba3q.azurecr.io 10.1.0.68

# Run automated validation
./scripts/test-dns-resolver.sh --ip 10.1.0.68
```

**Common DNS Issues**:
- **DNS queries timeout**: P2S VPN not connected or routing issue to 10.1.0.68
- **Returns public IP instead of private**: Private DNS zone not linked to vnet-ai-shared
- **Public DNS fails**: Resolver can't reach public DNS servers (check outbound routing)
- **Resolver IP changed**: Re-deployment may allocate new IP; update client DNS settings

For full troubleshooting guide, see: [DNS Resolver Troubleshooting Section](dns-resolver-setup.md#troubleshooting)

## Getting Help

### Azure Support Resources

1. **Azure Portal** → Resource → **Diagnose and solve problems**
2. **Azure Support Tickets**: [https://aka.ms/azuresupport](https://aka.ms/azuresupport)
3. **Azure CLI Help**: `az network vwan --help`
4. **Microsoft Learn**: [https://learn.microsoft.com/azure/virtual-wan/](https://learn.microsoft.com/azure/virtual-wan/)

### Community Resources

- **Microsoft Q&A**: [https://aka.ms/azureqa](https://aka.ms/azureqa)
- **Azure Updates**: [https://azure.microsoft.com/updates/](https://azure.microsoft.com/updates/)
- **GitHub Issues** (this repo): Submit issue with:
  - Deployment logs
  - Error messages
  - `az deployment sub show` output
  - `az resource list` output

### Escalation Path

1. **Level 1**: Check this troubleshooting guide
2. **Level 2**: Run validation script: `./scripts/validate-core.sh`
3. **Level 3**: Review Azure activity logs and deployment history
4. **Level 4**: Contact Azure Support with diagnostics

---

**Version**: 1.0.0  
**Last Updated**: 2025-12-31  
**Maintainer**: AI-Lab Team
