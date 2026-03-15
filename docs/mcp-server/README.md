# MCP Server — ACA + APIM + Copilot Studio

Deploy a demo MCP (Model Context Protocol) server as a container app in the private Azure Container Apps environment, expose it publicly through Azure API Management with Entra ID JWT authentication, and connect it to Copilot Studio as an AI agent tool.

## Architecture

```
┌──────────────┐    OAuth 2.0     ┌──────────────────┐    VNet routing    ┌──────────────────┐
│  Copilot     │   (Entra ID)    │   APIM Gateway   │                   │  ACA Environment │
│  Studio      │ ───────────────►│   (public)       │ ─────────────────►│  (private VNet)  │
│              │                 │                  │                   │                  │
│  Agent ID:   │ ◄───────────────│  JWT validation  │ ◄─────────────────│  MCP Server      │
│  b159da1b    │   SSE stream    │  SSE passthrough │   SSE stream      │  port 3333       │
└──────────────┘                 └──────────────────┘                   └──────────────────┘
       │                                │                                       ▲
       │                                │                                       │ AcrPull
       │                          rg-ai-apim                                    │
       │                       apim-ai-lab-0115                          ┌──────┴───────┐
       │                                                                 │  rg-ai-acr   │
  Entra Agent Identity                                                   │  Private ACR │
  (auto-provisioned)                                                     └──────────────┘
```

## MCP Tools

| Tool | Parameters | Returns | Description |
|------|-----------|---------|-------------|
| `get_current_time` | `timezone_name` (default: "UTC") | ISO 8601 timestamp | Returns current UTC time |
| `get_runtime_info` | — | `{hostname, version}` | Returns container identity and version |

## Prerequisites

| Requirement | Details |
|------------|---------|
| Core Infrastructure | `rg-ai-core` with VNet, DNS zones, VPN gateway |
| ACA Environment | `rg-ai-aca` with `cae-ai-lab` (deploy via `scripts/deploy-aca.sh`) |
| Private ACR | `rg-ai-acr` with container registry (deploy via `scripts/deploy-registry.sh`) |
| APIM | `rg-ai-apim` with `apim-ai-lab-0115` (deploy via `scripts/deploy-apim.sh`) |
| VPN Connection | Required for ACR image push and direct ACA validation |
| Docker | Installed locally for building and pushing images over VPN |
| Azure CLI | ≥2.50 with `containerapp` extension |
| jq | For JSON parsing in scripts |
| Copilot Studio | Microsoft 365 Copilot license with Frontier enabled |

## Quick Start

### 1. Build and Deploy MCP Server to ACA

```bash
# Build image locally and push to private ACR (requires Docker + VPN)
sudo docker build -t mcp-server:v1 mcp-server/
ACR_NAME=$(az acr list -g rg-ai-acr --query '[0].loginServer' -o tsv)
TOKEN=$(az acr login --name $ACR_NAME --expose-token --query accessToken -o tsv)
sudo docker login $ACR_NAME -u 00000000-0000-0000-0000-000000000000 -p $TOKEN
sudo docker tag mcp-server:v1 $ACR_NAME/mcp-server:v1
sudo docker push $ACR_NAME/mcp-server:v1

# Deploy container app to ACA
./scripts/deploy-mcp-server.sh --skip-build --auto-approve
```

### 2. Deploy MCP API to APIM

```bash
# Deploy API definition with JWT validation and SSE passthrough policies
./scripts/deploy-mcp-api.sh
```

### 3. Validate

```bash
# Infrastructure validation (requires VPN)
./scripts/validate-mcp-server.sh

# Functional test — direct to ACA (requires VPN)
python3 scripts/test-mcp-server.py

# End-to-end test — through APIM (public, requires Azure CLI login)
bash scripts/test-mcp-api.sh
```

### 4. Connect Copilot Studio

