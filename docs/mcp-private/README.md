# Private MCP Server — ACA + Private APIM + Copilot Studio

Connect a Copilot Studio agent to the MCP server running in ACA through a **fully private** APIM gateway — zero public endpoints. Copilot Studio reaches the private gateway through Power Platform VNet delegation.

## Architecture

```
┌──────────────┐   PP VNet        ┌──────────────────┐    VNet routing    ┌──────────────────┐
│  Copilot     │   delegation     │  APIM Gateway    │                   │  ACA Environment │
│  Studio      │ ────────────────►│  (private PE)    │ ─────────────────►│  (private VNet)  │
│              │                  │                  │                   │                  │
│  Managed PP  │ ◄────────────────│  JWT validation  │ ◄─────────────────│  MCP Server      │
│  Environment │   SSE stream     │  SSE passthrough │   SSE stream      │  port 3333       │
└──────┬───────┘                  └──────────────────┘                   └──────────────────┘
       │                                │                                       ▲
       │ Container injected             │                                       │ AcrPull
       │ into delegated subnet          │                                       │
       ▼                          rg-ai-apim-private                     ┌──────┴───────┐
┌──────────────┐                  apim-ai-lab-private                    │  rg-ai-acr   │
│  PowerPlat-  │                  publicNetworkAccess:                   │  Private ACR │
│  formSubnet  │                    Disabled                             └──────────────┘
│  10.1.1.0/27 │
│  (delegated) │                  Traffic path:
└──────────────┘                  PP subnet → PE subnet → APIM → VNet integration → ACA
                                  All within vnet-ai-shared — no public internet
```

### How It Works

1. Power Platform injects a container into the delegated subnet at runtime
2. The container gets a NIC with a private IP and uses VNet DNS
3. The custom connector resolves `apim-ai-lab-private.azure-api.net` via `privatelink.azure-api.net` private DNS zone
4. DNS returns the private endpoint IP → traffic hits APIM's private endpoint
5. APIM validates JWT, forwards to ACA backend via VNet integration
6. MCP server responds with SSE stream back through the same private path

**Zero public network exposure at any point.**

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Private APIM | `rg-ai-apim-private` deployed via `deploy-apim-private.sh` |
| ACA + MCP Server | `mcp-server` container app in `rg-ai-aca` |
| Core Infrastructure | vWAN hub, shared services VNet, DNS resolver |
| Private ACR | Container registry with MCP server image |
| Azure CLI | Version 2.50.0 or later |
| PowerShell 7+ | For Power Platform enterprise policy setup |
| Microsoft 365 | Copilot Studio license (includes Managed Environment) |
| VPN Connection | For testing and validation |
| jq | For JSON processing |

## Quick Start

### Phase 0: Create a Managed Power Platform Environment

> **Do NOT enable this on your existing environment.** VNet delegation affects ALL connector traffic in that environment, which would break your existing public solution. Create a new one.

