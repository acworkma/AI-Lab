#!/usr/bin/env bash

set -euo pipefail

PARAMETER_FILE="bicep/foundry/main.parameters.json"
STRICT=false
VALIDATION_PASSED=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[✓ PASS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
  if [ "$STRICT" = true ]; then
    VALIDATION_PASSED=false
  fi
}

log_error() {
  echo -e "${RED}[✗ FAIL]${NC} $1"
  VALIDATION_PASSED=false
}

usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Operational validation for Private Foundry.

OPTIONS:
  -p, --parameter-file PATH   Path to parameter file (default: bicep/foundry/main.parameters.json)
  --strict                    Treat warnings as failures
  -h, --help                  Show this help

Checks:
  1) Account/project capability host state and connection bindings
  2) Pre-caphost RBAC assignments (Search, Storage, Cosmos account)
  3) Post-caphost RBAC assignments (Storage container role, Cosmos SQL role)
  4) Private endpoint provisioning states
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--parameter-file)
      PARAMETER_FILE="$2"
      shift 2
      ;;
    --strict)
      STRICT=true
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

command -v az >/dev/null 2>&1 || { log_error "Azure CLI not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq not found"; exit 1; }
[ -f "$PARAMETER_FILE" ] || { log_error "Parameter file not found: $PARAMETER_FILE"; exit 1; }

FOUNDRY_RG=$(jq -r '.parameters.foundryResourceGroupName.value' "$PARAMETER_FILE")
PROJECT_CAPHOST_NAME=$(jq -r '.parameters.projectCapHostName.value // "caphostproj"' "$PARAMETER_FILE")
ACCOUNT_CAPHOST_NAME=$(jq -r '.parameters.accountCapHostName.value // "caphostaccount"' "$PARAMETER_FILE")
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

log_info "Running Foundry operational validation"

FOUNDRY_ACCOUNT=$(az cognitiveservices account list -g "$FOUNDRY_RG" --query "[?kind=='AIServices'] | [0].name" -o tsv)
if [ -z "$FOUNDRY_ACCOUNT" ] || [ "$FOUNDRY_ACCOUNT" = "null" ]; then
  log_error "Foundry account not found"
  exit 1
fi
log_success "Foundry account: $FOUNDRY_ACCOUNT"

FOUNDRY_PROJECT_FULL=$(az resource list -g "$FOUNDRY_RG" --resource-type "Microsoft.CognitiveServices/accounts/projects" --query "[0].name" -o tsv)
if [ -z "$FOUNDRY_PROJECT_FULL" ] || [ "$FOUNDRY_PROJECT_FULL" = "null" ]; then
  log_error "Foundry project not found"
  exit 1
fi

if [[ "$FOUNDRY_PROJECT_FULL" == */* ]]; then
  FOUNDRY_PROJECT="${FOUNDRY_PROJECT_FULL#*/}"
else
  FOUNDRY_PROJECT="$FOUNDRY_PROJECT_FULL"
fi
log_success "Foundry project: $FOUNDRY_PROJECT"

PROJECT_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${FOUNDRY_RG}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT}/projects/${FOUNDRY_PROJECT}"
PROJECT_PRINCIPAL_ID=$(az resource show --ids "$PROJECT_RESOURCE_ID" --api-version 2025-04-01-preview --query "identity.principalId" -o tsv 2>/dev/null || echo "")
if [ -z "$PROJECT_PRINCIPAL_ID" ] || [ "$PROJECT_PRINCIPAL_ID" = "null" ]; then
  log_error "Could not resolve Foundry project principal ID"
  exit 1
fi
log_success "Project principal ID resolved"

SEARCH_NAME=$(az search service list -g "$FOUNDRY_RG" --query "[0].name" -o tsv)
STORAGE_NAME=$(az storage account list -g "$FOUNDRY_RG" --query "[0].name" -o tsv)
COSMOS_NAME=$(az cosmosdb list -g "$FOUNDRY_RG" --query "[0].name" -o tsv)

