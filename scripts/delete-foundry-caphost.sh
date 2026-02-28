#!/usr/bin/env bash

set -euo pipefail

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
Usage: $0 --subscription-id <id> --resource-group <rg> --account-name <name> --caphost-name <name> [--project-name <name>]
EOF
  exit 1
}

SUBSCRIPTION_ID=""
RESOURCE_GROUP=""
ACCOUNT_NAME=""
CAPHOST_NAME=""
PROJECT_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription-id)
      SUBSCRIPTION_ID="$2"
      shift 2
      ;;
    --resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    --account-name)
      ACCOUNT_NAME="$2"
      shift 2
      ;;
    --caphost-name)
      CAPHOST_NAME="$2"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME="$2"
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

[ -n "$SUBSCRIPTION_ID" ] || usage
[ -n "$RESOURCE_GROUP" ] || usage
[ -n "$ACCOUNT_NAME" ] || usage
[ -n "$CAPHOST_NAME" ] || usage

command -v az >/dev/null 2>&1 || { log_error "Azure CLI not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq not found"; exit 1; }
command -v curl >/dev/null 2>&1 || { log_error "curl not found"; exit 1; }

log_info "Getting Azure access token..."
ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)
[ -n "$ACCESS_TOKEN" ] || { log_error "Failed to get access token"; exit 1; }

if [ -n "$PROJECT_NAME" ]; then
  API_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${ACCOUNT_NAME}/projects/${PROJECT_NAME}/capabilityHosts/${CAPHOST_NAME}?api-version=2025-04-01-preview"
  log_info "Scope: project capability host (${PROJECT_NAME}/${CAPHOST_NAME})"
else
  API_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${ACCOUNT_NAME}/capabilityHosts/${CAPHOST_NAME}?api-version=2025-04-01-preview"
  log_info "Scope: account capability host (${CAPHOST_NAME})"
fi

log_info "Deleting capability host: ${CAPHOST_NAME}"
RESPONSE_HEADERS=$(mktemp)

curl -X DELETE \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -D "${RESPONSE_HEADERS}" \
  -s \
  "${API_URL}" >/dev/null

OPERATION_URL=$(grep -i "Azure-AsyncOperation" "${RESPONSE_HEADERS}" | cut -d' ' -f2 | tr -d '\r')
rm -f "${RESPONSE_HEADERS}"

[ -n "$OPERATION_URL" ] || { log_error "Could not find async operation URL"; exit 1; }

STATUS="Deleting"
while [ "$STATUS" = "Deleting" ]; do
  ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)
  OP_RESPONSE=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" "${OPERATION_URL}")
  ERROR_CODE=$(echo "$OP_RESPONSE" | jq -r '.error.code // empty')
  if [ "$ERROR_CODE" = "TransientError" ]; then
    sleep 10
    continue
  fi

  STATUS=$(echo "$OP_RESPONSE" | jq -r '.status // empty')
  [ -n "$STATUS" ] || { log_error "Could not determine operation status"; echo "$OP_RESPONSE"; exit 1; }
  log_info "Current status: $STATUS"

  if [ "$STATUS" = "Deleting" ]; then
    sleep 10
  fi
done

if [ "$STATUS" = "Succeeded" ]; then
  log_success "Capability host deletion completed"
else
  log_error "Capability host deletion failed with status: $STATUS"
  exit 1
fi
