# Research: Azure API Management Standard v2

**Feature**: 006-apim-std-v2  
**Date**: 2026-01-14  
**Purpose**: Resolve technical decisions and best practices for APIM Standard v2 deployment

## Research Tasks

### 1. VNet Integration Subnet Requirements

**Question**: What are the subnet requirements for APIM Standard v2 VNet integration?

**Findings**:
- Subnet must be **dedicated** to a single APIM instance (cannot be shared with other Azure resources)
- **Minimum size**: /27 (32 addresses)
- **Recommended size**: /24 (256 addresses) to accommodate scaling
- Subnet must be **delegated** to `Microsoft.Web/serverFarms` (not Microsoft.ApiManagement like classic tiers)
- The `Microsoft.Web` resource provider must be registered in the subscription
- Subnet must be in the **same region and subscription** as the APIM instance

**Decision**: Use a /24 subnet (`10.1.0.128/25` or similar in shared services VNet) with delegation to `Microsoft.Web/serverFarms`

**Rationale**: /24 provides room for scaling while staying within the shared services VNet address space

---

### 2. NSG Rules for VNet Integration

**Question**: What NSG rules are required for APIM Standard v2 VNet integration?

**Findings**:
- **Outbound rules required**:
  | Direction | Source | Destination | Port | Protocol | Purpose |
  |-----------|--------|-------------|------|----------|---------|
  | Outbound | VirtualNetwork | Storage | 443 | TCP | Azure Storage dependency |
  | Outbound | VirtualNetwork | AzureKeyVault | 443 | TCP | Azure Key Vault dependency |
  
- **Inbound rules**: Do NOT apply for VNet integration mode (only for VNet injection in Premium v2)
- Additional outbound rules needed for backend connectivity (private endpoints, DNS)

**Decision**: Create dedicated NSG for APIM subnet with required outbound rules plus VNet/VPN access

**Rationale**: Follows Microsoft best practices while allowing connectivity to private backends

---

### 3. Shared Services VNet Integration

**Question**: Should APIM subnet be added to existing shared-services-vnet or create a new VNet?

**Findings**:
- Current shared-services-vnet has address space `10.1.0.0/24`
- Current PrivateEndpointSubnet uses `10.1.0.0/26` (64 addresses)
- Remaining space: `10.1.0.64/26`, `10.1.0.128/25`
- APIM needs dedicated subnet with delegation (incompatible with private endpoints in same subnet)

**Decision**: Add new subnet to existing shared-services-vnet at `10.1.0.64/26` (64 addresses)

**Rationale**: 
- Keeps APIM within the hub-connected VNet for routing to private endpoints
- /26 provides 64 addresses (more than /27 minimum, less waste than /24)
- Maintains single VNet simplicity while meeting APIM requirements

**Alternative Rejected**: Separate VNet would require additional hub connection and routing complexity

---

### 4. APIM Bicep Resource Configuration

**Question**: What is the correct Bicep configuration for Standard v2 APIM?

**Findings**:
```bicep
resource apiManagementService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  sku: {
    name: 'Standardv2'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'None' // VNet integration configured separately
  }
  identity: {
    type: 'SystemAssigned'
  }
}
```

- VNet integration is configured via `Microsoft.ApiManagement/service@2023-09-01-preview` or later with `virtualNetworkConfiguration`
- System-assigned managed identity enables Key Vault access for future certificate/secret needs

**Decision**: Use API version `2023-09-01-preview` or later, enable system-assigned identity

**Rationale**: Latest API version supports VNet integration configuration in Bicep

---

### 5. Developer Portal Activation

**Question**: How is the developer portal enabled and accessed?

**Findings**:
- Developer portal is **enabled by default** in Standard v2
- Portal URL: `https://{apim-name}.developer.azure-api.net`
- Gateway URL: `https://{apim-name}.azure-api.net`
- Management URL: `https://{apim-name}.management.azure-api.net`
- Portal requires explicit **publish** action after APIM deployment
- VPN clients access via public URLs (portal is always public in Standard v2)

**Decision**: Document post-deployment step to publish developer portal

**Rationale**: Portal auto-enables but requires publish action to make content visible

---

### 6. OAuth/Entra ID Integration

**Question**: How to configure OAuth 2.0 with Entra ID for API authentication?

**Findings**:
- Requires **Entra ID App Registration** for APIM
- Configure as **OAuth 2.0 authorization server** in APIM
- Apply `validate-jwt` **inbound policy** on APIs requiring auth
- Token validation endpoints: `https://login.microsoftonline.com/{tenant}/v2.0/.well-known/openid-configuration`

**Decision**: OAuth configuration is post-deployment (not part of Bicep). Document manual/script steps.

**Rationale**: App registration requires Entra ID admin permissions; configuration through Azure Portal or ARM/Bicep is complex. Initial deployment can proceed without OAuth, added as enhancement.

---

### 7. DNS Resolution for Private Endpoints

**Question**: How does APIM resolve private endpoint FQDNs?

**Findings**:
- VNet-integrated APIM uses **Azure DNS by default**
- Private DNS zones linked to shared services VNet resolve private endpoints
- DNS Resolver in core infrastructure (004-dns-resolver) already handles this
- APIM outbound traffic routes through VNet, uses VNet's DNS settings

**Decision**: No additional DNS configuration needed; leverage existing DNS resolver infrastructure

**Rationale**: Core infrastructure already provides private DNS resolution for the shared services VNet

---

## Summary of Decisions

| Topic | Decision |
|-------|----------|
| Subnet location | New subnet in shared-services-vnet |
| Subnet size | /26 (64 addresses) at `10.1.0.64/26` |
| Subnet delegation | `Microsoft.Web/serverFarms` |
| NSG | Dedicated NSG with Storage + KeyVault outbound rules |
| API version | `2023-09-01-preview` or later |
| Identity | System-assigned managed identity |
| Developer portal | Enabled by default, document publish step |
| OAuth | Post-deployment configuration, not in initial Bicep |
| DNS | Leverage existing DNS resolver infrastructure |
