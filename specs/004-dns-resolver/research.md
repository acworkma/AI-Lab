# Phase 0: Research - DNS Private Resolver for Core Infrastructure

**Created**: 2026-01-04  
**Purpose**: Research Azure DNS Private Resolver architecture, private DNS zone integration, P2S client routing, and best practices for core deployment.

## Problem Statement

P2S VPN clients (WSL, jump boxes) querying Azure DNS (168.63.129.16) receive public IPs for private resources because:
1. Azure DNS is not VNet-aware when queried from outside linked VNets.
2. P2S clients have no automatic DNS link to private DNS zones.
3. Manual /etc/hosts entries are unsustainable as services multiply (ACR, Key Vault, Storage, App Service, etc.).

**Solution**: Deploy DNS Private Resolver in the VNet that's linked to private DNS zones, exposing an inbound endpoint IP. Queries to this IP resolve private resources to private IPs.

---

## Research Topics

### 1. Azure DNS Private Resolver Architecture

**Decision**: Single resolver with inbound endpoint in shared services VNet.

**Technical Details**:
- **Resolver**: Managed Azure DNS service (Microsoft.Network/dnsResolvers).
- **Inbound Endpoint**: Listener on a specific subnet IP that accepts queries from clients.
- **Outbound Endpoint**: (Not in MVP) For forwarding queries to on-prem or corporate DNS.
- **Scope**: Resolver is VNet-aware; inherits knowledge of private DNS zones linked to that VNet.

**Deployment Context**:
- Resolver lives in shared services VNet (10.1.0.0/24).
- Inbound endpoint in dedicated subnet (10.1.0.64/27) with service delegation.
- Inbound endpoint assigned a private IP (e.g., 10.1.0.65) by Azure.
- This IP becomes the DNS server clients query.

**References**:
- [Azure DNS Private Resolver Overview](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview)
- [Create a DNS Private Resolver](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-how-to-guide)

### 2. Private DNS Zone Resolution Through Resolver

**Decision**: Existing private DNS zones (already linked to shared VNet) are automatically queryable via resolver.

**Resolution Flow**:
1. Client (WSL) sends DNS query to resolver inbound endpoint IP (10.1.0.65:53).
2. Resolver receives query; checks its VNet's linked private DNS zones.
3. If zone found (e.g., privatelink.azurecr.io), resolver queries that zone for the record.
4. Zone returns A record (e.g., acraihubk2lydtz5uba3q → 10.1.0.5).
5. Resolver returns private IP to client.
6. If zone not found, resolver recursively queries public DNS (fallback behavior).

**Why This Works**:
- Resolver is deployed in the VNet that has links to private DNS zones.
- Zone links are not modified; resolver auto-discovers them on its VNet.
- No special configuration needed for resolver to resolve private zones.

**Implications**:
- All existing private DNS zones (ACR, Key Vault, Blob, File, SQL) work automatically.
- Future zones added to shared VNet are automatically resolvable.
- No hardcoded zone names or IP addresses in resolver config.

