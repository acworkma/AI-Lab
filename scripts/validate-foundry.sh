#!/usr/bin/env bash

set -euo pipefail

PARAMETER_FILE="bicep/foundry/main.parameters.json"

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
Usage: $0 [--parameter-file <path>]
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--parameter-file)
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
command -v jq >/dev/null 2>&1 || { log_error "jq not found"; exit 1; }
[ -f "$PARAMETER_FILE" ] || { log_error "Parameter file not found: $PARAMETER_FILE"; exit 1; }

FOUNDRY_RG=$(jq -r '.parameters.foundryResourceGroupName.value' "$PARAMETER_FILE")
CORE_RG=$(jq -r '.parameters.coreResourceGroupName.value' "$PARAMETER_FILE")
VNET_NAME=$(jq -r '.parameters.sharedVnetName.value' "$PARAMETER_FILE")
AGENT_SUBNET=$(jq -r '.parameters.agentSubnetName.value' "$PARAMETER_FILE")
PE_SUBNET=$(jq -r '.parameters.privateEndpointSubnetName.value' "$PARAMETER_FILE")

log_info "Validating Foundry baseline resources"

az group show --name "$FOUNDRY_RG" >/dev/null
log_success "Resource group exists: $FOUNDRY_RG"

az network vnet show -g "$CORE_RG" -n "$VNET_NAME" >/dev/null
log_success "Shared VNet exists: $VNET_NAME"

DELEGATION=$(az network vnet subnet show \
  -g "$CORE_RG" \
  --vnet-name "$VNET_NAME" \
  -n "$AGENT_SUBNET" \
  --query "delegations[0].serviceName" -o tsv)

if [ "$DELEGATION" != "Microsoft.App/environments" ]; then
  log_error "Agent subnet delegation is not Microsoft.App/environments"
  exit 1
fi
log_success "Agent subnet delegation verified: Microsoft.App/environments"

PENP=$(az network vnet subnet show \
  -g "$CORE_RG" \
  --vnet-name "$VNET_NAME" \
  -n "$PE_SUBNET" \
  --query "privateEndpointNetworkPolicies" -o tsv)

if [ "$PENP" != "Disabled" ]; then
  log_error "Private endpoint subnet network policies should be Disabled"
  exit 1
fi
log_success "Private endpoint subnet policy verified: Disabled"

zones=(
  "privatelink.services.ai.azure.com"
  "privatelink.openai.azure.com"
  "privatelink.cognitiveservices.azure.com"
  "privatelink.search.windows.net"
  "privatelink.documents.azure.com"
  "privatelink.blob.core.windows.net"
  "privatelink.file.core.windows.net"
)

for zone in "${zones[@]}"; do
  if az network private-dns zone show -g "$CORE_RG" -n "$zone" >/dev/null 2>&1; then
    log_success "DNS zone found: $zone"
  else
    log_warning "DNS zone missing in core RG: $zone"
  fi
done

log_success "Foundry baseline validation completed"
