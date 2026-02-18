# Private Azure Kubernetes Service

## Overview

This module deploys a private Azure Kubernetes Service (AKS) cluster with private API server endpoint, Azure RBAC authorization, and integration with the private ACR for container image pulling. The cluster is accessible only via VPN connection, ensuring all Kubernetes operations are performed securely within the Azure private network.

**Key Components**:
- **Resource Group**: `rg-ai-aks` - Container for AKS resources
- **AKS Cluster**: `aks-ai-lab` - Private Kubernetes cluster with 3-node system pool
- **Node Pool**: 3x Standard_D2s_v3 across availability zones 1, 2
- **Node OS**: Azure Linux (CBL-Mariner)
- **Network**: Azure CNI Overlay with pod CIDR 10.244.0.0/16

**Deployment Region**: East US 2

## Prerequisites

### Required Infrastructure

1. **Core Infrastructure Deployed**:
   - Run `./scripts/deploy-core.sh` first
   - Core must include VPN gateway and private DNS zones
   - VPN connection must be established for kubectl access

2. **Private ACR Deployed** (recommended):
   - Run `./scripts/deploy-registry.sh` first
   - Required for pulling container images
   - AKS kubelet identity will be granted AcrPull role

3. **VPN Connection**:
   - Azure VPN Client installed and configured
   - Connected to `vpngw-ai-hub` VPN gateway
   - Required for kubectl access to private API server
   - See [VPN client setup guide](../core-infrastructure/vpn-client-setup.md)

### Required Tools

- **Azure CLI** (version 2.50.0 or later)
- **kubectl** (Kubernetes command-line tool)
- **jq** (for JSON parsing in deployment script)

### Required Azure Permissions

- Contributor on subscription (for resource group and AKS creation)
- User Access Administrator (for role assignments)
- Azure Kubernetes Service Cluster Admin Role (assigned during deployment)

## Deployment

### Step 1: Verify Prerequisites

```bash
# Check that core infrastructure is deployed
az group show --name rg-ai-core

# Verify VPN is connected (should see routes to 10.x.x.x or 172.x.x.x)
ip route | grep -E "10\.|172\."

# Check ACR is deployed (optional but recommended)
az group show --name rg-ai-acr
```

### Step 2: Review Parameters

```bash
cd /workspaces/AI-Lab
cat bicep/aks/main.parameters.json
```

**Default Parameters**:
- `location`: `eastus2`
- `environment`: `dev`
- `clusterName`: `aks-ai-lab`
- `nodeCount`: `3`
- `vmSize`: `Standard_D2s_v3`
- `kubernetesVersion`: `` (empty = Azure default stable version)

### Step 3: Deploy AKS

```bash
./scripts/deploy-aks.sh
```

The script will:
1. Check prerequisites (Azure CLI, core infrastructure, ACR)
2. Verify VM quota for Standard_D2s_v3
3. Run what-if analysis
4. Prompt for confirmation
5. Deploy AKS cluster (~10-15 minutes)
6. Assign AcrPull role to kubelet identity (if ACR exists)
7. Assign Cluster Admin role to deploying user
8. Display deployment outputs and next steps

**Deployment Time**: 10-15 minutes

### Step 4: Verify Deployment

```bash
# Run validation (basic Azure resource checks)
./scripts/validate-aks.sh

# Run full validation including kubectl tests (requires VPN)
./scripts/validate-aks.sh --full

# Check DNS resolution (requires VPN)
./scripts/validate-aks-dns.sh
```

## Cluster Access

### Get Credentials

After deployment, get kubectl credentials:

```bash
# Get credentials (requires VPN connection)
az aks get-credentials --resource-group rg-ai-aks --name aks-ai-lab

# Verify connection
kubectl get nodes
```

Expected output:
```
NAME                                STATUS   ROLES   AGE   VERSION
aks-system-12345678-vmss000000      Ready    agent   10m   v1.33.x
aks-system-12345678-vmss000001      Ready    agent   10m   v1.33.x
aks-system-12345678-vmss000002      Ready    agent   10m   v1.33.x
```

### Basic Operations

```bash
# List namespaces
kubectl get namespaces

# Create a test namespace
kubectl create namespace test-ns

# List pods in all namespaces
kubectl get pods -A

# Delete test namespace
kubectl delete namespace test-ns
```

## Using Private ACR Images

### Pull Images from Private ACR

The AKS kubelet identity is automatically granted AcrPull role during deployment. No manual image pull secrets are needed.

