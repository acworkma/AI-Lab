#!/usr/bin/env bash
#
# Deploy GitHub Copilot BYOK Solution
#
# This script deploys the copilot-byok solution project which:
# 1. Deploys gpt-5.1-codex-mini model to existing Foundry account
# 2. Assigns RBAC (APIM managed identity → Foundry)
# 3. Deploys APIM API, product, and subscription
# 4. Outputs subscription key and deployment URL to .env
#
# Prerequisites:
# - Core infrastructure deployed (rg-ai-core)
# - Foundry infrastructure deployed (rg-ai-foundry)
# - APIM infrastructure deployed (rg-ai-apim)
#

set -euo pipefail

# Configuration
APIM_NAME="apim-ai-lab-0115"
APIM_RG="rg-ai-apim"
FOUNDRY_RG="rg-ai-foundry"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BICEP_DIR="$REPO_ROOT/bicep/copilot-byok"
ENV_FILE="$REPO_ROOT/.env"
AUTO_APPROVE=false
WHAT_IF_ONLY=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy GitHub Copilot BYOK solution (Foundry model + APIM API).

Options:
  -a, --auto-approve    Skip confirmation prompts
  -w, --what-if         Run what-if analysis only (no deployment)
  -h, --help            Show this help message

Prerequisites:
  - Azure CLI 2.50.0+ with active login
  - jq installed
  - Foundry deployed (rg-ai-foundry)
  - APIM deployed (rg-ai-apim)
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--auto-approve) AUTO_APPROVE=true; shift ;;
        -w|--what-if) WHAT_IF_ONLY=true; shift ;;
        -h|--help) usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

# ─── Prerequisites ──────────────────────────────────────────────────────────

log_info "Checking prerequisites..."

command -v az >/dev/null 2>&1 || { log_error "Azure CLI not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq not found"; exit 1; }

az account show >/dev/null 2>&1 || { log_error "Not logged in to Azure CLI. Run: az login"; exit 1; }
log_success "Azure CLI authenticated"

# Validate bicep files exist
for f in "$BICEP_DIR/main.bicep" "$BICEP_DIR/foundry-model.bicep" "$BICEP_DIR/foundry-rbac.bicep" "$BICEP_DIR/policies/managed-identity-auth.xml"; do
    if [[ ! -f "$f" ]]; then
        log_error "Required file not found: $f"
        exit 1
    fi
done
log_success "All Bicep templates found"

# Validate infrastructure prerequisites
if ! az group show --name "$FOUNDRY_RG" &>/dev/null; then
    log_error "Foundry resource group not found: $FOUNDRY_RG. Deploy Foundry infrastructure first."
    exit 1
fi
log_success "Foundry resource group exists: $FOUNDRY_RG"

if ! az group show --name "$APIM_RG" &>/dev/null; then
    log_error "APIM resource group not found: $APIM_RG. Deploy APIM infrastructure first."
    exit 1
fi
log_success "APIM resource group exists: $APIM_RG"

# Discover Foundry account name
FOUNDRY_ACCOUNT=$(az cognitiveservices account list \
    --resource-group "$FOUNDRY_RG" \
    --query "[0].name" -o tsv 2>/dev/null)

if [[ -z "$FOUNDRY_ACCOUNT" ]]; then
    log_error "No Foundry account found in $FOUNDRY_RG"
    exit 1
fi
log_success "Foundry account discovered: $FOUNDRY_ACCOUNT"

# Get Foundry endpoint
FOUNDRY_ENDPOINT=$(az cognitiveservices account show \
    --name "$FOUNDRY_ACCOUNT" \
    --resource-group "$FOUNDRY_RG" \
    --query "properties.endpoint" -o tsv)
log_info "Foundry endpoint: $FOUNDRY_ENDPOINT"

# Get APIM managed identity principal ID
APIM_PRINCIPAL_ID=$(az apim show \
    --name "$APIM_NAME" \
    --resource-group "$APIM_RG" \
    --query "identity.principalId" -o tsv 2>/dev/null)

if [[ -z "$APIM_PRINCIPAL_ID" ]]; then
    log_error "Could not retrieve APIM managed identity. Is APIM deployed with system-assigned identity?"
    exit 1
fi
log_success "APIM managed identity: $APIM_PRINCIPAL_ID"

echo ""
echo "=== GitHub Copilot BYOK Deployment ==="
echo "  Foundry Account:  $FOUNDRY_ACCOUNT"
echo "  Foundry Endpoint: $FOUNDRY_ENDPOINT"
echo "  APIM Instance:    $APIM_NAME"
echo "  APIM Principal:   $APIM_PRINCIPAL_ID"
echo ""

# ─── Step 1: Deploy Foundry Model ───────────────────────────────────────────

log_info "[1/4] Deploying gpt-5.1-codex-mini model to Foundry..."

