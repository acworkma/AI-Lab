#!/usr/bin/env bash
#
# deploy-mcp-server.sh - Build and Deploy MCP Server to ACA
#
# Purpose: Build the MCP server container image in the private ACR,
#          deploy it as a container app in the existing ACA environment,
#          configure managed identity for ACR pull, and validate deployment.
#
# Usage: ./scripts/deploy-mcp-server.sh [OPTIONS]
#
# Prerequisites:
# - Core infrastructure deployed (rg-ai-core)
# - ACA environment deployed (rg-ai-aca)
# - Private ACR deployed (rg-ai-acr)
# - VPN connection established (for ACR build and validation)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
APP_NAME="mcp-server"
IMAGE_TAG="v1"
ACA_RG="rg-ai-aca"
ACR_RG="rg-ai-acr"
ACA_ENV_NAME="cae-ai-lab"
TARGET_PORT=3333
CPU="0.25"
MEMORY="0.5Gi"
MIN_REPLICAS=1
MAX_REPLICAS=3
SKIP_BUILD=false
AUTO_APPROVE=false
LOCATION="eastus2"
BUILD_CONTEXT="${REPO_ROOT}/mcp-server"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# FUNCTIONS
# ============================================================================

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
Usage: $0 [OPTIONS]

Build and deploy the MCP server container app to Azure Container Apps

OPTIONS:
    -n, --name NAME             Container app name (default: mcp-server)
    -t, --tag TAG               Image tag (default: v1)
    -s, --skip-build            Skip image build (use existing image in ACR)
    -a, --auto-approve          Skip confirmation prompt
    -h, --help                  Show this help message

EXAMPLES:
    # Standard deployment (build + deploy)
    $0

    # Deploy with custom tag
    $0 --tag v2

    # Skip build, redeploy existing image
    $0 --skip-build

    # Automated deployment (CI/CD)
    $0 --auto-approve

EXIT CODES:
    0  Success
    1  Prerequisites check failed
    2  Image build failed
    3  Deployment failed
    4  Post-deployment validation failed

EOF
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Install: https://aka.ms/azure-cli"
        exit 1
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Install: sudo apt install jq"
        exit 1
    fi

    # Check Azure login
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Run 'az login' first."
        exit 1
    fi

    # Check ACR resource group exists
    if ! az group show --name "$ACR_RG" &> /dev/null; then
        log_error "ACR resource group '$ACR_RG' not found. Deploy ACR first."
        exit 1
    fi

    # Check ACA resource group exists
    if ! az group show --name "$ACA_RG" &> /dev/null; then
        log_error "ACA resource group '$ACA_RG' not found. Deploy ACA environment first."
        exit 1
    fi

    # Check ACA environment exists
    if ! az containerapp env show --name "$ACA_ENV_NAME" --resource-group "$ACA_RG" &> /dev/null; then
        log_error "ACA environment '$ACA_ENV_NAME' not found in '$ACA_RG'. Deploy ACA environment first."
        exit 1
    fi

    # Check build context exists
    if [[ ! -f "${BUILD_CONTEXT}/Dockerfile" ]]; then
        log_error "Dockerfile not found at ${BUILD_CONTEXT}/Dockerfile"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

discover_acr() {
    log_info "Discovering ACR in resource group '$ACR_RG'..."

    ACR_NAME=$(az acr list --resource-group "$ACR_RG" --query "[0].name" -o tsv 2>/dev/null)
    if [[ -z "$ACR_NAME" ]]; then
        log_error "No ACR found in resource group '$ACR_RG'"
        exit 1
    fi

    ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query "loginServer" -o tsv)
    ACR_ID=$(az acr show --name "$ACR_NAME" --query "id" -o tsv)

    log_success "Found ACR: $ACR_NAME ($ACR_LOGIN_SERVER)"
}

build_image() {
    if [[ "$SKIP_BUILD" == "true" ]]; then
        log_info "Skipping image build (--skip-build)"
        return 0
    fi

    local FULL_IMAGE="${ACR_LOGIN_SERVER}/${APP_NAME}:${IMAGE_TAG}"
    log_info "Building image: $FULL_IMAGE"
    log_info "Build context: ${BUILD_CONTEXT}"

    if ! az acr build \
        --registry "$ACR_NAME" \
        --image "${APP_NAME}:${IMAGE_TAG}" \
        --file "${BUILD_CONTEXT}/Dockerfile" \
        "${BUILD_CONTEXT}" ; then
        log_error "Image build failed"
        exit 2
    fi

    log_success "Image built and pushed: $FULL_IMAGE"
}

