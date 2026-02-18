// Private AKS Cluster Orchestration
// Deploys AKS cluster with private API server, Azure RBAC, and ACR integration
// Purpose: Container orchestration infrastructure for AI Lab

targetScope = 'subscription'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Azure region for deployment')
param location string = 'eastus2'

@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Owner tag value')
param owner string = 'AI-Lab Team'

@description('AKS cluster name')
param clusterName string = 'aks-ai-lab'

@description('Kubernetes version (leave empty for Azure default stable)')
param kubernetesVersion string = ''

@description('Number of nodes in system pool')
param nodeCount int = 3

@description('VM size for nodes')
param vmSize string = 'Standard_D2s_v3'

@description('Resource ID of the private DNS zone for AKS (use "system" for Azure-managed)')
param privateDnsZoneId string = 'system'

// Core infrastructure references (retrieved from rg-ai-core deployment)
@description('Resource ID of the ACR for image pull integration')
param acrResourceId string = ''

// ============================================================================
// VARIABLES
// ============================================================================

var resourceGroupName = 'rg-ai-aks'
var tags = {
  environment: environment
  purpose: 'aks-infrastructure'
  owner: owner
  deployedBy: 'bicep'
  project: '011-private-aks'
}

// ============================================================================
// RESOURCE GROUP
// ============================================================================

resource aksResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// AKS CLUSTER
// ============================================================================

module aksCluster '../modules/aks.bicep' = {
  name: 'deploy-aks-cluster'
  scope: aksResourceGroup
  params: {
    clusterName: clusterName
    location: location
    kubernetesVersion: kubernetesVersion
    nodeCount: nodeCount
    vmSize: vmSize
    availabilityZones: ['1', '2']
    podCidr: '10.244.0.0/16'
    serviceCidr: '10.0.0.0/16'
    dnsServiceIP: '10.0.0.10'
    privateDnsZoneId: privateDnsZoneId
    tags: tags
  }
}

// ============================================================================
// ACR ROLE ASSIGNMENT (AcrPull for kubelet identity)
// ============================================================================

// Note: Cross-resource-group role assignment for ACR pull
// This is handled by the deploy script using az cli for cross-RG RBAC
// The kubelet identity ID is output for the script to use

// ============================================================================
// OUTPUTS
// ============================================================================

@description('AKS cluster resource ID')
output clusterResourceId string = aksCluster.outputs.clusterResourceId

@description('AKS cluster name')
output clusterName string = aksCluster.outputs.clusterName

@description('AKS API server FQDN (private)')
output clusterFqdn string = aksCluster.outputs.clusterFqdn

@description('Kubelet identity object ID (for ACR pull role assignment)')
output kubeletIdentityObjectId string = aksCluster.outputs.kubeletIdentityObjectId

@description('Kubelet identity client ID')
output kubeletIdentityClientId string = aksCluster.outputs.kubeletIdentityClientId

@description('Node resource group name')
output nodeResourceGroup string = aksCluster.outputs.nodeResourceGroup

@description('Resource group name')
output resourceGroupName string = aksResourceGroup.name

@description('AKS cluster principal ID')
output clusterPrincipalId string = aksCluster.outputs.clusterPrincipalId
