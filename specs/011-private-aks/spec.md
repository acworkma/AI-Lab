# Feature Specification: Private Azure Kubernetes Service Infrastructure

**Feature Branch**: `011-private-aks`  
**Created**: 2026-02-17  
**Status**: Implemented  
**Input**: User description: "Deploy a Private Azure Kubernetes Service (AKS) cluster with private endpoint connectivity, RBAC authorization, private container registry integration, and DNS integration for secure container orchestration accessible only via VPN"

## Background

This specification creates a private AKS cluster as a foundational infrastructure project, following the same patterns established by Key Vault, Storage Account, and ACR infrastructure projects. The cluster will provide container orchestration capabilities accessible only through the VPN connection, with the API server secured via private endpoint.

This enables:
1. **Container workload hosting** - Run containerized applications in a managed Kubernetes environment
2. **Private-only access** - API server is inaccessible from public internet
3. **ACR integration** - Pull container images from the private ACR without additional credentials
4. **VPN-based management** - kubectl and other tools work only when connected via VPN

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Private AKS Cluster (Priority: P1)

As an infrastructure engineer, I need to deploy a private Azure Kubernetes Service cluster with the API server accessible only via private endpoint, integrated with the existing private DNS infrastructure and shared services VNet, so that container workloads can be orchestrated securely within the Azure environment.

**Why this priority**: This is the foundation for running containerized applications. Without the cluster, no container workloads can be scheduled or managed. The private API server ensures the control plane is never exposed to the public internet.

**Independent Test**: Can be fully tested by deploying the AKS Bicep module, verifying the cluster is created with a private API server, confirming kubectl commands work only when VPN-connected, and validating DNS resolution returns a private IP address for the API server endpoint.

**Acceptance Scenarios**:

1. **Given** AKS Bicep module exists, **When** deploying to Azure, **Then** AKS cluster is created in resource group `rg-ai-aks` with private cluster enabled
2. **Given** AKS is deployed, **When** checking network configuration, **Then** API server has no public endpoint and private endpoint is configured
3. **Given** private endpoint is configured, **When** connecting from VPN client, **Then** kubectl commands succeed via private DNS resolution
4. **Given** AKS is operational, **When** attempting kubectl from public internet (not VPN-connected), **Then** connection fails or times out
5. **Given** AKS module is deployed, **When** reviewing configuration, **Then** RBAC authorization is enabled and local accounts are disabled

---

### User Story 2 - Pull Images from Private ACR (Priority: P2)

As a developer, I need the AKS cluster to authenticate with the private ACR using managed identity, so that pods can pull container images without requiring manual credential configuration or exposing secrets.

**Why this priority**: Enables the primary workload deployment use case. Container images already stored in the private ACR need to be accessible to the cluster for pods to start. Without ACR integration, workloads cannot be deployed.

**Independent Test**: Can be tested by deploying a sample pod that references an image from the private ACR. If the pod starts successfully without ImagePullBackOff errors, ACR integration is working correctly.

**Acceptance Scenarios**:

1. **Given** AKS cluster is deployed with ACR integration, **When** deploying a pod referencing an ACR image, **Then** pod successfully pulls the image and starts
2. **Given** ACR integration is configured, **When** checking cluster identity permissions, **Then** AKS managed identity has AcrPull role on the private ACR
3. **Given** pod is running with ACR image, **When** checking image pull secret, **Then** no manual image pull secrets are required
4. **Given** ACR has private endpoint only, **When** AKS pulls images, **Then** traffic flows through private network (no public internet access)

---

### User Story 3 - Manage Cluster via kubectl (Priority: P3)

As a developer, I need to connect to the AKS cluster using kubectl from a VPN-connected workstation, so that I can deploy applications, inspect pods, and troubleshoot issues.

**Why this priority**: Enables day-to-day cluster operations. Required for deploying and managing workloads, but depends on the cluster being deployed first.

**Independent Test**: Can be tested by connecting to VPN, running `az aks get-credentials`, and executing kubectl commands like `kubectl get nodes` and `kubectl get namespaces` to verify cluster connectivity.

**Acceptance Scenarios**:

1. **Given** VPN connection is established and user has cluster admin role, **When** running `az aks get-credentials`, **Then** kubeconfig is updated with cluster connection details
2. **Given** kubeconfig is configured, **When** running `kubectl get nodes`, **Then** cluster nodes are listed with Ready status
3. **Given** kubectl access is working, **When** creating a test namespace, **Then** namespace is created successfully
4. **Given** user is not connected to VPN, **When** attempting kubectl commands, **Then** commands fail with connection timeout