deploy_container_app() {
    local FULL_IMAGE="${ACR_LOGIN_SERVER}/${APP_NAME}:${IMAGE_TAG}"
    local ACA_ENV_ID
    ACA_ENV_ID=$(az containerapp env show --name "$ACA_ENV_NAME" --resource-group "$ACA_RG" --query "id" -o tsv)

    log_info "Deploying container app: $APP_NAME"

    # Check if app already exists
    if az containerapp show --name "$APP_NAME" --resource-group "$ACA_RG" &> /dev/null; then
        log_info "Container app exists, updating..."
        if ! az containerapp update \
            --name "$APP_NAME" \
            --resource-group "$ACA_RG" \
            --image "$FULL_IMAGE" \
            --set-env-vars "MCP_SERVER_VERSION=${IMAGE_TAG}" ; then
            log_error "Container app update failed"
            exit 3
        fi
    else
        log_info "Creating new container app..."
        if ! az containerapp create \
            --name "$APP_NAME" \
            --resource-group "$ACA_RG" \
            --environment "$ACA_ENV_NAME" \
            --image "$FULL_IMAGE" \
            --target-port "$TARGET_PORT" \
            --ingress internal \
            --registry-server "$ACR_LOGIN_SERVER" \
            --registry-identity system \
            --system-assigned \
            --cpu "$CPU" \
            --memory "$MEMORY" \
            --min-replicas "$MIN_REPLICAS" \
            --max-replicas "$MAX_REPLICAS" \
            --env-vars "MCP_SERVER_VERSION=${IMAGE_TAG}" ; then
            log_error "Container app creation failed"
            exit 3
        fi
    fi

    log_success "Container app deployed: $APP_NAME"
}

assign_acr_pull_role() {
    log_info "Checking AcrPull role assignment..."

    # Get the container app's managed identity principal ID
    local PRINCIPAL_ID
    PRINCIPAL_ID=$(az containerapp show \
        --name "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --query "identity.principalId" -o tsv 2>/dev/null)

    if [[ -z "$PRINCIPAL_ID" || "$PRINCIPAL_ID" == "null" ]]; then
        log_warning "No system-assigned identity found. Skipping role assignment."
        return 0
    fi

    # Check if role already assigned
    local EXISTING
    EXISTING=$(az role assignment list \
        --assignee "$PRINCIPAL_ID" \
        --role "AcrPull" \
        --scope "$ACR_ID" \
        --query "length(@)" -o tsv 2>/dev/null)

    if [[ "$EXISTING" -gt 0 ]]; then
        log_info "AcrPull role already assigned"
        return 0
    fi

    log_info "Assigning AcrPull role to container app identity..."
    if az role assignment create \
        --assignee "$PRINCIPAL_ID" \
        --role "AcrPull" \
        --scope "$ACR_ID" &> /dev/null; then
        log_success "AcrPull role assigned"
        log_warning "Role propagation may take 1-2 minutes"
    else
        log_warning "Failed to assign AcrPull role (may already exist)"
    fi
}

show_outputs() {
    echo ""
    echo "============================================"
    echo "MCP Server Deployment Summary"
    echo "============================================"
    echo ""

    local FQDN
    FQDN=$(az containerapp show \
        --name "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null)

    local LATEST_REVISION
    LATEST_REVISION=$(az containerapp show \
        --name "$APP_NAME" \
        --resource-group "$ACA_RG" \
        --query "properties.latestRevisionName" -o tsv 2>/dev/null)

    echo "  App Name:         $APP_NAME"
    echo "  Resource Group:   $ACA_RG"
    echo "  Image:            ${ACR_LOGIN_SERVER}/${APP_NAME}:${IMAGE_TAG}"
    echo "  FQDN:             ${FQDN:-N/A}"
    echo "  Endpoint:         https://${FQDN:-N/A}"
    echo "  Target Port:      $TARGET_PORT"
    echo "  Latest Revision:  ${LATEST_REVISION:-N/A}"
    echo "  Ingress:          Internal only"
    echo ""

    echo "============================================"
    echo "Next Steps"
    echo "============================================"
    echo ""
    echo "  1. Connect to VPN"
    echo "  2. Validate infrastructure:"
    echo "     ./scripts/validate-mcp-server.sh"
    echo "  3. Test MCP tools:"
    echo "     python3 scripts/test-mcp-server.py --endpoint https://${FQDN:-<FQDN>}"
    echo ""
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            APP_NAME="$2"
            shift 2
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -s|--skip-build)
            SKIP_BUILD=true
            shift
            ;;
        -a|--auto-approve)
            AUTO_APPROVE=true
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

# ============================================================================
# MAIN
# ============================================================================

echo ""
echo "============================================"
echo "MCP Server Deployment"
echo "============================================"
echo ""

START_TIME=$(date +%s)

# Step 1: Check prerequisites
check_prerequisites

# Step 2: Discover ACR
discover_acr

echo ""
echo "  App Name:       $APP_NAME"
echo "  Image Tag:      $IMAGE_TAG"
echo "  ACR:            $ACR_LOGIN_SERVER"
echo "  ACA Env:        $ACA_ENV_NAME"
echo "  Resource Group: $ACA_RG"
echo "  Skip Build:     $SKIP_BUILD"
echo ""

# Step 3: Confirm deployment
if [[ "$AUTO_APPROVE" != "true" ]]; then
    read -p "Proceed with deployment? (y/N) " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        log_info "Deployment cancelled."
        exit 0
    fi
fi

# Step 4: Build image
build_image

# Step 5: Deploy container app
deploy_container_app

# Step 6: Assign AcrPull role
assign_acr_pull_role

# Step 7: Show outputs
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

show_outputs

log_success "Deployment completed in ${ELAPSED} seconds"
echo ""
