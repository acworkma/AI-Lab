# Private Azure Container Registry

## Overview

This module deploys a private Azure Container Registry (ACR) with private endpoint connectivity to the core shared services infrastructure. The ACR is accessible only via the VPN connection, ensuring all container images are stored and accessed privately within the Azure environment.

**Key Components**:
- **Resource Group**: `rg-ai-acr` - Container for ACR resources
- **Azure Container Registry**: `acraihub<unique>` - Standard SKU with import support
- **Private Endpoint**: Connected to `vnet-ai-shared/PrivateEndpointSubnet` in core infrastructure
- **DNS Integration**: `privatelink.azurecr.io` private DNS zone from core infrastructure

**Deployment Region**: East US 2

## Prerequisites

### Required Infrastructure

1. **Core Infrastructure Deployed**:
   - Run `./scripts/deploy-core.sh` first
   - Core must include shared services VNet and private DNS zones
   - Verify outputs include `privateEndpointSubnetId` and `acrDnsZoneId`

2. **VPN Connection**:
   - Azure VPN Client installed and configured
   - Connected to `vpngw-ai-hub` VPN gateway
   - Required for DNS resolution and ACR access
   - See [VPN client setup guide](../core-infrastructure/vpn-client-setup.md)

### Required Tools

- **Azure CLI** (version 2.50.0 or later)
- **Docker** (optional, for docker pull/push workflows)
- **jq** (for JSON parsing in deployment script)

## Deployment

### Step 1: Verify Core Infrastructure

```bash
# Check that core infrastructure is deployed
az group show --name rg-ai-core

# Verify shared services VNet exists
az network vnet show \
  --resource-group rg-ai-core \
  --name vnet-ai-shared

# Get core outputs (save these for reference)
az deployment sub list \
  --query "[?contains(name, 'deploy-ai-core')].name | sort(@) | [-1]" \
  -o tsv
```

### Step 2: Review Parameters

```bash
cd /workspaces/AI-Lab
cat bicep/registry/main.parameters.json
```

**Default Parameters**:
- `location`: `eastus2`
- `environment`: `dev`
- `owner`: `AI-Lab Team`
- `acrSku`: `Standard`
- `privateEndpointSubnetId`: Auto-populated from core outputs
- `acrDnsZoneId`: Auto-populated from core outputs

The deployment script automatically retrieves `privateEndpointSubnetId` and `acrDnsZoneId` from core infrastructure outputs.

### Step 3: Deploy ACR

```bash
./scripts/deploy-registry.sh
```

The script will:
1. Check prerequisites and core infrastructure
2. Retrieve core outputs (private endpoint subnet and DNS zone)
3. Run what-if analysis
4. Prompt for confirmation
5. Deploy ACR with private endpoint
6. Assign RBAC roles (AcrPush, AcrPull) to deploying user
7. Verify private DNS resolution (retries up to 10 times)
8. Display deployment outputs

**Deployment Time**: 5-10 minutes

### Step 4: Verify Deployment

```bash
# Check resource group
az group show --name rg-ai-acr

# Get ACR details
ACR_NAME=$(az deployment sub show \
  --name $(az deployment sub list --query "[?contains(name, 'deploy-ai-acr')].name | sort(@) | [-1]" -o tsv) \
  --query properties.outputs.acrName.value -o tsv)

echo "ACR Name: $ACR_NAME"

# Verify private endpoint
az network private-endpoint show \
  --resource-group rg-ai-acr \
  --name ${ACR_NAME}-pe \
  --query '{name:name, provisioningState:provisioningState, privateIp:customDnsConfigs[0].ipAddresses[0]}'

# Verify DNS resolution (requires VPN connection)
nslookup ${ACR_NAME}.azurecr.io
# Should resolve to private IP: 10.0.1.x
```

## Container Image Import Workflow

### Overview

Since the ACR has public network access disabled, all image operations must be performed from a VPN-connected machine. The recommended workflow is to import images from public registries using Azure's managed import feature, which pulls images through Azure's backend infrastructure.

### Option 1: Azure ACR Import (Recommended)

This method uses Azure's backend to pull images from public registries directly into your private ACR, bypassing the need to pull images locally.

#### Import from GitHub Container Registry

