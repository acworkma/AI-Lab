#!/usr/bin/env bash
#
# cleanup-apim-private.sh - Clean up Private APIM deployment
# 
# Purpose: Remove private APIM resource group and optionally clean up
#          subnets, NSG, and DNS zone from shared services VNet
#
# Usage: ./scripts/cleanup-apim-private.sh [--include-networking] [--auto-approve]
#

set -euo pipefail

# Default values
RESOURCE_GROUP="rg-ai-apim-private"
CORE_RG="rg-ai-core"
SHARED_VNET="vnet-ai-shared"
APIM_SUBNET="ApimPrivateIntegrationSubnet"
PP_SUBNET="PowerPlatformSubnet"
APIM_NSG="nsg-apim-private-integration"
DNS_ZONE="privatelink.azure-api.net"
INCLUDE_NETWORKING=false
AUTO_APPROVE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Private APIM deployment

OPTIONS:
    --include-networking  Also remove subnets, NSG, and DNS zone from rg-ai-core
    --auto-approve        Skip confirmation prompts
    -h, --help            Show this help message

NOTES:
    - Does NOT remove the Power Platform enterprise policy (use PowerShell)
    - Does NOT remove the Managed PP environment
    - With --include-networking: removes PP subnet, APIM subnet, NSG, DNS zone

EOF
    exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --include-networking)
            INCLUDE_NETWORKING=true
            shift
            ;;
        --auto-approve)
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

echo ""
echo "=============================================="
echo "  Private APIM Cleanup"
echo "=============================================="
echo ""

log_info "Resources to remove:"
echo "  - Resource group: $RESOURCE_GROUP (APIM instance, private endpoint)"
if [ "$INCLUDE_NETWORKING" = true ]; then
    echo "  - Subnet: $APIM_SUBNET (from $SHARED_VNET)"
    echo "  - Subnet: $PP_SUBNET (from $SHARED_VNET)"
    echo "  - NSG: $APIM_NSG (from $CORE_RG)"
    echo "  - DNS Zone: $DNS_ZONE (from $CORE_RG)"
fi
echo ""
log_warning "This does NOT remove:"
echo "  - Power Platform enterprise policy (use PowerShell)"
echo "  - Managed Power Platform environment"
echo ""

if [ "$AUTO_APPROVE" = false ]; then
    read -p "Are you sure you want to proceed? (yes/no): " response
    case "$response" in
        [Yy][Ee][Ss])
            ;;
        *)
            log_info "Cleanup cancelled."
            exit 0
            ;;
    esac
fi

# Delete resource group (includes APIM + PE)
if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    log_info "Deleting resource group $RESOURCE_GROUP..."
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    log_success "Resource group deletion initiated (runs in background)"
else
    log_info "Resource group $RESOURCE_GROUP does not exist, skipping"
fi

# Optionally clean up networking resources in core RG
if [ "$INCLUDE_NETWORKING" = true ]; then
    echo ""
    log_info "Cleaning up networking resources..."

    # Delete subnets
    for subnet in "$APIM_SUBNET" "$PP_SUBNET"; do
        if az network vnet subnet show --name "$subnet" --vnet-name "$SHARED_VNET" --resource-group "$CORE_RG" &> /dev/null; then
            log_info "Deleting subnet $subnet..."
            az network vnet subnet delete --name "$subnet" --vnet-name "$SHARED_VNET" --resource-group "$CORE_RG"
            log_success "Subnet $subnet deleted"
        else
            log_info "Subnet $subnet does not exist, skipping"
        fi
    done

    # Delete NSG
    if az network nsg show --name "$APIM_NSG" --resource-group "$CORE_RG" &> /dev/null; then
        log_info "Deleting NSG $APIM_NSG..."
        az network nsg delete --name "$APIM_NSG" --resource-group "$CORE_RG"
        log_success "NSG $APIM_NSG deleted"
    else
        log_info "NSG $APIM_NSG does not exist, skipping"
    fi

    # Delete DNS zone
    if az network private-dns zone show --name "$DNS_ZONE" --resource-group "$CORE_RG" &> /dev/null; then
        log_info "Deleting private DNS zone $DNS_ZONE..."
        az network private-dns zone delete --name "$DNS_ZONE" --resource-group "$CORE_RG" --yes
        log_success "DNS zone $DNS_ZONE deleted"
    else
        log_info "DNS zone $DNS_ZONE does not exist, skipping"
    fi
fi

echo ""
log_success "Cleanup complete!"
echo ""
log_info "To remove the Power Platform enterprise policy, run in PowerShell:"
echo "  Remove-SubnetInjection -EnvironmentId <PP_ENVIRONMENT_ID>"
echo "  Remove-SubnetInjectionEnterprisePolicy -PolicyArmId <POLICY_ARM_ID>"
