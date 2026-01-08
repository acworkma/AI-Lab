# Storage Module Validation Suite

This directory contains validation tests for the Private Storage Account with CMK module.

## Overview

The validation suite verifies:

- **Template Syntax**: Bicep compilation succeeds
- **Parameter Validation**: Required parameters present and valid
- **What-If Analysis**: Deployment would succeed
- **Deployed Resources**: CMK, private endpoint, DNS, tags all configured correctly
- **Data Operations**: Create, upload, list, download, delete work via VPN
- **Idempotency**: Redeploys produce no changes

## Running Validations

### Quick Start (All Tests)

```bash
# Template validation only
./scripts/validate-storage.sh

# Deployed resource validation
./scripts/validate-storage.sh --deployed

# DNS resolution validation
./scripts/validate-storage-dns.sh

# Data operations validation
./scripts/validate-storage-ops.sh

# Idempotency check (requires prior deployment)
./scripts/what-if-storage.sh --idempotent
```

### Individual Validations

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `validate-storage.sh` | Template syntax + what-if | Before deployment |
| `validate-storage.sh --deployed` | Full deployed resource checks | After deployment |
| `validate-storage-dns.sh` | DNS zone, A record, latency | After deployment |
| `validate-storage-ops.sh` | CRUD operations test | After RBAC assignment |
| `what-if-storage.sh --idempotent` | Redeploy produces no changes | Anytime after deploy |

## Validation Details

### Pre-Deployment Checks

```bash
./scripts/validate-storage.sh
```

Validates:
- ✓ Bicep template syntax (no compilation errors)
- ✓ Parameter file JSON syntax
- ✓ Required parameters present (storageAccountName, keyVaultName, etc.)
- ✓ What-if deployment would succeed
- ✓ Core infrastructure dependencies exist

### Post-Deployment Checks

```bash
./scripts/validate-storage.sh --deployed
```

Validates:
- ✓ **SR-002**: CMK encryption enabled (keySource: Microsoft.Keyvault)
- ✓ **SR-003**: Public network access disabled
- ✓ **SR-003**: Blob public access disabled
- ✓ **SR-004**: Private endpoint exists and approved
- ✓ **SR-005**: DNS resolves to private IP
- ✓ **Constitution**: Required tags present (project, environment, component, deployedBy)

### DNS Validation (NFR-003)

```bash
./scripts/validate-storage-dns.sh
```

Validates:
- ✓ Private DNS zone exists in core resource group
- ✓ VNet link configured
- ✓ A record for storage account exists
- ✓ A record points to private IP (10.x.x.x)
- ✓ DNS query time < 100ms

### Data Operations (End-to-End)

```bash
./scripts/validate-storage-ops.sh
```

Runs complete CRUD test:
1. Create container
2. Upload blob
3. List blobs (verify presence)
4. Download blob
5. Verify content matches
6. Delete blob
7. Cleanup container

**Requires**: VPN connection + "Storage Blob Data Contributor" role

### Idempotency Check

```bash
./scripts/what-if-storage.sh --idempotent
```

Validates:
- ✓ Storage account exists (already deployed)
- ✓ What-if shows no changes (NoChange)
- ✓ No Create, Modify, or Delete operations

## CI/CD Integration

### GitHub Actions Example

```yaml
jobs:
  validate-storage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Validate Template
        run: ./scripts/validate-storage.sh
      
      - name: Deploy
        run: ./scripts/deploy-storage.sh --auto-approve
      
      - name: Validate Deployment
        run: ./scripts/validate-storage.sh --deployed
      
      - name: Validate DNS
        run: ./scripts/validate-storage-dns.sh
      
      - name: Check Idempotency
        run: ./scripts/what-if-storage.sh --idempotent
```

## Expected Outputs

### Successful Validation

```
==============================================
 Validate Private Storage Account with CMK
==============================================

Parameter File: bicep/storage/main.parameters.json
Mode: Deployed Resources

[✓ PASS] Template syntax valid
[✓ PASS] Parameter 'storageAccountName' present: stailab001
[✓ PASS] Parameter 'keyVaultName' present: kv-ai-core
[✓ PASS] Parameter 'subnetName' present: snet-private-endpoints
[✓ PASS] Parameter 'vnetName' present: vnet-ai-sharedservices

--- Security Requirements ---
[✓ PASS] SR-002: CMK encryption enabled (source: Microsoft.Keyvault)
[✓ PASS] SR-002: Key Vault URI configured
[✓ PASS] SR-002: User-assigned identity configured for CMK
[✓ PASS] SR-003: Public network access disabled
[✓ PASS] SR-003: Blob public access disabled
[✓ PASS] SR-004: Private endpoint exists
[✓ PASS] SR-004: Private endpoint connection approved
[✓ PASS] SR-004: Private endpoint IP assigned: 10.1.4.5
[✓ PASS] SR-005: DNS resolves to private endpoint IP

--- Constitution Compliance ---
[✓ PASS] Tag 'project' present: ai-lab
[✓ PASS] Tag 'environment' present: dev
[✓ PASS] Tag 'component' present: storage
[✓ PASS] Tag 'deployedBy' present: azure-cli

==============================================
[✓ PASS] All validations passed!
```

### Failed Validation

```
[✗ FAIL] SR-002: CMK encryption not configured (source: Microsoft.Storage)
[✗ FAIL] SR-003: Public network access not disabled (status: Enabled)
[✗ FAIL] Required tag missing: component

==============================================
[✗ FAIL] Some validations failed - review output above
```

## Troubleshooting

### "DNS resolution failed (VPN may not be connected)"

**Cause**: VPN not connected or DNS server not configured

**Solution**:
1. Connect to VPN
2. Configure DNS server to 10.1.0.68
3. Re-run validation

### "Storage account not found"

**Cause**: Storage not deployed yet

**Solution**:
1. Run `./scripts/deploy-storage.sh` first
2. Then run validations

### "AuthorizationPermissionMismatch"

**Cause**: Missing data plane RBAC role

**Solution**:
1. Run `./scripts/grant-storage-roles.sh --user your@email.com`
2. Retry operation

## Related Documentation

- [Storage Module](../../docs/storage/README.md)
- [Feature Specification](../../specs/005-storage-cmk/spec.md)
- [Deployment Contract](../../specs/005-storage-cmk/contracts/deployment-contract.md)