if [[ "$WHAT_IF_ONLY" == true ]]; then
    az deployment group what-if \
        --resource-group "$FOUNDRY_RG" \
        --template-file "$BICEP_DIR/foundry-model.bicep" \
        --parameters foundryAccountName="$FOUNDRY_ACCOUNT"
else
    az deployment group create \
        --resource-group "$FOUNDRY_RG" \
        --template-file "$BICEP_DIR/foundry-model.bicep" \
        --parameters foundryAccountName="$FOUNDRY_ACCOUNT" \
        --name "copilot-byok-model-$(date +%Y%m%d-%H%M%S)" \
        --output table
    log_success "Codex model deployed"
fi

# ─── Step 2: Assign RBAC ────────────────────────────────────────────────────

log_info "[2/4] Assigning RBAC: APIM → Foundry (Cognitive Services OpenAI User)..."

if [[ "$WHAT_IF_ONLY" == true ]]; then
    az deployment group what-if \
        --resource-group "$FOUNDRY_RG" \
        --template-file "$BICEP_DIR/foundry-rbac.bicep" \
        --parameters foundryAccountName="$FOUNDRY_ACCOUNT" \
              apimPrincipalId="$APIM_PRINCIPAL_ID"
else
    az deployment group create \
        --resource-group "$FOUNDRY_RG" \
        --template-file "$BICEP_DIR/foundry-rbac.bicep" \
        --parameters foundryAccountName="$FOUNDRY_ACCOUNT" \
              apimPrincipalId="$APIM_PRINCIPAL_ID" \
        --name "copilot-byok-rbac-$(date +%Y%m%d-%H%M%S)" \
        --output table
    log_success "RBAC assignment complete"
fi

# ─── Step 3: Deploy APIM Resources ──────────────────────────────────────────

log_info "[3/4] Deploying APIM API, product, and subscription..."

if [[ "$WHAT_IF_ONLY" == true ]]; then
    az deployment group what-if \
        --resource-group "$APIM_RG" \
        --template-file "$BICEP_DIR/main.bicep" \
        --parameters apimName="$APIM_NAME" \
              foundryEndpointUrl="$FOUNDRY_ENDPOINT"
    echo ""
    log_info "What-if analysis complete. No resources were deployed."
    exit 0
fi

if [[ "$AUTO_APPROVE" == false ]]; then
    echo ""
    read -p "Continue with APIM deployment? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Deployment cancelled by user"
        exit 0
    fi
fi

az deployment group create \
    --resource-group "$APIM_RG" \
    --template-file "$BICEP_DIR/main.bicep" \
    --parameters apimName="$APIM_NAME" \
          foundryEndpointUrl="$FOUNDRY_ENDPOINT" \
    --name "copilot-byok-apim-$(date +%Y%m%d-%H%M%S)" \
    --output table
log_success "APIM resources deployed"

# ─── Step 4: Extract Subscription Key & Write .env ───────────────────────────

log_info "[4/4] Extracting subscription key and writing .env..."

SUBSCRIPTION_KEY=$(az rest \
    --method post \
    --uri "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$APIM_RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/github-copilot-byok/listSecrets?api-version=2023-09-01-preview" \
    --query "primaryKey" -o tsv 2>/dev/null)

GATEWAY_URL=$(az apim show \
    --name "$APIM_NAME" \
    --resource-group "$APIM_RG" \
    --query "gatewayUrl" -o tsv)

# Write .env file (gitignored)
cat > "$ENV_FILE" << EOF
# GitHub Copilot BYOK — Auto-generated by deploy-copilot-byok.sh
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
#
# IMPORTANT: This file is gitignored. Do NOT commit to source control.

APIM_SUBSCRIPTION_KEY=$SUBSCRIPTION_KEY
APIM_GATEWAY_URL=$(echo "$GATEWAY_URL" | sed 's|https://||')
FOUNDRY_DEPLOYMENT_NAME=gpt-5.1-codex-mini
EOF

log_success ".env file written to $ENV_FILE"

# ─── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "GitHub Enterprise Configuration:"
echo "  Provider:       Microsoft Foundry"
echo "  Deployment URL: ${GATEWAY_URL}/openai/deployments"
echo "  API Key:        (stored in .env — run 'source .env && echo \$APIM_SUBSCRIPTION_KEY')"
echo "  Model ID:       gpt-5.1-codex-mini"
echo ""
echo "Test with:"
echo "  source .env"
echo "  curl -X POST \\"
echo "    -H \"api-key: \$APIM_SUBSCRIPTION_KEY\" \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}' \\"
echo "    \"https://\$APIM_GATEWAY_URL/openai/deployments/gpt-5.1-codex-mini/chat/completions?api-version=2024-10-21\""
echo ""
echo "Validate with:"
echo "  ./scripts/validate-copilot-byok.sh"
