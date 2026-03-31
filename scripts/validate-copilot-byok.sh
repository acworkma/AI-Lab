#!/usr/bin/env bash
#
# Validate GitHub Copilot BYOK Deployment
#
# Checks:
# 1. Codex model deployed in Foundry
# 2. RBAC assignment (APIM → Foundry)
# 3. APIM API, product, and subscription exist
# 4. End-to-end chat/completions test (if .env exists)
# 5. Rate limiting verification (optional)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

APIM_NAME="apim-ai-lab-0115"
APIM_RG="rg-ai-apim"
FOUNDRY_RG="rg-ai-foundry"
STRICT=false
RUN_E2E=false
VALIDATION_PASSED=true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; if [[ "$STRICT" == true ]]; then VALIDATION_PASSED=false; fi; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; VALIDATION_PASSED=false; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate GitHub Copilot BYOK deployment.

Options:
  --e2e               Run end-to-end API test (requires .env with subscription key)
  --strict            Treat warnings as failures
  -h, --help          Show this help message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --e2e) RUN_E2E=true; shift ;;
        --strict) STRICT=true; shift ;;
        -h|--help) usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

command -v az >/dev/null 2>&1 || { log_error "Azure CLI not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq not found"; exit 1; }

echo "=== Validate GitHub Copilot BYOK ==="
echo ""

# ─── 1. Foundry Model ───────────────────────────────────────────────────────

log_info "Checking Foundry model deployment..."

FOUNDRY_ACCOUNT=$(az cognitiveservices account list \
    --resource-group "$FOUNDRY_RG" \
    --query "[0].name" -o tsv 2>/dev/null)

if [[ -z "$FOUNDRY_ACCOUNT" ]]; then
    log_error "No Foundry account found in $FOUNDRY_RG"
else
    log_success "Foundry account: $FOUNDRY_ACCOUNT"

    # Check codex model exists
    CODEX_MODEL=$(az cognitiveservices account deployment list \
        --name "$FOUNDRY_ACCOUNT" \
        --resource-group "$FOUNDRY_RG" \
        --query "[?name=='gpt-5.1-codex-mini'].name" -o tsv 2>/dev/null)

    if [[ "$CODEX_MODEL" == "gpt-5.1-codex-mini" ]]; then
        log_success "Codex model deployed: gpt-5.1-codex-mini"
    else
        log_error "Codex model NOT found: gpt-5.1-codex-mini"
    fi

    # Check existing model still intact
    EXISTING_MODEL=$(az cognitiveservices account deployment list \
        --name "$FOUNDRY_ACCOUNT" \
        --resource-group "$FOUNDRY_RG" \
        --query "[?name=='gpt-4.1'].name" -o tsv 2>/dev/null)

    if [[ "$EXISTING_MODEL" == "gpt-4.1" ]]; then
        log_success "Existing model intact: gpt-4.1"
    else
        log_warning "Existing model gpt-4.1 not found (may not have been deployed)"
    fi
fi

# ─── 2. RBAC Assignment ─────────────────────────────────────────────────────

log_info "Checking RBAC assignment..."

APIM_PRINCIPAL_ID=$(az apim show \
    --name "$APIM_NAME" \
    --resource-group "$APIM_RG" \
    --query "identity.principalId" -o tsv 2>/dev/null)

if [[ -n "$APIM_PRINCIPAL_ID" && -n "$FOUNDRY_ACCOUNT" ]]; then
    FOUNDRY_ID=$(az cognitiveservices account show \
        --name "$FOUNDRY_ACCOUNT" \
        --resource-group "$FOUNDRY_RG" \
        --query "id" -o tsv 2>/dev/null)

    ROLE_ASSIGNMENT=$(az role assignment list \
        --assignee "$APIM_PRINCIPAL_ID" \
        --scope "$FOUNDRY_ID" \
        --query "[?roleDefinitionName=='Cognitive Services OpenAI User'].id" -o tsv 2>/dev/null)

    if [[ -n "$ROLE_ASSIGNMENT" ]]; then
        log_success "RBAC: Cognitive Services OpenAI User assigned to APIM identity"
    else
        log_error "RBAC: Cognitive Services OpenAI User NOT assigned to APIM identity"
    fi