See [Copilot Studio Integration](#copilot-studio-integration) below.

### 5. Cleanup

```bash
# Delete container app only (preserves ACA environment)
./scripts/cleanup-mcp-server.sh

# Also remove image from ACR
./scripts/cleanup-mcp-server.sh --clean-image
```

## Deployment Flow

```
deploy-mcp-server.sh
├── 1. Check prerequisites (az CLI, ACR, ACA environment)
├── 2. Discover ACR (auto-detect name and login server)
├── 3. Confirm deployment (unless --auto-approve)
├── 4. Build image (az acr build → remote build in ACR)
├── 5. Deploy container app (az containerapp create/update)
├── 6. Assign AcrPull role (managed identity → ACR)
└── 7. Show outputs (FQDN, endpoint, next steps)
```

## File Structure

```
AI-Lab/
├── mcp-server/                          # Application code
│   ├── server.py                        # FastMCP server with demo tools
│   ├── requirements.txt                 # Python dependencies (mcp[cli])
│   ├── Dockerfile                       # Container image definition
│   └── .dockerignore                    # Build context exclusions
├── bicep/
│   ├── modules/
│   │   └── container-app.bicep          # Reusable container app module
│   └── mcp-api/                         # APIM API definition
│       ├── main.bicep                   # API + operations + policies
│       └── policies/
│           ├── jwt-validation.xml       # Entra ID JWT validation
│           └── mcp-passthrough.xml      # SSE streaming passthrough
├── scripts/
│   ├── deploy-mcp-server.sh             # Build + deploy container app
│   ├── deploy-mcp-api.sh               # Deploy API definition to APIM
│   ├── validate-mcp-server.sh           # Infrastructure validation
│   ├── test-mcp-server.py               # Functional test (direct to ACA)
│   ├── test-mcp-api.sh                  # End-to-end test (through APIM)
│   └── cleanup-mcp-server.sh            # Container app cleanup
├── docs/mcp-server/
│   └── README.md                        # This file
└── specs/013-mcp-server/
    ├── spec.md                          # Feature specification
    ├── plan.md                          # Implementation plan
    └── tasks.md                         # Task tracking
```

## Configuration

### Deploy Script Options

| Option | Default | Description |
|--------|---------|-------------|
| `--name` | `mcp-server` | Container app name |
| `--tag` | `v1` | Image tag |
| `--skip-build` | false | Skip image build, use existing |
| `--auto-approve` | false | Skip confirmation prompt |

### Container App Settings

| Setting | Value |
|---------|-------|
| CPU | 0.25 cores |
| Memory | 0.5 Gi |
| Min Replicas | 1 |
| Max Replicas | 3 |
| Target Port | 3333 |
| Ingress | External (VNet-injected environment, no public internet) |
| Transport | HTTP (streamable HTTP/SSE) |
| Identity | System-assigned managed identity |

### MCP Transport

The server uses **streamable HTTP** transport (MCP over HTTP with SSE):
- Endpoint: `POST https://<fqdn>/mcp`
- Protocol: JSON-RPC 2.0 over HTTP
- Content-Type: `application/json`
- Response: `application/json` or `text/event-stream`

## Validation Checks

### Infrastructure (`validate-mcp-server.sh`)

| Check | Description |
|-------|-------------|
| App exists | Container app resource in Azure |
| Provisioning state | Must be "Succeeded" |
| Ingress config | External, port 3333 |
| Managed identity | System-assigned enabled |
| AcrPull role | Role assigned on ACR |
| DNS resolution | Resolves to private IP (VPN required) |
| Active revision | Latest revision is running |

### Functional — Direct (`test-mcp-server.py`)

| Test | Validates |
|------|----------|
| MCP handshake | Initialize + initialized notification |
| get_current_time | Returns valid ISO 8601 timestamp |
| get_runtime_info | Returns hostname + version "1.0.0" |

### Functional — Through APIM (`test-mcp-api.sh`)

| Test | Validates |
|------|----------|
| Unauthenticated request | Returns 401 Unauthorized |
| MCP initialize | Returns serverInfo with valid token |
| tools/list | Returns get_current_time and get_runtime_info |
| tools/call | Invokes get_current_time, returns timestamp |

## Troubleshooting

### Image build fails
```bash
# Check ACR connectivity (requires VPN)
az acr login --name <acr-name>

# Build with verbose output
az acr build --registry <acr-name> --image mcp-server:v1 mcp-server/ --verbose
```

### Container app won't start
```bash
# Check revision logs
az containerapp logs show --name mcp-server --resource-group rg-ai-aca --follow

# Check revision status
az containerapp revision list --name mcp-server --resource-group rg-ai-aca -o table
```

### DNS resolution fails
```bash
# Verify VPN is connected
./scripts/validate-aca-dns.sh

# Check FQDN
az containerapp show --name mcp-server --resource-group rg-ai-aca --query "properties.configuration.ingress.fqdn" -o tsv
```

### AcrPull fails (image pull error)
```bash
# Check identity
az containerapp show --name mcp-server --resource-group rg-ai-aca --query "identity" -o json

# Verify role (may take 1-2 minutes to propagate)
az role assignment list --assignee <principal-id> --role AcrPull --all -o table
```

## APIM Integration

The MCP server is exposed publicly through Azure API Management with Entra ID JWT authentication using the `validate-azure-ad-token` policy.

### Public Endpoint

```
POST https://apim-ai-lab-0115.azure-api.net/mcp/
Authorization: Bearer <JWT from Entra ID>
Content-Type: application/json
```

### Authentication

| Setting | Value |
|---------|-------|
| Policy | `validate-azure-ad-token` |
| Tenant | `38c1a7b0-f16b-45fd-a528-87d8720e868e` |
| API Resource (audience) | `6cb63aba-6d0d-4f06-957e-c584fdeb23d7` (`apim-ai-lab-0115-devportal`) |
| Authorized Client | `b159da1b-bbe5-461e-922a-ef22194461c3` (Demo Agent — Copilot Studio) |
| Delegated Scope | `api://6cb63aba-6d0d-4f06-957e-c584fdeb23d7/user_impersonation` |

### SSE Streaming

The operation-level policy uses `<forward-request buffer-response="false" />` to ensure APIM does not buffer SSE responses. This is critical for MCP streamable HTTP transport.

## Copilot Studio Integration

Copilot Studio connects to the APIM-hosted MCP endpoint using OAuth 2.0 (Manual mode). When you create an agent in Copilot Studio, it auto-provisions an **Entra Agent Identity** — a first-class identity type for AI agents (visible under Entra Admin Center → Agent ID → All agent identities).

### Setup

1. **Entra Agent Identity**: Copilot Studio auto-creates this when you build an agent. Record the Application (client) ID.

2. **Add client secret** to the agent identity:
   ```bash
   az ad app credential reset --id <agent-app-id> --display-name "MCP APIM Access" --years 1
   ```

3. **Grant delegated permission** (`user_impersonation` on the API resource):
   ```bash
   az ad app permission add --id <agent-app-id> \
     --api 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 \
     --api-permissions faa0043a-3d8e-472b-bbc3-69aa95408184=Scope
   az ad app permission grant --id <agent-app-id> \
     --api 6cb63aba-6d0d-4f06-957e-c584fdeb23d7 --scope user_impersonation
   ```

4. **Add redirect URI** (from Copilot Studio's MCP server config page):
   ```bash
   az ad app update --id <agent-app-id> --web-redirect-uris "<redirect-url-from-copilot-studio>"
   ```

5. **Update APIM JWT policy** to authorize the agent's client application ID in `bicep/mcp-api/policies/jwt-validation.xml`.

6. **Deploy the updated policy**:
   ```bash
   ./scripts/deploy-mcp-api.sh
   ```

7. **Add MCP server in Copilot Studio** (Tools → Add tool → Model Context Protocol):

   | Field | Value |
   |-------|-------|
   | Server name | `AI Lab MCP Server` |
   | Server description | `Demo MCP server with time and runtime info tools` |
   | Server URL | `https://apim-ai-lab-0115.azure-api.net/mcp/` |
   | Authentication | OAuth 2.0 → **Manual** |
   | Client ID | `<agent-app-id>` |
   | Client secret | `<agent-client-secret>` |
   | Authorization URL | `https://login.microsoftonline.com/38c1a7b0-f16b-45fd-a528-87d8720e868e/oauth2/v2.0/authorize` |
   | Token URL template | `https://login.microsoftonline.com/38c1a7b0-f16b-45fd-a528-87d8720e868e/oauth2/v2.0/token` |
   | Refresh URL | `https://login.microsoftonline.com/38c1a7b0-f16b-45fd-a528-87d8720e868e/oauth2/v2.0/token` |
   | Scopes | `api://6cb63aba-6d0d-4f06-957e-c584fdeb23d7/user_impersonation` |

8. **Connect** — sign in when prompted. Toggle tools on and save.

9. **Test** — ask the agent "What time is it?" or "What is the container runtime info?"

## Extending with New Tools

To add tools to the MCP server:

1. Edit `mcp-server/server.py` — add a new `@mcp.tool()` decorated function
2. Rebuild the Docker image and push to ACR
3. Create a new container app revision:
   ```bash
   ./scripts/deploy-mcp-server.sh --skip-build --tag v2
   ```
4. Copilot Studio auto-discovers new tools — refresh the MCP server connection

## Related Documentation

- [Private ACA Environment](../aca/README.md) — ACA environment deployment
- [Private ACR](../registry/README.md) — Container registry setup
- [APIM Standard v2](../apim/README.md) — API Management integration
- [Core Infrastructure](../core-infrastructure/README.md) — VNet, DNS, VPN foundation
- [Secure MCP Servers in APIM](https://learn.microsoft.com/en-us/azure/api-management/secure-mcp-servers) — Microsoft docs
- [Expose Existing MCP Server](https://learn.microsoft.com/en-us/azure/api-management/expose-existing-mcp-server) — Microsoft docs
- [Microsoft Entra Agent ID](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id) — Agent identity overview
