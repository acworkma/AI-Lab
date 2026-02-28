#!/usr/bin/env bash

set -euo pipefail

PARAMETER_FILE="bicep/foundry/main.parameters.json"
RESOURCE_GROUP=""
ACCOUNT_NAME=""
DEPLOYMENT_NAME=""
PROMPT="Reply with: Private Foundry inference is reachable."
API_VERSION="2024-10-21"
TIMEOUT=30
ALLOW_PUBLIC_DNS=false

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

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Send a test prompt to the deployed Foundry model and print the response.

Options:
  -p, --prompt TEXT            Prompt text to send
  -g, --resource-group NAME    Foundry resource group (default from parameter file)
  -a, --account NAME           Foundry AIServices account name (auto-discover if omitted)
  -d, --deployment NAME        Model deployment name (auto-discover if omitted)
      --api-version VERSION    API version for chat completions (default: 2024-10-21)
      --timeout SECONDS        HTTP timeout in seconds (default: 30)
      --allow-public-dns       Allow non-private DNS resolution
      --parameter-file PATH    Parameter file path (default: bicep/foundry/main.parameters.json)
  -h, --help                   Show this help
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--prompt)
      PROMPT="$2"
      shift 2
      ;;
    -g|--resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    -a|--account)
      ACCOUNT_NAME="$2"
      shift 2
      ;;
    -d|--deployment)
      DEPLOYMENT_NAME="$2"
      shift 2
      ;;
    --api-version)
      API_VERSION="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --allow-public-dns)
      ALLOW_PUBLIC_DNS=true
      shift
      ;;
    --parameter-file)
      PARAMETER_FILE="$2"
      shift 2
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

command -v az >/dev/null 2>&1 || { log_error "Azure CLI not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { log_error "python3 not found"; exit 1; }

if [ -z "$RESOURCE_GROUP" ]; then
  if [ -f "$PARAMETER_FILE" ]; then
    command -v jq >/dev/null 2>&1 || { log_error "jq not found (required for --parameter-file discovery)"; exit 1; }
    RESOURCE_GROUP=$(jq -r '.parameters.foundryResourceGroupName.value // "rg-ai-foundry"' "$PARAMETER_FILE")
  else
    RESOURCE_GROUP="rg-ai-foundry"
  fi
fi

log_info "Running Foundry inference probe"
log_info "Resource group: $RESOURCE_GROUP"

ARGS=(
  "scripts/test-foundry-inference.py"
  "--resource-group" "$RESOURCE_GROUP"
  "--prompt" "$PROMPT"
  "--api-version" "$API_VERSION"
  "--timeout" "$TIMEOUT"
)

[ -n "$ACCOUNT_NAME" ] && ARGS+=("--account" "$ACCOUNT_NAME")
[ -n "$DEPLOYMENT_NAME" ] && ARGS+=("--deployment" "$DEPLOYMENT_NAME")
[ "$ALLOW_PUBLIC_DNS" = true ] && ARGS+=("--allow-public-dns")

python3 "${ARGS[@]}"

log_success "Foundry inference probe completed"