else
    log_error "Cannot verify RBAC — APIM principal ID or Foundry account not found"
fi

# ─── 3. APIM Resources ──────────────────────────────────────────────────────

log_info "Checking APIM resources..."

# Check API exists
API_EXISTS=$(az apim api show \
    --resource-group "$APIM_RG" \
    --service-name "$APIM_NAME" \
    --api-id "copilot-byok-api" \
    --query "name" -o tsv 2>/dev/null || echo "")

if [[ "$API_EXISTS" == "copilot-byok-api" ]]; then
    log_success "APIM API exists: copilot-byok-api"
else
    log_error "APIM API NOT found: copilot-byok-api"
fi

# Check product exists
PRODUCT_EXISTS=$(az apim product show \
    --resource-group "$APIM_RG" \
    --service-name "$APIM_NAME" \
    --product-id "github-copilot" \
    --query "name" -o tsv 2>/dev/null || echo "")

if [[ "$PRODUCT_EXISTS" == "github-copilot" ]]; then
    log_success "APIM product exists: github-copilot"
else
    log_error "APIM product NOT found: github-copilot"
fi

# Check subscription exists
SUB_EXISTS=$(az rest \
    --method get \
    --uri "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$APIM_RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/github-copilot-byok?api-version=2023-09-01-preview" \
    --query "name" -o tsv 2>/dev/null || echo "")

if [[ -n "$SUB_EXISTS" ]]; then
    log_success "APIM subscription exists: github-copilot-byok"
else
    log_error "APIM subscription NOT found: github-copilot-byok"
fi

# ─── 4. End-to-End Test ─────────────────────────────────────────────────────

if [[ "$RUN_E2E" == true ]]; then
    log_info "Running end-to-end API test..."

    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$ENV_FILE"

        if [[ -z "${APIM_SUBSCRIPTION_KEY:-}" || -z "${APIM_GATEWAY_URL:-}" ]]; then
            log_error "APIM_SUBSCRIPTION_KEY or APIM_GATEWAY_URL not set in .env"
        else
            HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                -X POST \
                -H "api-key: $APIM_SUBSCRIPTION_KEY" \
                -H "Content-Type: application/json" \
                -d '{"messages":[{"role":"user","content":"Say hello"}],"max_tokens":10}' \
                "https://$APIM_GATEWAY_URL/openai/deployments/gpt-5.1-codex-mini/chat/completions?api-version=2024-10-21" \
                --max-time 30 2>/dev/null || echo "000")

            if [[ "$HTTP_STATUS" == "200" ]]; then
                log_success "End-to-end test passed (HTTP 200)"
            elif [[ "$HTTP_STATUS" == "000" ]]; then
                log_error "End-to-end test failed: Connection timeout or DNS resolution failure"
            else
                log_error "End-to-end test failed: HTTP $HTTP_STATUS"
            fi

            # Test without key — should be 401
            NO_KEY_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                -X POST \
                -H "Content-Type: application/json" \
                -d '{"messages":[{"role":"user","content":"Hello"}],"max_tokens":10}' \
                "https://$APIM_GATEWAY_URL/openai/deployments/gpt-5.1-codex-mini/chat/completions?api-version=2024-10-21" \
                --max-time 10 2>/dev/null || echo "000")

            if [[ "$NO_KEY_STATUS" == "401" ]]; then
                log_success "Unauthorized test passed (HTTP 401 without key)"
            else
                log_warning "Unauthorized test: expected 401, got HTTP $NO_KEY_STATUS"
            fi
        fi
    else
        log_warning "No .env file found — skipping end-to-end test. Run deploy-copilot-byok.sh first."
    fi
else
    log_info "Skipping end-to-end test (use --e2e to enable)"
fi

# ─── Summary ────────────────────────────────────────────────────────────────

echo ""
if [[ "$VALIDATION_PASSED" == true ]]; then
    echo -e "${GREEN}=== All validations passed ===${NC}"
    exit 0
else
    echo -e "${RED}=== Some validations failed ===${NC}"
    exit 1
fi