1. **Open the Power Platform admin center**: [https://admin.powerplatform.microsoft.com](https://admin.powerplatform.microsoft.com)

2. **Create a new environment**:
   - Click **Environments** → **+ New**
   - Name: `AI Lab - Private` (or similar)
   - Region: Same region as your Azure deployment (e.g., United States)
   - Type: **Developer** or **Production**
   - Toggle **Enable Managed Environment** to **Yes**
   - Click **Next** → **Save**

3. **Wait for provisioning** (typically 2-5 minutes). Status will show "Ready".

4. **Record the Environment ID**:
   - Click into the environment → copy the Environment ID from the URL or Details panel
   - Format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

### Phase 1: Deploy MCP API to Private APIM

1. **Configure JWT Validation**

   Edit `bicep/mcp-api-private/policies/jwt-validation.xml` and set the values for your environment:

   | XML Attribute / Element | Replace With |
   |-------------------------|-------------|
   | `tenant-id` | Your Entra tenant ID |
   | `<application-id>` inside `<client-application-ids>` | Authorized client app ID(s) — added in Phase 3 |
   | `<audience>` | API resource ID (bare GUID and `api://` form) |

2. **Deploy MCP API**

   ```bash
   ./scripts/deploy-mcp-api-private.sh
   ```

   This deploys the MCP API definition (with JWT validation and SSE passthrough policies) into the existing private APIM instance.

3. **Validate**

   ```bash
   ./scripts/validate-mcp-private.sh
   ```

### Phase 2: Link Power Platform to VNet

> **Region requirement**: Power Platform "United States" geography requires VNets in `eastus` **and** `westus` — not `eastus2`. If your hub is in `eastus2`, create dedicated PP VNets in both required regions and peer them to the hub.

1. **Create Enterprise Policy**

   ```bash
   ./scripts/setup-pp-vnet.sh
   ```

   This script:
   - Verifies the Power Platform subnet exists with the correct delegation
   - Generates PowerShell commands to create an enterprise policy and link it to your PP environment
   - Optionally runs them if `pwsh` is available

   If running manually in PowerShell:
   ```powershell
   # Install the module (one time)
   Install-Module -Name Microsoft.PowerPlatform.EnterprisePolicies -Force

   # Authenticate
   Connect-AzAccount

   # Create enterprise policy
   New-SubnetInjectionEnterprisePolicy `
     -SubscriptionId "<subscription-id>" `
     -ResourceGroup "<rg>" `
     -EnterprisePolicyName "pp-vnet-policy" `
     -EnterprisePolicyLocation "eastus" `
     -VnetId "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet-name>" `
     -SubnetName "PowerPlatformSubnet"

   # Link to PP environment
   New-SubnetInjection `
     -EnvironmentId "<pp-environment-id>" `
     -PolicyArmId "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.PowerPlatform/enterprisePolicies/pp-vnet-policy"
   ```

2. **Verify VNet Linkage**

   In the Power Platform admin center:
   - Navigate to your environment → **Settings** → **Product** → **Virtual Network**
   - Status should show **Active** with the subnet name

### Phase 3: Copilot Studio Agent + Custom Connector

> **Important**: Copilot Studio agents use Entra **Agent Identities** (type `ServiceIdentity`), which **cannot hold client secrets**. The custom connector needs its own separate Entra app registration with a secret for OAuth. The agent and the connector app registration are two different things.

1. **Register a Connector App in Entra ID**

   Create a regular app registration for the custom connector. This is **not** the agent — it is the identity the connector uses to authenticate with APIM.

   ```bash
   # Create the app registration
   az ad app create --display-name "Private MCP Connector"

   # Note the appId from the output — save this as CONNECTOR_CLIENT_ID
   ```

2. **Create a Client Secret**

   ```bash
   # Create a secret — save the "password" value as CONNECTOR_CLIENT_SECRET
   # (you cannot retrieve it again after this command)
   az ad app credential reset --id <CONNECTOR_CLIENT_ID> --append \
     --display-name "private-mcp-connector" --years 1
   ```

3. **Grant API Permissions**

   ```bash
   # Grant delegated permission (user_impersonation on the MCP API resource)
   az ad app permission add --id <CONNECTOR_CLIENT_ID> \
     --api 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 \
     --api-permissions faa0043a-3d8e-472b-bbc3-69aa95408184=Scope

   # Create a service principal (required before granting consent)
   az ad sp create --id <CONNECTOR_CLIENT_ID>

   # Grant admin consent
   az ad app permission grant --id <CONNECTOR_CLIENT_ID> \
     --api 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 \
     --scope user_impersonation
   ```

4. **Authorize the Connector in APIM JWT Policy**

   Add the connector's client ID to `bicep/mcp-api-private/policies/jwt-validation.xml` inside the `<client-application-ids>` block:

   ```xml
   <client-application-ids>
       <application-id><CONNECTOR_CLIENT_ID></application-id>
   </client-application-ids>
   ```

   Then redeploy:

   ```bash
   ./scripts/deploy-mcp-api-private.sh --auto-approve
   ```

5. **Create Standard HTTP Custom Connector**

   In [https://make.powerapps.com](https://make.powerapps.com) → switch to your **AI Lab - Private** environment:

   1. Navigate to **Custom connectors** → **+ New custom connector** → **Create from blank**

   2. **General** tab:

      | Setting | Value |
      |---------|-------|
      | Connector name | `MCP Server (Private)` |
      | Host | `apim-ai-lab-private.azure-api.net` |
      | Base URL | `/mcp/` |
      | Scheme | HTTPS |

   3. **Security** tab (OAuth 2.0):

      | Setting | Value |
      |---------|-------|
      | Authentication type | OAuth 2.0 |
      | Identity Provider | Azure Active Directory |
      | Client ID | `CONNECTOR_CLIENT_ID` from step 1 |
      | Client secret | `CONNECTOR_CLIENT_SECRET` from step 2 |
      | Authorization URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize` |
      | Token URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
      | Refresh URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
      | Scope | `api://6cb63aba-6d0d-4f06-957e-c584fdeb23d7/user_impersonation` |
      | Resource URL | `6cb63aba-6d0d-4f06-957e-c584fdeb23d7` |

   4. After saving Security, copy the **Redirect URL** shown at the top of the Security page, then add it to the connector's app registration:

      ```bash
      az ad app update --id <CONNECTOR_CLIENT_ID> \
        --web-redirect-uris "<redirect-url-from-connector>"
      ```

   5. **Definition** tab — add the MCP POST action:
      - Click **New action**
      - Summary: `MCPCall`
      - Request: click **Import from sample** → Method: `POST`, URL: `/`
      - Body: Raw JSON

   6. Click **Create connector** → **Test** tab → create a new connection (sign in via OAuth)

   > **Why standard HTTP connector instead of MCP connector?** The standard custom connector has GA-level support for Power Platform VNet integration. Traffic routes through the delegated subnet and resolves the private endpoint via VNet DNS — no public network exposure at any point.

6. **Create Agent and Wire Connector**

   1. Open [Copilot Studio](https://copilotstudio.microsoft.com)
   2. Switch to your **AI Lab - Private** environment (top-right environment picker)
   3. Click **Create** → **New agent**
   4. Name: `Private MCP Agent` (or similar)
   5. Click **Create**
   6. Go to **Actions** → **Add an action** → select your `MCP Server (Private)` connector
   7. Select the `MCPCall` action
   8. Configure input/output mapping as needed
   9. **Save** and **Test** — the agent should be able to call the private MCP server

### Phase 4: Validate End-to-End

1. **Run Solution Validation**

   ```bash
   ./scripts/validate-mcp-private.sh
   ```

2. **Test from VPN**

   ```bash
   # Resolve APIM through private DNS (requires VPN)
   nslookup apim-ai-lab-private.azure-api.net
   # Should resolve to a private IP (10.x.x.x), NOT a public IP

   # Test MCP endpoint (requires VPN + valid token)
   TOKEN=$(az account get-access-token \
     --resource 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 \
     --query accessToken -o tsv)
   curl -X POST https://apim-ai-lab-private.azure-api.net/mcp/ \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
   ```

3. **Test from Copilot Studio**

   Ask the agent:
   - "What time is it?"
   - "What is the container runtime info?"

   The agent should invoke the MCP tools through the private path.

## MCP Tools

| Tool | Parameters | Returns | Description |
|------|-----------|---------|-------------|
| `get_current_time` | `timezone_name` (default: "UTC") | ISO 8601 timestamp | Returns current UTC time |
| `get_runtime_info` | — | `{hostname, version}` | Returns container identity and version |

## File Structure

```
AI-Lab/
├── bicep/
│   └── mcp-api-private/
│       ├── main.bicep                 # MCP API definition for private APIM
│       └── policies/
│           ├── jwt-validation.xml     # Entra ID JWT validation
│           └── mcp-passthrough.xml    # SSE streaming passthrough
├── scripts/
│   ├── deploy-mcp-api-private.sh      # Deploy MCP API to private APIM
│   ├── setup-pp-vnet.sh              # Power Platform VNet enterprise policy
│   ├── validate-mcp-private.sh        # Solution validation
│   └── cleanup-mcp-private.sh         # Remove MCP API from APIM
├── docs/mcp-private/
│   └── README.md                      # This file
└── specs/016-mcp-private/
    └── spec.md                        # Feature specification
```

### Infrastructure Dependencies (not part of this project)

```
bicep/apim-private/                    # 015-apim-private (infra project)
bicep/modules/apim-private.bicep       # Private APIM module
bicep/modules/pp-subnet.bicep          # PP delegated subnet module
bicep/modules/private-dns-zone.bicep   # DNS zone module
mcp-server/                            # 013-mcp-server (solution project)
```

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy-mcp-api-private.sh` | Deploy MCP API definition to private APIM |
| `setup-pp-vnet.sh` | Create enterprise policy and link PP environment |
| `validate-mcp-private.sh` | Validate MCP API, backend, PP subnet, DNS |
| `cleanup-mcp-private.sh` | Remove MCP API from APIM |

## Troubleshooting

### MCP API Deployment

**APIM not found**
```
APIM instance apim-ai-lab-private not found
```
Solution: Deploy the private APIM infrastructure first:
```bash
./scripts/deploy-apim-private.sh
```

**JWT policy placeholder warning**
The deploy script warns if `jwt-validation.xml` still has `REPLACE_WITH` placeholders. Edit the file with your actual tenant ID, client app ID, and audience before deploying.

### Power Platform VNet Issues

**Enterprise policy creation fails**
- Ensure subnet has delegation to `Microsoft.PowerPlatform/enterprisePolicies`
- Verify the subnet has no existing resources
- Check PowerShell module version: `Get-Module Microsoft.PowerPlatform.EnterprisePolicies -ListAvailable`

**Region mismatch**
PP "United States" geography requires VNets in `eastus` + `westus`. If your hub is in `eastus2`, create separate PP VNets in both required regions and peer them to the hub.

**Connector traffic not using VNet**
1. Verify the PP environment is **Managed** (admin center → environment → Details)
2. Verify VNet linkage is **Active** (admin center → environment → Settings → Virtual Network)
3. Ensure the custom connector is in the **same** Managed Environment
4. Check that the connector uses `apim-ai-lab-private.azure-api.net` as the host

**VNet delegation affects all connectors**
This is expected. When VNet support is enabled on a PP environment, ALL custom connector traffic routes through the delegated subnet. This is why we create a **separate** Managed Environment.

### Entra / OAuth Issues

**Agent Identity cannot hold a secret**
Copilot Studio agents use Entra Agent Identities (type `ServiceIdentity`), which do not support `passwordCredentials`. Create a separate regular app registration for the custom connector instead.

**401 Unauthorized**
- JWT validation policy may be blocking requests
- Verify token audience matches `jwt-validation.xml`
- Check that the connector's app client ID is in the `<client-application-ids>` list
- Verify admin consent was granted: `az ad app permission list-grants --id <app-id>`

### Connectivity Issues

**Connection timeout from Copilot Studio**
1. Verify the PP VNet delegation is active
2. Check that DNS resolution works from inside the VNet
3. Verify NSG on the PE subnet allows inbound from the PP subnet range (10.1.1.0/27)

**504 Gateway Timeout from APIM**
- Backend (ACA MCP server) is not responding:
  ```bash
  az containerapp show --name mcp-server --resource-group rg-ai-aca \
    --query "properties.provisioningState" -o tsv
  ```
- Check APIM can reach the backend through VNet integration

**Cannot resolve APIM URL from VPN**
- Verify VPN is connected
- Check `privatelink.azure-api.net` DNS zone is linked to VNet
- Test: `nslookup apim-ai-lab-private.azure-api.net` should return a 10.x.x.x IP

## Related Documentation

- [Private APIM Infrastructure](../apim-private/README.md)
- [MCP Server (Public)](../mcp-server/README.md) — Public variant of this solution
- [Public APIM](../apim/README.md)
- [ACA Environment](../aca/README.md) — Container Apps environment
- [Core Infrastructure](../core-infrastructure/README.md) — VNet, DNS, VPN
- [Azure APIM Private Endpoint](https://learn.microsoft.com/en-us/azure/api-management/private-endpoint)
- [Power Platform VNet Support](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [PP Enterprise Policies PowerShell](https://learn.microsoft.com/en-us/power-platform/admin/setup-vnet)

## Security Considerations

- ✅ No public network exposure — APIM gateway is private endpoint only
- ✅ JWT/OAuth 2.0 validation on all API operations
- ✅ Separate app registration for connector — agent identity stays untouched
- ✅ Power Platform VNet delegation — connector traffic stays in VNet
- ✅ Separate Managed Environment — does not affect existing public solution
- ✅ Standard HTTP connector — GA-supported for VNet integration
- ✅ All traffic: PP subnet → PE → APIM → VNet integration → ACA (no internet)
