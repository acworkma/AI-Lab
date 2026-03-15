# Feature Specification: MCP Server on Azure Container Apps

**Feature Branch**: `013-mcp-server`  
**Created**: 2026-03-15  
**Status**: Implementing  
**Input**: Deploy a demo MCP server (Python/FastMCP) with streamable HTTP transport into the private ACA environment, using the private ACR for image hosting, with Python-based functional validation.

## Background

This specification creates a demo MCP (Model Context Protocol) server deployed as a container app in the existing private Azure Container Apps environment. The server exposes two tools (`get_current_time` and `get_runtime_info`) over streamable HTTP (SSE) transport on port 3333. This is the first phase of a larger pipeline: MCP Server → ACA → APIM → Copilot Studio.

This enables:
1. **MCP server hosting** — Run a FastMCP server as a containerized app in ACA
2. **Private-only access** — Server accessible only via VPN through the private ACA environment
3. **ACR integration** — Container image built and stored in the private ACR via `az acr build`
4. **Foundation for APIM integration** — Streamable HTTP transport is compatible with APIM proxying

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Build and Push MCP Server Image (Priority: P1)

As a developer, I need to build the MCP server container image and push it to the private ACR so that it can be deployed to the ACA environment.

**Why this priority**: Without a container image in ACR, no container app can be deployed. This is the foundation.

**Independent Test**: Run `az acr build` against the private ACR and verify the image appears in the repository list.

**Acceptance Scenarios**:

1. **Given** the MCP server source code and Dockerfile exist, **When** running `az acr build`, **Then** the image is built and stored in the private ACR
2. **Given** the image exists in ACR, **When** listing repositories, **Then** `mcp-server` appears with the correct tag
3. **Given** the Dockerfile uses a non-root user, **When** inspecting the image, **Then** the container runs as non-root

---

### User Story 2 — Deploy MCP Server to ACA (Priority: P1)

As a developer, I need to deploy the MCP server container app into the existing ACA environment with internal ingress on port 3333, so that the server is accessible within the private network.

**Why this priority**: The deployed container app is the core deliverable of this feature.

**Independent Test**: Run the deploy script and verify the container app is running in the ACA environment with correct ingress configuration.

**Acceptance Scenarios**:

1. **Given** the ACA environment exists and the image is in ACR, **When** deploying the container app, **Then** the app is created in `rg-ai-aca` with status Running
2. **Given** the app is deployed, **When** checking ingress, **Then** ingress is internal-only on port 3333
3. **Given** the app is deployed, **When** checking identity, **Then** system-assigned managed identity has AcrPull role on ACR
4. **Given** the app is deployed, **When** resolving the app FQDN, **Then** DNS returns a private IP address (10.x.x.x)

---

### User Story 3 — Validate MCP Server Functionality (Priority: P2)

As a developer, I need to validate the MCP server responds to tool invocations so that I can confirm the server is operational.

**Why this priority**: Functional validation proves the server is actually working, not just deployed.

**Independent Test**: Run the Python test script over VPN and verify both MCP tools respond correctly.

**Acceptance Scenarios**:

1. **Given** the MCP server is deployed and VPN is connected, **When** calling the MCP endpoint, **Then** the server responds
2. **Given** the server is responding, **When** invoking `get_current_time`, **Then** a valid ISO 8601 timestamp is returned
3. **Given** the server is responding, **When** invoking `get_runtime_info`, **Then** hostname and version fields are present
4. **Given** the server endpoint, **When** attempting access from public internet, **Then** connection fails

---

### Edge Cases

- **ACR not deployed**: Deploy script checks ACR exists before attempting image build
- **ACA environment not deployed**: Deploy script checks ACA environment exists before creating container app
- **VPN not connected**: Validation script warns if DNS resolves to public IP or fails
- **Image build failure**: Deploy script checks `az acr build` exit code and reports errors
- **Port conflicts**: ACA ingress configured specifically for port 3333; no conflicts with environment-level ports
- **Container startup failure**: Deploy script waits for Running state and reports provisioning errors
- **Identity propagation delay**: AcrPull role assignment may take 1-2 minutes to propagate; deploy script includes wait

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
         │ VPN                          │ ACR Pull (managed identity)
         │                              │
    ┌────┴────┐                   ┌─────┴─────┐
    │ Client  │                   │ rg-ai-acr │
    │ (VPN)   │                   │ Private   │
    └─────────┘                   │ ACR       │
                                  └───────────┘
```

## Dependencies

| Dependency | Resource Group | Required |
|-----------|---------------|----------|
| Core Infrastructure (VNet, DNS) | rg-ai-core | Yes |
| ACA Environment | rg-ai-aca | Yes |
| Private ACR | rg-ai-acr | Yes |
| VPN Connection | — | Yes (for validation) |

## Files

### New
- `mcp-server/server.py` — MCP server application
- `mcp-server/requirements.txt` — Python dependencies
- `mcp-server/Dockerfile` — Container image definition
- `mcp-server/.dockerignore` — Build context exclusions
- `bicep/modules/container-app.bicep` — Reusable container app module
- `scripts/deploy-mcp-server.sh` — Build + deploy orchestration
- `scripts/validate-mcp-server.sh` — Infrastructure validation
- `scripts/test-mcp-server.py` — Functional validation (Python)
- `scripts/cleanup-mcp-server.sh` — Container app cleanup
- `docs/mcp-server/README.md` — Documentation

### Modified
- `README.md` — Add MCP server to project listing