**References**:
- [Private DNS Zone Virtual Network Links](https://learn.microsoft.com/en-us/azure/dns/private-dns-virtual-network-links)
- [DNS Resolution for Private Endpoints](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)

### 3. P2S Client Routing to Resolver Inbound Endpoint

**Decision**: Existing vHub ↔ shared VNet connection provides routing; no additional routing configuration needed.

**Routing Path**:
1. P2S client (172.16.0.1) connects to vHub.
2. vHub has established connection to shared services VNet (via hubVirtualNetworkConnections in Bicep).
3. Routes from P2S address pool (172.16.0.0/24) to shared VNet addresses (10.1.0.0/24) are automatically created.
4. Client sends DNS query to resolver IP (10.1.0.65); packet is routed via vHub to shared VNet.
5. Resolver receives query, responds directly to client.

**Why This Works**:
- Core infrastructure (001) already established vHub ↔ shared VNet connection.
- vHub routing is dynamic; P2S clients are automatically in the routing domain.
- No NSG or UDR changes needed; existing NSG allows VPN client traffic.

**Validation**:
```bash
# From P2S client (WSL), verify routing to resolver IP
ip route get 10.1.0.65
# Expected: route via vHub (172.17.80.1 or similar)

# From shared VNet, verify inbound endpoint is reachable
ping 10.1.0.65
# Expected: pong (if ICMP allowed) or TCP 53 port is open
```

**References**:
- [Virtual Hub Routing](https://learn.microsoft.com/en-us/azure/virtual-wan/about-virtual-hub-routing)
- [Hub Virtual Network Connections](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-route-table)

### 4. Resolver Idempotency and Re-Deployment

**Decision**: Resolver and inbound endpoint can be safely re-deployed via Bicep. Azure idempotency handles most cases.

**Idempotency Behavior**:
- Deploying the same Bicep multiple times: No resource recreation if properties unchanged.
- Changing inbound subnet prefix: Requires subnet deletion/recreation (breaking; avoid in production).
- Changing resolver name: Creates new resolver (old one orphaned; manual cleanup needed).
- Updating tags: Safe; tags only updated, no recreations.

**Safe Updates**:
- Tag changes, output-only modifications.
- Scaling not applicable (single endpoint, no scale units).

**Unsafe Updates** (avoid in production; document):
- Changing inbound subnet CIDR.
- Changing resolver name.
- Deleting resolver (breaks all clients).

**Implementation**:
- Bicep module uses explicit names and consistent CIDR prefixes.
- Parameters have sensible defaults (dnsResolverName, dnsInboundSubnetPrefix).
- Documentation emphasizes not changing these values post-deployment.

**References**:
- [Bicep Idempotency](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices)

### 5. Validation and Troubleshooting Approaches

**Decision**: Multi-level validation: DNS queries, connectivity, end-to-end tests.

**Validation Levels**:

**Level 1: Resolver Existence**
```bash
az resource show -g rg-ai-core --resource-type Microsoft.Network/dnsResolvers -n dnsr-ai-shared
# Verify resolver exists and is operational
```

**Level 2: Inbound Endpoint IP**
```bash
az rest --method get --uri "/subscriptions/{subId}/resourceGroups/rg-ai-core/providers/Microsoft.Network/dnsResolvers/dnsr-ai-shared/inboundEndpoints"
# Extract inbound endpoint IP (e.g., 10.1.0.65)
```

**Level 3: DNS Query (Private Zone)**
```bash
nslookup acraihubk2lydtz5uba3q.azurecr.io 10.1.0.65
# Expected: returns 10.1.0.5 (private IP)
```

**Level 4: DNS Query (Public Domain)**
```bash
nslookup google.com 10.1.0.65
# Expected: returns public IPs (fallback via recursion)
```

**Level 5: Connectivity**
```bash
curl -v https://acraihubk2lydtz5uba3q.azurecr.io/v2/
# Expected: connects to private IP, HTTP 401 or 200 (not 403 or timeout)
```

**Troubleshooting Decision Tree**:
- Resolver doesn't exist: Deploy via Bicep.
- Queries timeout: Check routing from P2S to shared VNet (vHub connection).
- Queries return public IP: Check private DNS zone is linked to shared VNet.
- Queries fail for unrelated reason: Check resolver is operational (Azure Portal), no service degradation.

**References**:
- [DNS Troubleshooting Methodology](https://www.linux.com/training-tutorials/how-to-troubleshoot-dns-linux/)
- [Azure Diagnostics for DNS](https://learn.microsoft.com/en-us/azure/dns/troubleshoot-dns-records)

### 6. Fallback DNS Behavior

**Decision**: Resolver supports recursive queries to public DNS for non-private domains.

**Behavior**:
- Query for private zone (e.g., acraihubk2lydtz5uba3q.azurecr.io): Resolver checks linked zones, returns private IP.
- Query for public domain (e.g., google.com): Resolver doesn't find in linked zones, recursively queries public DNS, returns public IP.
- Query for non-existent domain: Resolver returns NXDOMAIN (not found).

**Client Fallback** (separate from resolver):
- If resolver IP unreachable (VPN down), client can fall back to public DNS (8.8.8.8) in /etc/resolv.conf.
- This is configured at client level (WSL), not resolver level.

**References**:
- [Recursive DNS Resolution](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)

---

## Summary of Technical Decisions

| Area | Decision | Rationale |
|------|----------|-----------|
| Resolver Location | Shared Services VNet (rg-ai-core) | Linked to all private DNS zones; serves all spokes and P2S |
| Inbound Subnet | 10.1.0.64/27 (dedicated) | Non-overlapping with PE subnet (10.1.0.0/26); service delegation required |
| Inbound Endpoint | Single endpoint, auto-assigned IP | Sufficient for MVP; scales to thousands of clients |
| Zone Resolution | Auto (linked zones) | No manual zone configuration in resolver; zones are VNet-linked |
| Fallback DNS | Recursive to public | Supports both private and public queries |
| Outbound Endpoint | Not in MVP | Future enhancement for on-prem forwarding |
| Idempotency | Bicep defaults | Parameter names/values should not change post-deployment |

---

## Open Questions Resolved

All functional requirements from spec.md are fully defined:

- ✅ Resolver location: Shared services VNet.
- ✅ Inbound endpoint IP: Auto-assigned, exposed in outputs.
- ✅ Private zone resolution: Automatic via VNet links.
- ✅ P2S routing: Existing vHub connection supports it.
- ✅ Public DNS fallback: Resolver supports recursive queries.
- ✅ Idempotency: Bicep module is safe to re-deploy.
- ✅ Validation approach: Multi-level DNS queries and connectivity tests.
- ✅ Deployment model: Integrated into core Bicep template.

## Next Steps (Phase 1)

1. Document resolver data model (entities, IP allocation, lifecycle).
2. Define deployment contract (Bicep inputs/outputs, side effects).
3. Define validation contract (test procedures, expected results).
4. Create operational quickstart (deploy, validate, troubleshoot).
5. Update GitHub Copilot context with Bicep + Azure DNS.
6. Generate implementation tasks for deployment and validation.

