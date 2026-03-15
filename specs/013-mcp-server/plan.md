# Implementation Plan: MCP Server on Azure Container Apps

**Branch**: `013-mcp-server` | **Date**: 2026-03-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/013-mcp-server/spec.md`

## Summary

Build a demo MCP server (Python/FastMCP) with streamable HTTP (SSE) transport, containerize it, push to private ACR via `az acr build`, deploy as a container app in the existing private ACA environment, and validate with a Python test script. This is phase 1 of the MCP Server → ACA → APIM → Copilot Studio pipeline.

## Technical Context

**Language/Version**: Python 3.12, MCP SDK (`mcp[cli]`), Bicep  
**Primary Dependencies**: Azure CLI ≥2.50, Private ACR (rg-ai-acr), ACA environment (rg-ai-aca)  
**Compute**: Azure Container Apps (Consumption workload profile)  
**Network**: Internal-only ingress via VNet-injected ACA environment  
**Testing**: Python test script (stdlib HTTP), bash validation scripts  
**Target Platform**: Azure Cloud (East US 2 region)  
**Project Type**: Solution project (application + infrastructure)  
**Transport**: Streamable HTTP (SSE) on port 3333  
**Constraints**: Internal-only access; VPN required; no public endpoints

## Architecture

### Container Image Pipeline

```
mcp-server/           →  az acr build  →  Private ACR  →  ACA Container App
├── server.py                              (rg-ai-acr)     (rg-ai-aca)
├── requirements.txt                          │
├── Dockerfile                                │ AcrPull (managed identity)
└── .dockerignore                             ▼
                                         mcp-server:v1
```

### Network Flow

```
VPN Client → vWAN Hub → Private Endpoint → ACA Environment → mcp-server:3333
                                              (internal ingress)
```

### MCP Server Tools

| Tool | Input | Output | Purpose |
|------|-------|--------|---------|
| `get_current_time` | `timezone: str` (default "UTC") | ISO 8601 timestamp string | Demo: time retrieval |
| `get_runtime_info` | — | `{hostname, version}` dict | Demo: container identity |

## Implementation Phases

### Phase A: Application Code

1. Create `mcp-server/server.py` with FastMCP server, two tools, streamable HTTP transport on port 3333
2. Create `mcp-server/requirements.txt` pinning `mcp[cli]>=1.0`
3. Create `mcp-server/Dockerfile` — Python 3.12-slim, non-root user, health check, EXPOSE 3333
4. Create `mcp-server/.dockerignore` — exclude non-essential files

### Phase B: Infrastructure

5. Create `bicep/modules/container-app.bicep` — reusable module for deploying container apps into ACA environment with managed identity, ACR pull, internal ingress, health probes
6. Create `scripts/deploy-mcp-server.sh` — orchestration: check prerequisites → build image → deploy container app → assign identity → validate

### Phase C: Validation & Ops

7. Create `scripts/validate-mcp-server.sh` — infrastructure checks (app exists, running, DNS, identity)
8. Create `scripts/test-mcp-server.py` — functional validation: call MCP tools via HTTP, validate responses
9. Create `scripts/cleanup-mcp-server.sh` — delete container app only (not ACA environment)

### Phase D: Documentation

10. Create `docs/mcp-server/README.md` — architecture, deployment, validation, next steps
11. Update `README.md` — add MCP server to solution projects listing

## Deployment Approach

**Container app via CLI** (`az containerapp create`), not Bicep, for the deploy script. Rationale:
- App deployments are frequent; infra changes are rare  
- CLI provides immediate feedback and error messages  
- Bicep module created for reuse but deploy script uses CLI for agility
- The ACA environment (Bicep-managed) is decoupled from app lifecycle

**Image build via `az acr build`** (remote build in ACR):
- No local Docker needed  
- Works over VPN connection  
- Build context is the `mcp-server/` directory

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Transport | Streamable HTTP (SSE) | Future APIM proxy compatibility |
| Port | 3333 | MCP convention; avoids 80/443 conflicts |
| Image build | `az acr build` | No local Docker; works over VPN |
| Deploy method | `az containerapp create` (CLI) | Agile app lifecycle; Bicep for infra only |
| Validation | Python (stdlib) | Consistent with test-foundry-inference.py |
| Identity | System-assigned managed identity | AcrPull role on ACR for image pulls |
| Ingress | Internal-only, port 3333 | Private network access via VPN |
| App name | `mcp-server` | Descriptive, consistent with project naming |

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| MCP SDK version incompatibility | Build failure | Pin specific version in requirements.txt |
| ACR build timeout | Deploy failure | Set --timeout flag; retry logic in script |
| Identity propagation delay | AcrPull fails on first pull | Wait 60s after role assignment before deploy |
| ACA environment not ready | App create fails | Pre-check environment state in deploy script |
| FastMCP health endpoint unknown | Probe misconfiguration | Verify health path; fall back to TCP probe |

## Future Phases (Out of Scope)

- **Phase 2**: Expose MCP server through APIM (API gateway)
- **Phase 3**: Connect Copilot Studio to APIM endpoint
- **Phase 4**: Add authentication/authorization to MCP server
- **Phase 5**: Add additional MCP tools (Azure resource queries, etc.)
