# Private Storage Account Infrastructure

This document covers the Private Azure Storage Account infrastructure deployed as part of the AI-Lab platform.

## Overview

The storage infrastructure provides a secure, private Azure Storage Account with:

- **Private Endpoint Access**: No public internet exposure
- **RBAC-Only Authentication**: Shared keys disabled for enhanced security
- **DNS Integration**: Private DNS zone for seamless resolution via VPN
- **TLS 1.2**: Minimum encryption standard enforced

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    rg-ai-storage                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Storage Account (stailab<MMDD>)            │   │
│  │  • RBAC-only (no shared keys)                           │   │
│  │  • TLS 1.2 minimum                                      │   │
│  │  • Public access disabled                               │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│  ┌────────────────────────▼────────────────────────────────┐   │
│  │           Private Endpoint (pe-stailab<MMDD>)           │   │
│  │  • Target: blob sub-resource                            │   │
│  │  • Private IP: 10.1.0.x                                 │   │
│  └────────────────────────┬────────────────────────────────┘   │
└───────────────────────────┼─────────────────────────────────────┘
                            │
┌───────────────────────────┼─────────────────────────────────────┐
│                    rg-ai-core                                   │
│                           │                                     │
│  ┌────────────────────────▼────────────────────────────────┐   │
│  │        PrivateEndpointSubnet (10.1.0.0/26)              │   │
│  │                  vnet-ai-shared                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │       privatelink.blob.core.windows.net (DNS Zone)      │   │
│  │  • A record: stailab<MMDD> → 10.1.0.x                   │   │
│  │  • Linked to vnet-ai-shared                              │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

Before deploying, ensure:

1. **Core Infrastructure**: Deploy with `./scripts/deploy-core.sh`
2. **VPN Access**: Required for private endpoint access
3. **Azure CLI**: Version 2.50+ with Bicep extension
4. **Permissions**: Contributor on subscription, User Access Admin for RBAC

## Deployment

### Quick Start

```bash
# Deploy with defaults
./scripts/deploy-storage-infra.sh

# Deploy without prompts
./scripts/deploy-storage-infra.sh --yes

# Deploy with custom parameters
./scripts/deploy-storage-infra.sh -p custom.parameters.json
```

### Customization

Edit `bicep/storage-infra/main.parameters.json`:

```json
{
  "parameters": {
    "storageNameSuffix": { "value": "0117" },
    "location": { "value": "eastus2" },
    "environment": { "value": "dev" }
  }
}
```

Key parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `storageNameSuffix` | Appended to `stailab` | `0117` |
| `location` | Azure region | `eastus2` |
| `environment` | Environment tag | `dev` |
| `enableVersioning` | Blob versioning | `true` |
| `softDeleteRetentionDays` | Soft delete period | `7` |

## Security Model

### RBAC-Only Access

Shared key access is **disabled**. All access requires Azure AD authentication:

```bash
# Grant your user access
./scripts/grant-storage-infra-roles.sh --current-user

# Grant specific user
./scripts/grant-storage-infra-roles.sh --user user@example.com

# Grant service principal
./scripts/grant-storage-infra-roles.sh --service-principal <object-id>
```

Available roles:

| Role | Permissions |
|------|-------------|
| `Storage Blob Data Reader` | Read blobs |
| `Storage Blob Data Contributor` | Read/write blobs (default) |
| `Storage Blob Data Owner` | Full access + RBAC management |

### Private Network

- **No public endpoint**: `publicNetworkAccess: Disabled`
- **VPN required**: Access only via Azure Virtual WAN VPN
- **Private DNS**: Resolves `stailab<MMDD>.blob.core.windows.net` to private IP

## Validation

### Post-Deployment Checks

```bash
# Full validation
./scripts/validate-storage-infra.sh

# DNS-specific validation (requires VPN)
./scripts/validate-storage-infra-dns.sh
```

### Manual Verification

```bash
# Check DNS resolution (via VPN)
nslookup stailab0117.blob.core.windows.net

# Should return 10.1.0.x (private IP), not public IP

# Test RBAC access
az storage container list \
    --account-name stailab0117 \
    --auth-mode login
```

## Operations

### Create Container

```bash
az storage container create \
    --name mycontainer \
    --account-name stailab0117 \
    --auth-mode login
```

### Upload Blob

```bash
az storage blob upload \
    --container-name mycontainer \
    --name myfile.txt \
    --file ./myfile.txt \
    --account-name stailab0117 \
    --auth-mode login
```

### List Blobs

```bash
az storage blob list \
    --container-name mycontainer \
    --account-name stailab0117 \
    --auth-mode login \
    --output table
```

## Cleanup

```bash
# Interactive cleanup
./scripts/cleanup-storage-infra.sh

# Force cleanup (no prompts)
./scripts/cleanup-storage-infra.sh --force

# Keep DNS records
./scripts/cleanup-storage-infra.sh --keep-dns
```

## Troubleshooting

### DNS Resolution Fails

**Symptom**: `nslookup` returns public IP or fails

**Causes & Solutions**:

1. **VPN not connected**: Connect to Azure Virtual WAN VPN
2. **DNS zone not linked**: Verify `privatelink.blob.core.windows.net` is linked to VNet
3. **DNS record missing**: Check A record exists in private DNS zone

```bash
# Check DNS zone link
az network private-dns link vnet list \
    --resource-group rg-ai-core \
    --zone-name privatelink.blob.core.windows.net \
    --output table

# Check A record
az network private-dns record-set a list \
    --resource-group rg-ai-core \
    --zone-name privatelink.blob.core.windows.net \
    --output table
```

### Access Denied (403)

**Symptom**: Operations fail with 403 Forbidden

**Causes & Solutions**:

1. **Missing RBAC role**: Grant appropriate role
2. **RBAC propagation delay**: Wait up to 5 minutes
3. **Wrong auth mode**: Ensure `--auth-mode login` is used

```bash
# Check current assignments
az role assignment list \
    --scope /subscriptions/<sub>/resourceGroups/rg-ai-storage/providers/Microsoft.Storage/storageAccounts/stailab0117 \
    --output table
```

### Shared Key Error

**Symptom**: "Shared key authorization is not permitted"

**Cause**: Using connection string or storage key instead of RBAC

**Solution**: Use `--auth-mode login` with Azure CLI or managed identity for applications

## Related Documentation

- [Core Infrastructure](../core-infrastructure/README.md)
- [VPN Client Setup](../core-infrastructure/vpn-client-setup.md)
- [DNS Resolver Setup](../core-infrastructure/dns-resolver-setup.md)

## Files

| File | Description |
|------|-------------|
| `bicep/modules/storage-account.bicep` | Reusable storage module |
| `bicep/storage-infra/main.bicep` | Orchestration template |
| `bicep/storage-infra/main.parameters.json` | Dev parameters |
| `scripts/deploy-storage-infra.sh` | Deployment script |
| `scripts/validate-storage-infra.sh` | Validation script |
| `scripts/validate-storage-infra-dns.sh` | DNS validation |
| `scripts/cleanup-storage-infra.sh` | Cleanup script |
| `scripts/grant-storage-infra-roles.sh` | RBAC assignment |