---

### User Story 4 - Integrate with Existing Infrastructure Patterns (Priority: P4)

As an infrastructure engineer, I need the AKS module to follow the same deployment patterns as Key Vault, Storage, and ACR (parameterized Bicep, deployment scripts, validation scripts, documentation), so that infrastructure management is consistent across all modules.

**Why this priority**: Ensures maintainability and consistency. Important for long-term management but can be refined after core cluster functionality is operational.

**Independent Test**: Can be tested by reviewing Bicep module structure, parameter file patterns, and running deployment/validation scripts. Validates consistent infrastructure-as-code patterns.

**Acceptance Scenarios**:

1. **Given** AKS Bicep module exists, **When** reviewing file structure, **Then** module follows `bicep/aks/main.bicep` pattern with supporting modules in `bicep/modules/`
2. **Given** parameter files exist, **When** reviewing contents, **Then** no secrets are hardcoded
3. **Given** AKS deployment script exists, **When** running `./scripts/deploy-aks.sh`, **Then** script performs what-if, prompts for confirmation, and deploys with validation
4. **Given** module is deployed, **When** running idempotent redeployment, **Then** no unexpected changes are made

---

### Edge Cases

- **Cluster name collision**: AKS cluster names must be unique within the resource group; use consistent naming pattern with environment suffix
- **Node pool scaling failures**: If node pool cannot scale due to quota or capacity, deployment fails with actionable error; script checks quota pre-flight
- **API server DNS resolution failure**: If private DNS zone link is missing, kubectl commands fail; validation script checks DNS resolution from VPN
- **ACR authentication failures**: If managed identity lacks AcrPull role, pods fail with ImagePullBackOff; deployment assigns RBAC automatically
- **Kubernetes version deprecation**: System should use supported Kubernetes version; parameter defaults to current stable version
- **Network address space conflicts**: AKS subnet must not overlap with existing VNet address spaces; parameter validation prevents conflicts
- **Control plane upgrade failures**: During Kubernetes version upgrades, API server may be temporarily unavailable; operations should retry with backoff

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a Bicep deployment at `bicep/aks/main.bicep` for orchestrating AKS cluster deployment
- **FR-002**: System MUST provide a reusable module at `bicep/modules/aks.bicep` for AKS cluster resource
- **FR-003**: AKS cluster MUST be deployed to a dedicated resource group `rg-ai-aks` (following project separation pattern)
- **FR-004**: AKS cluster MUST be private (API server has no public endpoint)
- **FR-005**: AKS cluster MUST have API server accessible via private endpoint integrated with the shared services VNet
- **FR-006**: Private endpoint MUST resolve via the existing private DNS zone infrastructure in `rg-ai-core`
- **FR-006a**: AKS cluster MUST use Azure CNI Overlay network plugin with pod CIDR 10.244.0.0/16
- **FR-007**: AKS cluster MUST use Azure RBAC authorization (local accounts disabled)
- **FR-008**: AKS cluster MUST have managed identity enabled for Azure resource access
- **FR-009**: AKS managed identity MUST be granted AcrPull role on the private ACR for image pulling
- **FR-010**: AKS cluster MUST use Azure's default stable Kubernetes version (queried via `az aks get-versions` at deployment time)
- **FR-011**: AKS cluster MUST have a system node pool with 3 nodes distributed across availability zones 1 and 2
- **FR-012**: Node pools MUST use Standard_D2s_v3 VM size (2 vCPU, 8 GB RAM per node)
- **FR-012a**: Node pools MUST use Azure Linux (CBL-Mariner) as the node OS
- **FR-013**: Deployment scripts MUST follow patterns from `deploy-keyvault.sh` (what-if, validation, outputs)
- **FR-014**: Documentation MUST be provided at `docs/aks/README.md` following existing doc patterns
- **FR-015**: AKS cluster MUST have appropriate Azure tags (environment, owner, purpose) consistent with core infrastructure

### Key Entities

