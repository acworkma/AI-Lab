#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FOUNDRY_RG="rg-ai-foundry"
CORE_RG="rg-ai-core"
VNET_NAME="vnet-ai-shared"
AGENT_SUBNET="snet-foundry-agent"

SUBSCRIPTION_ID=""
LOCATION="eastus2"
ACCOUNT_NAME=""
PROJECT_NAME=""
PROJECT_CAPHOST_NAME=""
ACCOUNT_CAPHOST_NAME=""
DELETE_NETWORK=false
FORCE=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
  cat << EOF
Usage: $0 --subscription-id <id> --account-name <name> --project-caphost-name <name> --account-caphost-name <name> [options]

Options:
  --foundry-rg <name>        Foundry resource group (default: rg-ai-foundry)
  --core-rg <name>           Core resource group (default: rg-ai-core)
  --vnet-name <name>         Shared VNet name (default: vnet-ai-shared)
  --agent-subnet <name>      Foundry agent subnet name (default: snet-foundry-agent)
  --location <azure-region>  Region for account purge (default: eastus2)
  --delete-network           Delete Foundry agent subnet after account purge and unlink
  --force                    Skip confirmation prompt
  -h, --help                 Show help
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription-id)
      SUBSCRIPTION_ID="$2"
      shift 2
      ;;
    --account-name)
      ACCOUNT_NAME="$2"
      shift 2
      ;;
    --project-caphost-name)
      PROJECT_CAPHOST_NAME="$2"
      shift 2
      ;;
    --account-caphost-name)
      ACCOUNT_CAPHOST_NAME="$2"
      shift 2
      ;;
    --foundry-rg)
      FOUNDRY_RG="$2"
      shift 2
      ;;
    --core-rg)
      CORE_RG="$2"
      shift 2
      ;;
    --vnet-name)
      VNET_NAME="$2"
      shift 2
      ;;
    --agent-subnet)
      AGENT_SUBNET="$2"
      shift 2
      ;;
    --location)
      LOCATION="$2"
      shift 2
      ;;
    --delete-network)
      DELETE_NETWORK=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
done

[ -n "$SUBSCRIPTION_ID" ] || usage
[ -n "$ACCOUNT_NAME" ] || usage
[ -n "$PROJECT_CAPHOST_NAME" ] || usage
[ -n "$ACCOUNT_CAPHOST_NAME" ] || usage

command -v az >/dev/null 2>&1 || { log_error "Azure CLI not found"; exit 1; }

PROJECT_FULL_NAME=$(az resource list \
  -g "$FOUNDRY_RG" \
  --resource-type "Microsoft.CognitiveServices/accounts/projects" \
  --query "[0].name" -o tsv 2>/dev/null || true)

if [[ "$PROJECT_FULL_NAME" == */* ]]; then
  PROJECT_NAME="${PROJECT_FULL_NAME#*/}"
else
  PROJECT_NAME="$PROJECT_FULL_NAME"
fi

[ -n "$PROJECT_NAME" ] || { log_error "Could not discover Foundry project name in $FOUNDRY_RG"; exit 1; }

if [ "$FORCE" != true ]; then
  log_warning "This will delete and purge Foundry account resources."
  log_warning "Cleanup order is strict: project caphost -> account caphost -> account delete/purge -> optional subnet delete"
  read -p "Type 'yes' to continue: " -r
  if [ "$REPLY" != "yes" ]; then
    log_info "Cleanup cancelled"
    exit 0
  fi
fi

log_info "Step 1/6: Delete project capability host first"
"${SCRIPT_DIR}/delete-foundry-caphost.sh" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --resource-group "$FOUNDRY_RG" \
  --account-name "$ACCOUNT_NAME" \
  --project-name "$PROJECT_NAME" \
  --caphost-name "$PROJECT_CAPHOST_NAME"

log_info "Step 2/6: Delete account capability host"
"${SCRIPT_DIR}/delete-foundry-caphost.sh" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --resource-group "$FOUNDRY_RG" \
  --account-name "$ACCOUNT_NAME" \
  --caphost-name "$ACCOUNT_CAPHOST_NAME"

log_info "Step 3/6: Delete Foundry account"
az cognitiveservices account delete \
  --name "$ACCOUNT_NAME" \
  --resource-group "$FOUNDRY_RG" \
  --yes >/dev/null

log_info "Step 4/6: Purge Foundry account (required for complete unlink)"
az cognitiveservices account purge \
  --name "$ACCOUNT_NAME" \
  --resource-group "$FOUNDRY_RG" \
  --location "$LOCATION" >/dev/null

log_info "Step 5/6: Wait for service unlink to complete (up to 20 minutes)"
max_wait=1200
interval=30
elapsed=0

while [ "$elapsed" -lt "$max_wait" ]; do
  sal_count=$(az network vnet subnet show \
    -g "$CORE_RG" \
    --vnet-name "$VNET_NAME" \
    -n "$AGENT_SUBNET" \
    --query "length(serviceAssociationLinks)" -o tsv 2>/dev/null || echo "0")

  if [ "$sal_count" = "0" ]; then
    log_success "Agent subnet service association links cleared"
    break
  fi

  log_info "Service associations still present (${sal_count}). Waiting ${interval}s..."
  sleep "$interval"
  elapsed=$((elapsed + interval))
done

if [ "$elapsed" -ge "$max_wait" ]; then
  log_warning "Timed out waiting for full unlink. Continue cautiously."
fi

log_info "Step 6/6: Delete Foundry resource group"
if az group show --name "$FOUNDRY_RG" >/dev/null 2>&1; then
  az group delete --name "$FOUNDRY_RG" --yes --no-wait >/dev/null
  log_success "Foundry resource group deletion started"
else
  log_warning "Foundry resource group not found: $FOUNDRY_RG"
fi

if [ "$DELETE_NETWORK" = true ]; then
  log_info "Deleting Foundry agent subnet from shared VNet"
  az network vnet subnet delete -g "$CORE_RG" --vnet-name "$VNET_NAME" -n "$AGENT_SUBNET" >/dev/null || true
  log_success "Foundry agent subnet deletion requested"
else
  log_info "Network deletion skipped. Re-run with --delete-network to remove agent subnet."
fi

log_success "Foundry cleanup flow completed"