[ -n "$SEARCH_NAME" ] || { log_error "Search service not found"; exit 1; }
[ -n "$STORAGE_NAME" ] || { log_error "Storage account not found"; exit 1; }
[ -n "$COSMOS_NAME" ] || { log_error "Cosmos DB not found"; exit 1; }

SEARCH_ID=$(az search service show -g "$FOUNDRY_RG" -n "$SEARCH_NAME" --query id -o tsv)
STORAGE_ID=$(az storage account show -g "$FOUNDRY_RG" -n "$STORAGE_NAME" --query id -o tsv)
COSMOS_ID=$(az cosmosdb show -g "$FOUNDRY_RG" -n "$COSMOS_NAME" --query id -o tsv)

PROJECT_CAPHOST_URI="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${FOUNDRY_RG}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT}/projects/${FOUNDRY_PROJECT}/capabilityHosts/${PROJECT_CAPHOST_NAME}?api-version=2025-04-01-preview"

ACCOUNT_CAPHOST_LIST_URI="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${FOUNDRY_RG}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT}/capabilityHosts?api-version=2025-09-01"
ACCOUNT_CAPHOST_LIST_JSON=$(az rest --method get --url "$ACCOUNT_CAPHOST_LIST_URI" 2>/dev/null || echo "")
ACCOUNT_CAPHOST_JSON=""
ACCOUNT_CAPHOST_RESOLVED_NAME=""

if [ -n "$ACCOUNT_CAPHOST_LIST_JSON" ]; then
  ACCOUNT_CAPHOST_JSON=$(echo "$ACCOUNT_CAPHOST_LIST_JSON" | jq -c --arg name "$ACCOUNT_CAPHOST_NAME" '.value[]? | select(.name == $name)' | head -n1)
  if [ -z "$ACCOUNT_CAPHOST_JSON" ]; then
    ACCOUNT_CAPHOST_JSON=$(echo "$ACCOUNT_CAPHOST_LIST_JSON" | jq -c '.value[]? | select(.properties.provisioningState == "Succeeded")' | head -n1)
  fi
fi

if [ -z "$ACCOUNT_CAPHOST_JSON" ]; then
  log_error "Account capability host missing (configured: $ACCOUNT_CAPHOST_NAME)"
else
  ACCOUNT_CAPHOST_RESOLVED_NAME=$(echo "$ACCOUNT_CAPHOST_JSON" | jq -r '.name')
  ACCOUNT_STATE=$(echo "$ACCOUNT_CAPHOST_JSON" | jq -r '.properties.provisioningState // "Unknown"')
  if [ "$ACCOUNT_STATE" = "Succeeded" ]; then
    log_success "Account capability host state: Succeeded ($ACCOUNT_CAPHOST_RESOLVED_NAME)"
  else
    log_warning "Account capability host state: $ACCOUNT_STATE ($ACCOUNT_CAPHOST_RESOLVED_NAME)"
  fi
fi

PROJECT_CAPHOST_JSON=$(az rest --method get --url "$PROJECT_CAPHOST_URI" 2>/dev/null || echo "")
if [ -z "$PROJECT_CAPHOST_JSON" ]; then
  log_error "Project capability host missing: $PROJECT_CAPHOST_NAME"
else
  PROJECT_STATE=$(echo "$PROJECT_CAPHOST_JSON" | jq -r '.properties.provisioningState // "Unknown"')
  if [ "$PROJECT_STATE" = "Succeeded" ]; then
    log_success "Project capability host state: Succeeded"
  else
    log_warning "Project capability host state: $PROJECT_STATE"
  fi

  THREAD_CONN_COUNT=$(echo "$PROJECT_CAPHOST_JSON" | jq -r '.properties.threadStorageConnections | length // 0')
  VECTOR_CONN_COUNT=$(echo "$PROJECT_CAPHOST_JSON" | jq -r '.properties.vectorStoreConnections | length // 0')
  STORAGE_CONN_COUNT=$(echo "$PROJECT_CAPHOST_JSON" | jq -r '.properties.storageConnections | length // 0')

  [ "$THREAD_CONN_COUNT" -gt 0 ] && log_success "Thread storage connections configured" || log_error "Thread storage connections missing"
  [ "$VECTOR_CONN_COUNT" -gt 0 ] && log_success "Vector store connections configured" || log_error "Vector store connections missing"
  [ "$STORAGE_CONN_COUNT" -gt 0 ] && log_success "Storage connections configured" || log_error "Storage connections missing"