```bash
# Connect to VPN first
# Verify VPN connection:
ip route | grep 172.16.0

# Login to ACR (wait 5 minutes after deployment for RBAC to propagate)
az acr login --name $ACR_NAME

# Import image from GitHub Container Registry
az acr import \
  --name $ACR_NAME \
  --source ghcr.io/owner/repository:tag \
  --image repository:tag

# Example: Import a public image
az acr import \
  --name $ACR_NAME \
  --source ghcr.io/nginxinc/nginx-unprivileged:latest \
  --image nginx:latest

# Verify import
az acr repository list --name $ACR_NAME -o table
az acr repository show-tags --name $ACR_NAME --repository nginx -o table
```

#### Import from Docker Hub

```bash
# Import from Docker Hub
az acr import \
  --name $ACR_NAME \
  --source docker.io/library/alpine:latest \
  --image alpine:latest

# Import specific version
az acr import \
  --name $ACR_NAME \
  --source docker.io/library/postgres:15-alpine \
  --image postgres:15-alpine
```

#### Import with Authentication (Private Registries)

```bash
# For private GitHub packages, create a PAT and store in Key Vault
az acr import \
  --name $ACR_NAME \
  --source ghcr.io/private-owner/private-repo:tag \
  --image private-repo:tag \
  --username <GITHUB_USERNAME> \
  --password <GITHUB_PAT>

# Or use Key Vault reference
KV_NAME=$(az deployment sub show \
  --name $(az deployment sub list --query "[?contains(name, 'deploy-ai-core')].name | sort(@) | [-1]" -o tsv) \
  --query properties.outputs.keyVaultName.value -o tsv)

GITHUB_PAT=$(az keyvault secret show \
  --vault-name $KV_NAME \
  --name github-pat \
  --query value -o tsv)

az acr import \
  --name $ACR_NAME \
  --source ghcr.io/private-owner/private-repo:tag \
  --image private-repo:tag \
  --username <GITHUB_USERNAME> \
  --password "$GITHUB_PAT"
```

### Option 2: Docker Pull/Tag/Push Workflow

Alternative approach using Docker CLI (requires Docker installed on VPN-connected machine).

```bash
# Connect to VPN
# Login to ACR
az acr login --name $ACR_NAME

# Pull image from public registry
docker pull ghcr.io/owner/repository:tag

# Tag for private ACR
docker tag ghcr.io/owner/repository:tag ${ACR_NAME}.azurecr.io/repository:tag

# Push to private ACR
docker push ${ACR_NAME}.azurecr.io/repository:tag

# Verify
docker images | grep ${ACR_NAME}.azurecr.io
```

### Verify Image in ACR

```bash
# List repositories
az acr repository list --name $ACR_NAME -o table

# List tags for a repository
az acr repository show-tags \
  --name $ACR_NAME \
  --repository <repository-name> \
  -o table

# Get image manifest
az acr repository show \
  --name $ACR_NAME \
  --image <repository-name>:tag

# Verify image digest
az acr repository show \
  --name $ACR_NAME \
  --image <repository-name>:tag \
  --query '{digest:digest, tags:tags, lastUpdateTime:lastUpdateTime}'
```

## Access Patterns for Downstream Services

### AKS Integration (Future)

When deploying Azure Kubernetes Service, attach ACR using managed identity:

```bash
# Attach ACR to AKS (when AKS is deployed)
az aks update \
  --resource-group rg-ai-aks \
  --name aks-ai-cluster \
  --attach-acr $ACR_NAME

# AKS will use managed identity with AcrPull role
```

### Container Instances

```bash
# Deploy container instance from private ACR
az container create \
  --resource-group rg-ai-app \
  --name my-container \
  --image ${ACR_NAME}.azurecr.io/repository:tag \
  --registry-login-server ${ACR_NAME}.azurecr.io \
  --registry-username $(az acr credential show --name $ACR_NAME --query username -o tsv) \
  --registry-password $(az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv)

# Note: For production, use managed identity instead of admin credentials
```

## Troubleshooting

### DNS Resolution Fails

**Symptom**:
```
nslookup acraihubxxx.azurecr.io
# Resolves to public IP or fails
```

**Solution**:
```bash
# Verify VPN connection
az network p2s-vpn-gateway show \
  --resource-group rg-ai-core \
  --name vpngw-ai-hub \
  --query provisioningState

# Check private DNS zone link
az network private-dns link vnet list \
  --resource-group rg-ai-core \
  --zone-name privatelink.azurecr.io \
  -o table

# Reconnect VPN client
# Wait 1-2 minutes for DNS propagation
```

