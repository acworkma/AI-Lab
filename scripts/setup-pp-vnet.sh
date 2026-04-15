#!/usr/bin/env bash
#
# setup-pp-vnet.sh - Set up Power Platform VNet Delegation
#
# Purpose: Configure Power Platform enterprise policy and link to a Managed Environment
#          for VNet support (enables Copilot Studio to reach private endpoints)
#
# Prerequisites:
# - Private APIM deployed (run deploy-apim-private.sh first — creates the PP subnet)
# - Managed Power Platform environment created (see docs/apim-private/README.md)
# - PowerShell with Microsoft.PowerPlatform.EnterprisePolicies module
# - Azure Network Contributor + Power Platform Admin roles
#
# Usage: ./scripts/setup-pp-vnet.sh
#

set -euo pipefail

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

echo ""
echo "========================================================="
echo "  Power Platform VNet Delegation Setup"
echo "========================================================="
echo ""

# ============================================================================
# CONFIGURATION
# ============================================================================

# These should match your deployment
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RESOURCE_GROUP="rg-ai-core"
VNET_NAME="vnet-ai-shared"
SUBNET_NAME="PowerPlatformSubnet"
POLICY_NAME="pp-enterprise-policy-ai-lab"
POLICY_LOCATION="unitedstates"  # Must match PP environment region

log_info "Configuration:"
echo "  Subscription:  $SUBSCRIPTION_ID"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  VNet:          $VNET_NAME"
echo "  Subnet:        $SUBNET_NAME"
echo "  Policy Name:   $POLICY_NAME"
echo "  Policy Region: $POLICY_LOCATION"
echo ""

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================

log_info "Checking prerequisites..."

# Check subnet exists and is delegated
DELEGATION=$(az network vnet subnet show \
    --name "$SUBNET_NAME" \
    --vnet-name "$VNET_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "delegations[0].serviceName" -o tsv 2>/dev/null || echo "")

if [ -z "$DELEGATION" ]; then
    log_error "Subnet $SUBNET_NAME not found or not delegated."
    log_error "Run deploy-apim-private.sh first to create the Power Platform subnet."
    exit 1
fi

if [ "$DELEGATION" != "Microsoft.PowerPlatform/enterprisePolicies" ]; then
    log_error "Subnet $SUBNET_NAME is delegated to $DELEGATION, not Microsoft.PowerPlatform/enterprisePolicies"
    exit 1
fi

log_success "Subnet $SUBNET_NAME exists with correct delegation"

# Check PowerShell availability
if ! command -v pwsh &> /dev/null; then
    log_warning "PowerShell Core (pwsh) not found."
    log_info "The enterprise policy setup requires PowerShell with the Microsoft.PowerPlatform.EnterprisePolicies module."
    log_info ""
    log_info "Install PowerShell Core: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
    log_info ""
    log_info "Then run these PowerShell commands manually:"
    echo ""
fi

# ============================================================================
# GENERATE POWERSHELL COMMANDS
# ============================================================================

VNET_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}"

cat << 'BANNER'

=== PowerShell Commands for Enterprise Policy Setup ===

Run these commands in PowerShell (pwsh) with Power Platform Admin role:

BANNER

cat << EOF
# Step 1: Install and import the module
Install-Module Microsoft.PowerPlatform.EnterprisePolicies -Force
Import-Module Microsoft.PowerPlatform.EnterprisePolicies

# Step 2: Create the enterprise policy
# Note: For two-region geographies (e.g., United States), you need VNets in both regions.
# For single-subnet setup (dev/test), use:
New-SubnetInjectionEnterprisePolicy \\
    -SubscriptionId "$SUBSCRIPTION_ID" \\
    -ResourceGroupName "$RESOURCE_GROUP" \\
    -PolicyName "$POLICY_NAME" \\
    -PolicyLocation "$POLICY_LOCATION" \\
    -VirtualNetworkId "$VNET_ID" \\
    -SubnetName "$SUBNET_NAME"

# Step 3: Link the policy to your Managed Power Platform environment
# Replace ENVIRONMENT_ID with your PP environment ID from the Admin Center
Enable-SubnetInjection \\
    -EnvironmentId "REPLACE_WITH_PP_ENVIRONMENT_ID" \\
    -PolicyArmId "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.PowerPlatform/enterprisePolicies/${POLICY_NAME}"

# Step 4: Verify the setup
# In the PP Admin Center, the environment should show VNet status as "Active"
# You can also run diagnostics:
# Test-NetworkConnectivity -EnvironmentId "REPLACE_WITH_PP_ENVIRONMENT_ID"
EOF

echo ""
log_info "After completing the PowerShell steps:"
echo "  1. Deploy MCP API: ./scripts/deploy-mcp-api-private.sh"
echo "  2. Create custom connector in Copilot Studio (see docs/apim-private/README.md)"
echo "  3. Validate: ./scripts/validate-apim-private.sh"
echo ""

# ============================================================================
# OPTIONAL: RUN POWERSHELL AUTOMATICALLY
# ============================================================================

if command -v pwsh &> /dev/null; then
    echo ""
    read -p "Would you like to run the enterprise policy creation now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter your Power Platform environment ID: " PP_ENV_ID
        if [ -z "$PP_ENV_ID" ]; then
            log_error "Environment ID is required."
            exit 1
        fi

        log_info "Running PowerShell commands..."
        pwsh -Command "
            Install-Module Microsoft.PowerPlatform.EnterprisePolicies -Force -Scope CurrentUser
            Import-Module Microsoft.PowerPlatform.EnterprisePolicies

            Write-Host 'Creating enterprise policy...'
            New-SubnetInjectionEnterprisePolicy \
                -SubscriptionId '$SUBSCRIPTION_ID' \
                -ResourceGroupName '$RESOURCE_GROUP' \
                -PolicyName '$POLICY_NAME' \
                -PolicyLocation '$POLICY_LOCATION' \
                -VirtualNetworkId '$VNET_ID' \
                -SubnetName '$SUBNET_NAME'

            Write-Host 'Linking policy to environment...'
            Enable-SubnetInjection \
                -EnvironmentId '$PP_ENV_ID' \
                -PolicyArmId '/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.PowerPlatform/enterprisePolicies/$POLICY_NAME'

            Write-Host 'Done! Verify in the Power Platform Admin Center.'
        "
        log_success "Enterprise policy setup complete!"
    fi
fi
