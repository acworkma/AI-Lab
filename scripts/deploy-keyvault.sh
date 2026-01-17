#!/usr/bin/env bash
#
# deploy-keyvault.sh - Deploy Private Azure Key Vault
# 
# Purpose: Orchestrate deployment of Key Vault resource group with private endpoint
#          connectivity to core infrastructure
#
# Usage: ./scripts/deploy-keyvault.sh [--parameter-file <path>] [--skip-whatif] [--auto-approve]
#
# Prerequisites:
# - Core infrastructure deployed (run scripts/deploy-core.sh first)
# - VPN connection established (for post-deployment DNS verification)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PARAMETER_FILE="${REPO_ROOT}/bicep/keyvault/main.parameters.json"
TEMPLATE_FILE="${REPO_ROOT}/bicep/keyvault/main.bicep"
DEPLOYMENT_NAME="deploy-ai-keyvault-$(date +%Y%m%d-%H%M%S)"
SKIP_WHATIF=false
AUTO_APPROVE=false
LOCATION="eastus2"

# NFR-002: Track deployment time (target: <3 minutes)
START_TIME=""
END_TIME=""

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

Deploy Private Azure Key Vault with RBAC authorization and private endpoint

OPTIONS:
    -p, --parameter-file PATH   Path to parameter file (default: bicep/keyvault/main.parameters.json)
    -s, --skip-whatif           Skip what-if analysis (not recommended)
    -a, --auto-approve          Skip confirmation prompt (use with caution)
    -d, --dry-run               Run what-if only, do not deploy
    -h, --help                  Show this help message

EXAMPLES:
    # Standard deployment with what-if and confirmation
    $0

    # Use custom parameter file
    $0 --parameter-file bicep/keyvault/main.parameters.prod.json

    # Automated deployment (CI/CD)
    $0 --auto-approve

    # Preview changes only
    $0 --dry-run

EXIT CODES:
    0  Success
    1  Prerequisites check failed
    2  What-if analysis failed
    3  Deployment failed
    4  Post-deployment validation failed

EOF
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Run validation script
    if ! "${SCRIPT_DIR}/validate-keyvault.sh" --parameter-file "$PARAMETER_FILE"; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

run_whatif() {
    log_info "Running what-if analysis..."
    
    local LOCATION
    LOCATION=$(jq -r '.parameters.location.value // "eastus2"' "$PARAMETER_FILE")
    
    if ! az deployment sub what-if \
        --name "$DEPLOYMENT_NAME-whatif" \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE"; then
        log_error "What-if analysis failed"
        exit 2
    fi
    
    echo ""
    log_success "What-if analysis complete"
}

confirm_deployment() {
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    read -p "Do you want to proceed with the deployment? (y/N) " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

deploy() {
    log_info "Starting Key Vault deployment..."
    START_TIME=$(date +%s)
    
    local LOCATION
    LOCATION=$(jq -r '.parameters.location.value // "eastus2"' "$PARAMETER_FILE")
    
    # Run deployment
    if ! az deployment sub create \
        --name "$DEPLOYMENT_NAME" \
        --location "$LOCATION" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --output json > /tmp/keyvault-deployment-output.json; then
        log_error "Deployment failed"
        cat /tmp/keyvault-deployment-output.json
        exit 3
    fi
    
    END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    
    echo ""
    log_success "Deployment completed in ${DURATION} seconds"
    
    # NFR-002: Check deployment time target
    if [[ $DURATION -gt 180 ]]; then
        log_warning "Deployment exceeded 3-minute target (NFR-002)"
    else
        log_success "Deployment time within target (NFR-002: <3 minutes)"
    fi
    
    # Display outputs
    echo ""
    log_info "Deployment Outputs:"
    echo "----------------------------------------"
    
    local KV_NAME
    KV_NAME=$(jq -r '.properties.outputs.keyVaultName.value // "N/A"' /tmp/keyvault-deployment-output.json)
    local KV_URI
    KV_URI=$(jq -r '.properties.outputs.keyVaultUri.value // "N/A"' /tmp/keyvault-deployment-output.json)
    local KV_ID
    KV_ID=$(jq -r '.properties.outputs.keyVaultId.value // "N/A"' /tmp/keyvault-deployment-output.json)
    local PE_IP
    PE_IP=$(jq -r '.properties.outputs.privateEndpointIp.value // "N/A"' /tmp/keyvault-deployment-output.json)
    local RG_NAME
    RG_NAME=$(jq -r '.properties.outputs.resourceGroupName.value // "N/A"' /tmp/keyvault-deployment-output.json)
    
    echo "  Resource Group:      $RG_NAME"
    echo "  Key Vault Name:      $KV_NAME"
    echo "  Key Vault URI:       $KV_URI"
    echo "  Private Endpoint IP: $PE_IP"
    echo "----------------------------------------"
    
    # Save outputs for later use
    echo "$KV_NAME" > /tmp/keyvault-name.txt
}

run_post_deployment_validation() {
    log_info "Running post-deployment validation..."
    
    if ! "${SCRIPT_DIR}/validate-keyvault.sh" --parameter-file "$PARAMETER_FILE" --deployed; then
        log_error "Post-deployment validation failed"
        exit 4
    fi
    
    log_success "Post-deployment validation passed"
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--parameter-file)
            PARAMETER_FILE="$2"
            shift 2
            ;;
        -s|--skip-whatif)
            SKIP_WHATIF=true
            shift
            ;;
        -a|--auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
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
echo "Private Azure Key Vault Deployment"
echo "============================================"
echo ""
echo "Template:    $TEMPLATE_FILE"
echo "Parameters:  $PARAMETER_FILE"
echo "Deployment:  $DEPLOYMENT_NAME"
echo ""

# Step 1: Check prerequisites
check_prerequisites

# Step 2: Run what-if (unless skipped)
if [[ "$SKIP_WHATIF" == "false" ]]; then
    run_whatif
fi

# Step 3: Dry-run mode exits here
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry-run complete. No changes made."
    exit 0
fi

# Step 4: Confirm deployment
confirm_deployment

# Step 5: Deploy
deploy

# Step 6: Post-deployment validation
run_post_deployment_validation

echo ""
echo "============================================"
log_success "Key Vault deployment complete!"
echo ""
echo "Next steps:"
echo "  1. Connect via VPN to verify private DNS resolution"
echo "  2. Run: ./scripts/validate-keyvault-dns.sh"
echo "  3. Assign RBAC roles: ./scripts/grant-keyvault-roles.sh"
echo "============================================"