### ACR Login Fails

**Symptom**:
```bash
az acr login --name $ACR_NAME
# Error: unauthorized
```

**Solutions**:

1. **Wait for RBAC propagation** (5 minutes after deployment):
   ```bash
   # Check role assignments
   az role assignment list \
     --scope $(az acr show --name $ACR_NAME --query id -o tsv) \
     --query '[].{role:roleDefinitionName, principal:principalName}' \
     -o table
   
   # Wait and retry
   sleep 300
   az acr login --name $ACR_NAME
   ```

2. **Verify role assignments**:
   ```bash
   # Get current user
   USER_ID=$(az ad signed-in-user show --query id -o tsv)
   
   # Assign roles manually if needed
   az role assignment create \
     --assignee $USER_ID \
     --role AcrPush \
     --scope $(az acr show --name $ACR_NAME --query id -o tsv)
   
   az role assignment create \
     --assignee $USER_ID \
     --role AcrPull \
     --scope $(az acr show --name $ACR_NAME --query id -o tsv)
   ```

### Image Import Fails

**Symptom**:
```bash
az acr import ...
# Error: unable to retrieve auth token
```

**Solutions**:

1. **Verify source registry accessibility**:
   ```bash
   # Test source image exists
   docker pull ghcr.io/owner/repository:tag
   
   # If private, verify credentials
   ```

2. **Check ACR import capability**:
   ```bash
   # Verify SKU supports import (Standard/Premium)
   az acr show --name $ACR_NAME --query sku.name -o tsv
   
   # Basic SKU does not support import
   ```

3. **Use authentication for private sources**:
   ```bash
   # Add --username and --password for private registries
   az acr import \
     --name $ACR_NAME \
     --source ghcr.io/private/repo:tag \
     --image repo:tag \
     --username <user> \
     --password <token>
   ```

### Private Endpoint Connection Failed

**Symptom**:
Private endpoint shows "Failed" provisioning state

**Diagnosis**:
```bash
az network private-endpoint show \
  --resource-group rg-ai-acr \
  --name ${ACR_NAME}-pe \
  --query provisioningState
```

**Solution**:
```bash
# Delete and recreate private endpoint
az network private-endpoint delete \
  --resource-group rg-ai-acr \
  --name ${ACR_NAME}-pe

# Redeploy ACR
./scripts/deploy-registry.sh
```

## Cleanup

To remove the ACR infrastructure:

```bash
# Delete ACR resource group
az group delete --name rg-ai-acr --yes --no-wait

# Verify deletion
az group show --name rg-ai-acr
# Error: Resource group not found (expected)
```

**Note**: This does not affect core infrastructure (VNet, DNS zones remain in rg-ai-core).

## Security Considerations

1. **Private-Only Access**: ACR has public network access disabled. All operations require VPN connection.

2. **RBAC Authorization**: Admin user disabled. Access controlled via Azure RBAC roles (AcrPush, AcrPull).

3. **Image Scanning**: Consider enabling Microsoft Defender for Containers for vulnerability scanning (additional cost).

4. **Content Trust**: For production, consider enabling Docker Content Trust for image signing (Premium SKU).

5. **Network Isolation**: Private endpoint ensures traffic stays within Azure backbone, not exposed to internet.

## Cost Optimization

**Estimated Monthly Cost** (Standard SKU):
- ACR Standard: ~$20/month (includes 100 GB storage)
- Private Endpoint: ~$7.50/month
- DNS Queries: ~$0.50/month
- **Total**: ~$28/month

**Storage Management**:
```bash
# View storage usage
az acr show-usage --name $ACR_NAME -o table

# Enable retention policy (auto-delete untagged images)
az acr config retention update \
  --registry $ACR_NAME \
  --status enabled \
  --days 7 \
  --type UntaggedManifests

# Manually purge old images
az acr repository show-tags \
  --name $ACR_NAME \
  --repository <repo> \
  --orderby time_asc \
  --output table

az acr repository delete \
  --name $ACR_NAME \
  --image <repo>:<old-tag> \
  --yes
```

## Next Steps

1. **Deploy AKS**: Create Azure Kubernetes Service and attach this ACR
2. **Import Application Images**: Copy your application container images to private ACR
3. **Configure CI/CD**: Set up GitHub Actions or Azure DevOps to build and push images
4. **Enable Monitoring**: Configure diagnostic settings to send logs to Log Analytics
