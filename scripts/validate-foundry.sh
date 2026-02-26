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
PROJECT_CAPHOST_NAME=$(jq -r '.parameters.projectCapHostName.value // "caphostproj"' "$PARAMETER_FILE")

log_info "Validating Foundry Phase 2 resources"

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

FOUNDRY_ACCOUNT=$(az cognitiveservices account list -g "$FOUNDRY_RG" --query "[?kind=='AIServices'] | [0].name" -o tsv)
if [ -z "$FOUNDRY_ACCOUNT" ] || [ "$FOUNDRY_ACCOUNT" = "null" ]; then
  log_error "No Foundry AIServices account found in $FOUNDRY_RG"
  exit 1
fi
log_success "Foundry account found: $FOUNDRY_ACCOUNT"

FOUNDRY_PROJECT=$(az resource list -g "$FOUNDRY_RG" --resource-type "Microsoft.CognitiveServices/accounts/projects" --query "[0].name" -o tsv)
if [ -z "$FOUNDRY_PROJECT" ] || [ "$FOUNDRY_PROJECT" = "null" ]; then
  log_warning "No Foundry project resource found yet (this can occur if project creation is still propagating)"
else
  log_success "Foundry project found: $FOUNDRY_PROJECT"

  CAPHOST_EXISTS=$(az resource show \
    --ids "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${FOUNDRY_RG}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT}/projects/${FOUNDRY_PROJECT}/capabilityHosts/${PROJECT_CAPHOST_NAME}" \
    --api-version 2025-04-01-preview \
    --query name -o tsv 2>/dev/null || true)
  if [ -n "$CAPHOST_EXISTS" ]; then
    log_success "Project capability host found: $PROJECT_CAPHOST_NAME"
  else
    log_warning "Project capability host not found yet: $PROJECT_CAPHOST_NAME"
  fi
fi

SEARCH_NAME=$(az search service list -g "$FOUNDRY_RG" --query "[0].name" -o tsv)
STORAGE_NAME=$(az storage account list -g "$FOUNDRY_RG" --query "[0].name" -o tsv)
COSMOS_NAME=$(az cosmosdb list -g "$FOUNDRY_RG" --query "[0].name" -o tsv)

[ -n "$SEARCH_NAME" ] || { log_error "AI Search not found in $FOUNDRY_RG"; exit 1; }
[ -n "$STORAGE_NAME" ] || { log_error "Storage account not found in $FOUNDRY_RG"; exit 1; }
[ -n "$COSMOS_NAME" ] || { log_error "Cosmos DB account not found in $FOUNDRY_RG"; exit 1; }

log_success "AI Search found: $SEARCH_NAME"
log_success "Storage account found: $STORAGE_NAME"
log_success "Cosmos DB account found: $COSMOS_NAME"

ACCOUNT_PNA=$(az cognitiveservices account show -g "$FOUNDRY_RG" -n "$FOUNDRY_ACCOUNT" --query "properties.publicNetworkAccess" -o tsv)
SEARCH_PNA=$(az search service show -g "$FOUNDRY_RG" -n "$SEARCH_NAME" --query "publicNetworkAccess" -o tsv)
STORAGE_PNA=$(az storage account show -g "$FOUNDRY_RG" -n "$STORAGE_NAME" --query "publicNetworkAccess" -o tsv)
COSMOS_PNA=$(az cosmosdb show -g "$FOUNDRY_RG" -n "$COSMOS_NAME" --query "publicNetworkAccess" -o tsv)

[[ "$ACCOUNT_PNA" =~ [Dd]isabled ]] || { log_error "Foundry account public network access is not Disabled"; exit 1; }
[[ "$SEARCH_PNA" =~ [Dd]isabled ]] || { log_error "AI Search public network access is not Disabled"; exit 1; }
[[ "$STORAGE_PNA" =~ [Dd]isabled ]] || { log_error "Storage public network access is not Disabled"; exit 1; }
[[ "$COSMOS_PNA" =~ [Dd]isabled ]] || { log_error "Cosmos DB public network access is not Disabled"; exit 1; }

log_success "Public network access disabled across Foundry, Search, Storage, and Cosmos"

PE_COUNT=$(az network private-endpoint list -g "$FOUNDRY_RG" --query "length([])" -o tsv)
if [ "$PE_COUNT" -lt 4 ]; then
  log_error "Expected at least 4 private endpoints, found $PE_COUNT"
  exit 1
fi
log_success "Private endpoints found: $PE_COUNT"

log_success "Foundry Phase 2 validation completed"