fi

has_role_assignment() {
  local scope="$1"
  local role_id="$2"
  local principal_id="$3"
  local count

  count=$(az role assignment list \
    --scope "$scope" \
    --assignee-object-id "$principal_id" \
    --query "[?roleDefinitionId=='/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/roleDefinitions/${role_id}'] | length(@)" \
    -o tsv 2>/dev/null || echo "0")

  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  [ "$count" -gt 0 ]
}

has_role_assignment "$SEARCH_ID" "8ebe5a00-799e-43f5-93ac-243d3dce84a7" "$PROJECT_PRINCIPAL_ID" \
  && log_success "Search Index Data Contributor assigned" \
  || log_error "Search Index Data Contributor missing"

has_role_assignment "$SEARCH_ID" "7ca78c08-252a-4471-8644-bb5ff32d4ba0" "$PROJECT_PRINCIPAL_ID" \
  && log_success "Search Service Contributor assigned" \
  || log_error "Search Service Contributor missing"

has_role_assignment "$STORAGE_ID" "ba92f5b4-2d11-453d-a403-e96b0029c9fe" "$PROJECT_PRINCIPAL_ID" \
  && log_success "Storage Blob Data Contributor assigned" \
  || log_error "Storage Blob Data Contributor missing"

has_role_assignment "$COSMOS_ID" "230815da-be43-4aae-9cb4-875f7bd000aa" "$PROJECT_PRINCIPAL_ID" \
  && log_success "Cosmos DB Operator role assigned" \
  || log_error "Cosmos DB Operator role missing"

has_role_assignment "$STORAGE_ID" "b7e6dc6d-f1e8-4753-8033-0f276bb0955b" "$PROJECT_PRINCIPAL_ID" \
  && log_success "Storage Blob Data Owner (container-scoped condition) assigned" \
  || log_warning "Storage Blob Data Owner assignment not detected"

COSMOS_SQL_ROLE_ASSIGN_COUNT=$(az rest --method get \
  --url "https://management.azure.com${COSMOS_ID}/sqlRoleAssignments?api-version=2022-05-15" \
  --query "value[?properties.principalId=='${PROJECT_PRINCIPAL_ID}'] | length(@)" -o tsv 2>/dev/null || echo "0")

[[ "$COSMOS_SQL_ROLE_ASSIGN_COUNT" =~ ^[0-9]+$ ]] || COSMOS_SQL_ROLE_ASSIGN_COUNT=0
if [ "$COSMOS_SQL_ROLE_ASSIGN_COUNT" -gt 0 ]; then
  log_success "Cosmos SQL role assignment found for project principal"
else
  log_warning "Cosmos SQL role assignment not detected"
fi

PE_BAD_COUNT=$(az network private-endpoint list -g "$FOUNDRY_RG" --query "[?provisioningState!='Succeeded'] | length(@)" -o tsv 2>/dev/null || echo "0")
[[ "$PE_BAD_COUNT" =~ ^[0-9]+$ ]] || PE_BAD_COUNT=0
if [ "$PE_BAD_COUNT" -eq 0 ]; then
  log_success "All private endpoints are in Succeeded state"
else
  log_warning "Some private endpoints are not in Succeeded state ($PE_BAD_COUNT)"
fi

if [ "$VALIDATION_PASSED" = true ]; then
  echo ""
  log_success "Foundry operational validation completed successfully"
  exit 0
fi

echo ""
log_error "Foundry operational validation failed"
exit 1
