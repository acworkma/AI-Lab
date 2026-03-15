---

description: "Task list for MCP Server on Azure Container Apps"
---

# Tasks: 013-mcp-server

**Input**: Design documents from `/specs/013-mcp-server/`
**Prerequisites**: plan.md (required), spec.md (user stories)

**Tests**: Python functional test script (test-mcp-server.py) validates MCP tool responses.

**Organization**: Tasks grouped by phase to enable systematic implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase A: Application Code

**Purpose**: Create the MCP server application and container image definition

- [x] T001 [P] [US1] Create `mcp-server/server.py` with FastMCP server, `get_current_time` and `get_runtime_info` tools, streamable HTTP transport on port 3333
- [x] T002 [P] [US1] Create `mcp-server/requirements.txt` pinning `mcp[cli]>=1.0`
- [x] T003 [P] [US1] Create `mcp-server/Dockerfile` with Python 3.12-slim, non-root user, EXPOSE 3333, health check
- [x] T004 [P] [US1] Create `mcp-server/.dockerignore` to exclude non-essential files from build context

---

## Phase B: Infrastructure

**Purpose**: Reusable Bicep module and deployment orchestration

- [x] T005 [US2] Create `bicep/modules/container-app.bicep` — reusable module for deploying container apps to ACA environment with managed identity, ACR pull, internal ingress, health probes
- [x] T006 [US2] Create `scripts/deploy-mcp-server.sh` — orchestration: prerequisites → build image → deploy container app → assign identity → validate

---

## Phase C: Validation & Operations

**Purpose**: Infrastructure validation, functional testing, and cleanup

- [x] T007 [P] [US3] Create `scripts/validate-mcp-server.sh` — checks: app exists, running state, ingress config, DNS resolution, identity
- [x] T008 [P] [US3] Create `scripts/test-mcp-server.py` — Python functional test: call MCP tools via HTTP, validate responses
- [x] T009 [P] [US2] Create `scripts/cleanup-mcp-server.sh` — delete container app only (preserves ACA environment)

---

## Phase D: Documentation

**Purpose**: Complete project documentation

- [x] T010 [P] [US3] Create `docs/mcp-server/README.md` with architecture, deployment, validation, next steps
- [x] T011 [US3] Update root `README.md` with MCP server entry in solution projects
- [x] T012 [P] Create `specs/013-mcp-server/spec.md` with feature specification
- [x] T013 [P] Create `specs/013-mcp-server/plan.md` with implementation plan
- [x] T014 [P] Create `specs/013-mcp-server/tasks.md` (this file)

---

## Phase E: Validation

**Purpose**: Verify all files are syntactically correct

- [ ] T015 Run `az bicep build` on `bicep/modules/container-app.bicep` to validate syntax
- [ ] T016 Verify Dockerfile builds locally or describe expected `az acr build` command
- [ ] T017 Run shellcheck on all new scripts (if available)
- [ ] T018 Make all scripts executable (chmod +x)