- **AKS Cluster**: Managed Kubernetes control plane and node pools, provides container orchestration, accessible only via private endpoint from VPN-connected clients
- **System Node Pool**: Virtual machines running Kubernetes system components and user workloads, automatically scaled and managed by AKS
- **Managed Identity**: Azure identity assigned to the cluster for authenticating to Azure services (ACR, Key Vault) without manual credential management
- **Private Endpoint**: Network interface that connects AKS API server to the private virtual network, enables kubectl access via private IP
- **Private DNS Zone**: DNS configuration for `privatelink.<region>.azmk8s.io` that resolves API server FQDN to private endpoint IP address
- **Kubeconfig**: Client configuration file containing cluster connection details and authentication tokens, retrieved via Azure CLI

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Infrastructure engineer can deploy private AKS cluster from Bicep module in under 20 minutes
- **SC-002**: VPN-connected users can successfully run kubectl commands against the cluster within 2 minutes of obtaining credentials
- **SC-003**: AKS API server is completely inaccessible from public internet (0% success rate on public access attempts)
- **SC-004**: Private DNS resolution for API server hostname resolves to private IP address from VPN clients 100% of the time
- **SC-005**: Pods referencing private ACR images start successfully without manual image pull secret configuration
- **SC-006**: AKS deployment follows same infrastructure patterns as other modules (parameterization, validation, documentation)
- **SC-007**: Cluster nodes reach Ready status within 10 minutes of deployment completion
- **SC-008**: Kubernetes workloads can be deployed and accessed by developers connected via VPN

## Clarifications

### Session 2026-02-17

- Q: What node pool sizing should be used for system node pool? → A: 3 nodes with Standard_D2s_v3 distributed across availability zones 1 and 2 (zone 3 not supported in eastus2)
- Q: What AKS network configuration should be used? → A: Azure CNI Overlay (pods use 10.244.0.0/16 internally, conserves VNet IP space)
- Q: Which Kubernetes version policy should be used? → A: Use Azure default stable version (auto-selected at deployment time)
- Q: What OS should be used for nodes? → A: Azure Linux (CBL-Mariner) - container-optimized, smaller attack surface

## Assumptions

- AKS cluster will be deployed in the same Azure region as the vWAN hub (East US 2) to minimize latency and simplify private endpoint configuration
- The existing private ACR (`acraihub<suffix>`) is deployed and accessible for AKS to pull container images
- The AKS subnet will use address space that does not conflict with existing VNet ranges (a new subnet will be created or existing private endpoint subnet will be extended)
- Initial cluster configuration uses 3x Standard_D2s_v3 nodes (2 vCPU, 8 GB RAM each) distributed across availability zones 1, 2, and 3 for high availability demonstration
- Users managing the cluster will connect via VPN and have appropriate Azure RBAC permissions for AKS operations
- DNS resolution for the private API server endpoint will leverage Azure Private DNS zones with automatic registration
- The cluster will run a single system node pool initially; additional node pools can be added later as needed
- Kubernetes version will default to the current Azure-recommended stable version at deployment time
- Network policy and ingress controller configuration are deferred to future solution projects (not part of base infrastructure)
- Azure Monitor and Container Insights integration can be enabled but is optional for the base infrastructure deployment

## Dependencies

- **Core Infrastructure (001-vwan-core)**: AKS private endpoint requires vWAN hub, VPN connectivity, and private DNS zones to be operational
- **Private ACR (002-private-acr)**: Required for AKS to pull container images without public network access
- **Shared Services VNet**: AKS requires connectivity to the shared services VNet for private endpoint placement
- **Azure RBAC Permissions**: Deploying user must have permissions to create AKS clusters, managed identities, and role assignments
- **VPN Client Connectivity**: Users must establish VPN connection to access the private AKS API server
- **Kubernetes Version Support**: Deployment depends on Azure's supported Kubernetes version matrix

## Out of Scope

- Ingress controller deployment and configuration (NGINX, Application Gateway, etc.)
- Network policy enforcement and pod security standards
- GitOps integration (Flux, ArgoCD)
- Kubernetes secrets management via external secrets operator or Key Vault CSI driver
- Horizontal pod autoscaler or cluster autoscaler configuration beyond defaults
- Multi-cluster federation or service mesh implementation
- Azure Container Apps or other container compute alternatives
- Production workload sizing and high availability configurations
- Backup and disaster recovery for cluster state
- Custom node pool configurations (GPU, spot instances, Windows nodes)
- Azure Dev Spaces or Bridge to Kubernetes developer tooling
- Prometheus/Grafana monitoring stack (Azure Monitor is the default)
