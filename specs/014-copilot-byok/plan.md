# Implementation Plan: GitHub Copilot BYOK

## Summary

Solution project that deploys a `gpt-4.1` model to the existing Foundry account and exposes it through the existing APIM gateway for GitHub Copilot Enterprise BYOK. Uses the `existing` keyword in Bicep to reference infrastructure without modifying it.

## Technical Context

- **Language/IaC**: Bicep (resource-group-scoped deployments)
- **Target RGs**: `rg-ai-foundry` (model + RBAC), `rg-ai-apim` (API + product)
- **Pattern**: Solution project — same as `bicep/storage-api/`, `bicep/mcp-api/`, `bicep/storage-cmk/`
- **Auth Flow**: GitHub → APIM (subscription key) → Foundry (managed identity token)

## Implementation Phases

### Phase 1: Foundry Model Deployment
1. Create `bicep/copilot-byok/foundry-model.bicep` — Reference existing Foundry account, add `gpt-4.1` as child deployment resource

### Phase 2: APIM API + Product
2. Create `bicep/copilot-byok/main.bicep` — Reference existing APIM, add backend + API + product + subscription
3. Create `bicep/copilot-byok/policies/managed-identity-auth.xml` — Managed identity auth + rate limiting policy

### Phase 3: RBAC
4. Create `bicep/copilot-byok/foundry-rbac.bicep` — APIM identity → Cognitive Services OpenAI User

### Phase 4: Deployment Automation
5. Create `.env.example` — Template for secrets
6. Create `scripts/deploy-copilot-byok.sh` — Multi-step deployment orchestration
7. Create `scripts/validate-copilot-byok.sh` — End-to-end validation

### Phase 5: Documentation
8. Create `docs/copilot-byok/README.md` — Full documentation
9. Update `README.md` — Add to Solution Projects table

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Solution vs Infrastructure | Solution project | Uses existing Foundry + APIM, does not modify infra modules |
| Auth inbound | APIM subscription key | GitHub BYOK sends API key — maps directly to APIM subscription key |
| Auth outbound | Managed identity | APIM → Foundry via system-assigned MI, no credentials exposed |
| Endpoint pattern | Native Foundry URL | `/openai/deployments/{id}/chat/completions` — GitHub's Microsoft Foundry provider expects this |
| Rate limiting | 60 req/min per key | Product-level policy, balances usability with cost control |
| Secrets | `.env` file | Gitignored, deploy script auto-populates, `.env.example` checked in |
| Model capacity | 30 TPM GlobalStandard | Matches existing gpt-4.1 deployment, scalable post-deployment |

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Foundry model not available in region | Blocking | Verify model availability in East US 2 before deployment |
| APIM MI cannot authenticate to Foundry | Blocking | RBAC assignment in `foundry-rbac.bicep` + validation in deploy script |
| Network routing APIM → Foundry PE | Blocking | Both services share the VNet; validate with curl from VPN |
| GitHub BYOK preview changes | Medium | Monitor GitHub docs; URL pattern is stable for Microsoft Foundry |
| Rate limit too restrictive | Low | Configurable parameter, adjustable post-deployment |