```bash
# Get ACR name
ACR_NAME=$(az acr list --resource-group rg-ai-acr --query "[0].name" -o tsv)

# Deploy a sample pod using ACR image
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: sample-nginx
  namespace: default
spec:
  containers:
  - name: nginx
    image: ${ACR_NAME}.azurecr.io/nginx:latest
    ports:
    - containerPort: 80
EOF

# Check pod status
kubectl get pod sample-nginx

# Clean up
kubectl delete pod sample-nginx
```

### Import Images to ACR

Before deploying workloads, import required images to the private ACR:

```bash
# Import nginx from Docker Hub
az acr import \
  --name $ACR_NAME \
  --source docker.io/library/nginx:latest \
  --image nginx:latest

# Import from GitHub Container Registry
az acr import \
  --name $ACR_NAME \
  --source ghcr.io/owner/repo:tag \
  --image repo:tag
```

## Troubleshooting

### kubectl Connection Timeout

**Symptom**: `kubectl get nodes` hangs or times out

**Cause**: VPN not connected or DNS resolution failing

**Solution**:
1. Verify VPN connection: `ip route | grep 172`
2. Check DNS resolution: `./scripts/validate-aks-dns.sh`
3. Re-establish VPN connection if needed

### ImagePullBackOff Errors

**Symptom**: Pods stuck in `ImagePullBackOff` status

**Cause**: Image not in ACR or kubelet identity lacks AcrPull role

**Solution**:
1. Verify image exists in ACR: `az acr repository list --name $ACR_NAME`
2. Check role assignment: `./scripts/grant-aks-acr-role.sh`
3. Wait 1-2 minutes for role propagation

### Node Not Ready

**Symptom**: Nodes show `NotReady` status

**Cause**: Node provisioning issue or network problem

**Solution**:
1. Check node conditions: `kubectl describe node <node-name>`
2. Review Azure activity log for provisioning errors
3. If persistent, delete and recreate the cluster

### Insufficient Quota

**Symptom**: Deployment fails with quota error

**Cause**: Insufficient vCPU quota for Standard_D2s_v3

**Solution**:
1. Check current usage: `az vm list-usage --location eastus2 -o table`
2. Request quota increase: https://aka.ms/ProdportalCRP

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         VPN Client                               │
│                    (Entra ID Auth)                               │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                     Virtual WAN Hub                              │
│                      (rg-ai-core)                                │
│                   • P2S VPN Gateway                              │
│                   • DNS Resolver                                 │
└─────────────────────────┬───────────────────────────────────────┘
                          │
         ┌────────────────┼────────────────┐
         │                │                │
┌────────▼────────┐ ┌─────▼──────┐ ┌───────▼───────┐
│   Private ACR    │ │  Private   │ │   Private     │
│  (rg-ai-acr)     │ │  AKS       │ │   Storage     │
│                  │ │ (rg-ai-aks)│ │(rg-ai-storage)│
│ • Container      │ │            │ │               │
│   Images         │ │ • 3 Nodes  │ │ • Blob Data   │
│                  │ │ • AZ 1,2,3 │ │               │
└──────────────────┘ │ • CBL-     │ └───────────────┘
                     │   Mariner  │
                     └────────────┘
                          │
                    ┌─────▼─────┐
                    │  Pod CIDR  │
                    │10.244.0.0/ │
                    │    16      │
                    └───────────┘
```

## Cleanup

To remove all AKS resources:

```bash
./scripts/cleanup-aks.sh
```

This will:
1. List all resources in rg-ai-aks
2. Prompt for confirmation
3. Remove kubectl context
4. Delete the resource group (runs in background)

## Configuration Reference

### Bicep Module Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `clusterName` | string | `aks-ai-lab` | AKS cluster name |
| `location` | string | `eastus2` | Azure region |
| `kubernetesVersion` | string | `` | K8s version (empty = Azure default) |
| `nodeCount` | int | `3` | Number of nodes in system pool |
| `vmSize` | string | `Standard_D2s_v3` | VM size for nodes |
| `privateDnsZoneId` | string | `system` | Private DNS zone ID |

### Resource Naming

| Resource | Name | Resource Group |
|----------|------|----------------|
| AKS Cluster | `aks-ai-lab` | `rg-ai-aks` |
| Node Pool | `system` | `MC_rg-ai-aks_aks-ai-lab_eastus2` |
| Managed Identity | `aks-ai-lab-agentpool` | `MC_rg-ai-aks_...` |

### Network Configuration

| Setting | Value |
|---------|-------|
| Network Plugin | Azure CNI Overlay |
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.0.0.0/16 |
| DNS Service IP | 10.0.0.10 |
| Outbound Type | LoadBalancer |

## Related Documentation

- [Core Infrastructure](../core-infrastructure/README.md)
- [Private ACR](../registry/README.md)
- [Private Storage](../storage-infra/README.md)
- [VPN Client Setup](../core-infrastructure/vpn-client-setup.md)
