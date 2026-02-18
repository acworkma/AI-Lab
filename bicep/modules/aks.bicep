// Azure Kubernetes Service (AKS) Module
// Creates private AKS cluster with Azure RBAC, Azure CNI Overlay, and managed identity
// Purpose: Private container orchestration for lab environments

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('AKS cluster name')
@minLength(1)
@maxLength(63)
param clusterName string

@description('Azure region for deployment')
param location string

@description('Kubernetes version (leave empty for Azure default stable)')
param kubernetesVersion string = ''

@description('Number of nodes in the system node pool')
@minValue(1)
@maxValue(100)
param nodeCount int = 3

@description('VM size for node pool')
param vmSize string = 'Standard_D2s_v3'

@description('Availability zones for node pool')
param availabilityZones array = ['1', '2']

@description('Pod CIDR for Azure CNI Overlay')
param podCidr string = '10.244.0.0/16'

@description('Service CIDR for Kubernetes services')
param serviceCidr string = '10.0.0.0/16'

@description('DNS service IP (must be within serviceCidr)')
param dnsServiceIP string = '10.0.0.10'

@description('Resource ID of the subnet for AKS nodes (optional - uses kubenet if not provided)')
param subnetId string = ''

@description('Resource ID of the private DNS zone for API server (use "system" for Azure-managed)')
param privateDnsZoneId string = 'system'

@description('Tags to apply to resources')
param tags object = {}

// ============================================================================
// RESOURCES
// ============================================================================

// AKS Cluster - Private Kubernetes cluster with Azure RBAC
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  properties: {
    // Kubernetes version - empty string uses Azure default
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    
    // DNS prefix for the cluster
    dnsPrefix: clusterName
    
    // Enable Azure RBAC for Kubernetes authorization
    enableRBAC: true
    
    // Disable local accounts - Azure AD only
    disableLocalAccounts: true
    
    // Azure AD integration with Azure RBAC
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    
    // API server access - private cluster only
    apiServerAccessProfile: {
      enablePrivateCluster: true
      privateDNSZone: privateDnsZoneId
      enablePrivateClusterPublicFQDN: false
    }
    
    // Network configuration - Azure CNI Overlay
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'azure'
      podCidr: podCidr
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }
    
    // System node pool configuration
    agentPoolProfiles: [
      {
        name: 'system'
        count: nodeCount
        vmSize: vmSize
        availabilityZones: availabilityZones
        mode: 'System'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        enableAutoScaling: false
        maxPods: 110
        // Use subnet if provided
        vnetSubnetID: empty(subnetId) ? null : subnetId
        // Node labels
        nodeLabels: {
          'node.kubernetes.io/purpose': 'system'
        }
        // Taints for system nodes (optional - commented out for lab simplicity)
        // nodeTaints: ['CriticalAddonsOnly=true:NoSchedule']
      }
    ]
    
    // Auto-upgrade channel
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('AKS cluster resource ID')
output clusterResourceId string = aksCluster.id

@description('AKS cluster name')
output clusterName string = aksCluster.name

@description('AKS API server FQDN (private)')
output clusterFqdn string = aksCluster.properties.privateFQDN

@description('Kubelet managed identity object ID (for ACR pull)')
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId

@description('Kubelet managed identity client ID')
output kubeletIdentityClientId string = aksCluster.properties.identityProfile.kubeletidentity.clientId

@description('Node resource group name')
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup

@description('AKS cluster principal ID (for RBAC assignments)')
output clusterPrincipalId string = aksCluster.identity.principalId
