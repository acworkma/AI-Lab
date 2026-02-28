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

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

format_duration() {
  local total_seconds="$1"
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))
  printf "%02dh:%02dm:%02ds" "$hours" "$minutes" "$seconds"
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

EXIST_STATUS=$(curl -s \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -o /tmp/foundry-caphost-get-response.json \
  -w "%{http_code}" \
  "${API_URL}")

if [ "$EXIST_STATUS" = "404" ]; then
  log_warning "Capability host not found; treating as already deleted"
  rm -f /tmp/foundry-caphost-get-response.json
  exit 0
fi

if [ "$EXIST_STATUS" != "200" ]; then
  log_error "Could not verify capability host state (HTTP ${EXIST_STATUS})"
  cat /tmp/foundry-caphost-get-response.json
  rm -f /tmp/foundry-caphost-get-response.json
  exit 1
fi

rm -f /tmp/foundry-caphost-get-response.json

log_info "Deleting capability host: ${CAPHOST_NAME}"
RESPONSE_HEADERS=$(mktemp)

HTTP_STATUS=$(curl -X DELETE \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -D "${RESPONSE_HEADERS}" \
  -s \
  -o /tmp/foundry-caphost-delete-response.json \
  -w "%{http_code}" \
  "${API_URL}")

if [ "$HTTP_STATUS" = "404" ]; then
  log_warning "Capability host not found; treating as already deleted"
  rm -f "${RESPONSE_HEADERS}" /tmp/foundry-caphost-delete-response.json
  exit 0
fi

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "204" ]; then
  log_success "Capability host deletion completed"
  rm -f "${RESPONSE_HEADERS}" /tmp/foundry-caphost-delete-response.json
  exit 0
fi

if [ "$HTTP_STATUS" != "202" ]; then
  log_error "Capability host deletion request failed (HTTP ${HTTP_STATUS})"
  cat /tmp/foundry-caphost-delete-response.json
  rm -f "${RESPONSE_HEADERS}" /tmp/foundry-caphost-delete-response.json
  exit 1
fi

OPERATION_URL=$(grep -i "Azure-AsyncOperation" "${RESPONSE_HEADERS}" | cut -d' ' -f2 | tr -d '\r')
rm -f "${RESPONSE_HEADERS}"
rm -f /tmp/foundry-caphost-delete-response.json

[ -n "$OPERATION_URL" ] || { log_error "Could not find async operation URL"; exit 1; }

STATUS="Deleting"
POLL_START_TS=$(date +%s)
while [ "$STATUS" = "Deleting" ] || [ "$STATUS" = "Creating" ] || [ "$STATUS" = "Running" ] || [ "$STATUS" = "InProgress" ]; do
  ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)
  OP_RESPONSE=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" "${OPERATION_URL}")
  ERROR_CODE=$(echo "$OP_RESPONSE" | jq -r '.error.code // empty')
  if [ "$ERROR_CODE" = "ResourceNotFound" ] || [ "$ERROR_CODE" = "NotFound" ]; then
    log_warning "Capability host already deleted"
    exit 0
  fi
  if [ "$ERROR_CODE" = "TransientError" ]; then
    sleep 10
    continue
  fi

  STATUS=$(echo "$OP_RESPONSE" | jq -r '.status // empty')
  [ -n "$STATUS" ] || { log_error "Could not determine operation status"; echo "$OP_RESPONSE"; exit 1; }

  NOW_TS=$(date +%s)
  ELAPSED=$((NOW_TS - POLL_START_TS))
  if [ "$STATUS" = "Creating" ] || [ "$STATUS" = "Running" ] || [ "$STATUS" = "InProgress" ] || [ "$STATUS" = "Deleting" ]; then
    log_info "Delete operation in progress (service status='${STATUS}', elapsed=$(format_duration "$ELAPSED"))"
  else
    log_info "Delete operation status='${STATUS}' (elapsed=$(format_duration "$ELAPSED"))"
  fi

  if [ "$STATUS" = "Deleting" ] || [ "$STATUS" = "Creating" ] || [ "$STATUS" = "Running" ] || [ "$STATUS" = "InProgress" ]; then
    sleep 10
  fi
done

if [ "$STATUS" = "Succeeded" ]; then
  log_success "Capability host deletion completed"
else
  log_error "Capability host deletion failed with status: $STATUS"
  exit 1
fi
