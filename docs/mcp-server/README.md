# MCP Server on Azure Container Apps

Deploy a demo MCP (Model Context Protocol) server as a container app in the private Azure Container Apps environment. The server exposes tools over streamable HTTP (SSE) transport, accessible only via VPN.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  rg-ai-aca                                                   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ ACA Environment (cae-ai-lab)                         │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │ Container App: mcp-server                     │   │   │
│  │  │  • Image: <acr>.azurecr.io/mcp-server:v1    │   │   │
│  │  │  • Port: 3333 (streamable HTTP/SSE)          │   │   │
│  │  │  • Ingress: internal-only                    │   │   │
│  │  │  • Identity: system-assigned (AcrPull)       │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  │  VNet-injected (10.1.2.0/23) | Internal ingress    │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  Private Endpoint → privatelink.azurecontainerapps.io       │
└──────────────────────────────────────────────────────────────┘
         ▲                              ▲
         │ VPN                          │ AcrPull (managed identity)
         │                              │
    ┌────┴────┐                   ┌─────┴─────┐
    │ Client  │                   │ rg-ai-acr │
    │ (VPN)   │                   │ Private   │
    └─────────┘                   │ ACR       │
                                  └───────────┘
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
| VPN Connection | Required for ACR build, deployment, and validation |
| Azure CLI | ≥2.50 with `containerapp` extension |
| jq | For JSON parsing in scripts |

## Quick Start

### 1. Deploy

```bash
# Build image and deploy container app (interactive)
./scripts/deploy-mcp-server.sh

# Automated deployment (CI/CD)
./scripts/deploy-mcp-server.sh --auto-approve

# Deploy with custom image tag
./scripts/deploy-mcp-server.sh --tag v2

# Redeploy existing image (skip build)
./scripts/deploy-mcp-server.sh --skip-build
```

### 2. Validate

```bash
# Infrastructure validation
./scripts/validate-mcp-server.sh

# Functional test (MCP tool invocations)
python3 scripts/test-mcp-server.py

# Functional test with explicit endpoint
python3 scripts/test-mcp-server.py --endpoint https://mcp-server.<aca-domain>
```

### 3. Cleanup

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
├── bicep/modules/
│   └── container-app.bicep              # Reusable container app module
├── scripts/
│   ├── deploy-mcp-server.sh             # Build + deploy orchestration
│   ├── validate-mcp-server.sh           # Infrastructure validation
│   ├── test-mcp-server.py               # Functional validation (Python)
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
| Ingress | Internal only |
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
| Ingress config | Internal-only, port 3333 |
| Managed identity | System-assigned enabled |
| AcrPull role | Role assigned on ACR |
| DNS resolution | Resolves to private IP (VPN required) |
| Active revision | Latest revision is running |

### Functional (`test-mcp-server.py`)

| Test | Validates |
|------|-----------|
| MCP handshake | Initialize + initialized notification |
| get_current_time | Returns valid ISO 8601 timestamp |
| get_runtime_info | Returns hostname + version "1.0.0" |

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

## Next Steps (Future Phases)

1. **APIM Integration** — Expose the MCP server through Azure API Management for external access
2. **Copilot Studio** — Connect Copilot Studio to the APIM endpoint for AI agent tool use
3. **Authentication** — Add OAuth/JWT validation to the MCP server
4. **Additional Tools** — Extend with Azure resource query tools, data lookup tools, etc.

## Related Documentation

- [Private ACA Environment](../aca/README.md) — ACA environment deployment
- [Private ACR](../registry/README.md) — Container registry setup
- [APIM Standard v2](../apim/README.md) — API Management (future integration)
- [Core Infrastructure](../core-infrastructure/README.md) — VNet, DNS, VPN foundation
