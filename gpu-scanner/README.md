# GPU Scanner

A standalone customer handoff for answering three different questions in an Azure subscription:
**catalog/access**, **vCPU quota**, and **capacity**. No lab deployment, networking changes, or VMs are required or created.

## Prerequisites and permissions

Use PowerShell 7+ (`pwsh`) and current Az modules:

```powershell
# From the gpu-scanner folder:
.\Test-GpuScannerPrerequisites.ps1                 # Check only, no installs or sign-in
.\Test-GpuScannerPrerequisites.ps1 -InstallMissing # Explicitly install missing modules
# Or provision modules directly:
Install-Module Az.Accounts,Az.Compute,Az.Resources -Scope CurrentUser -Repository PSGallery
```

Pre-flight checks all three modules and confirms they can be imported, then returns a `Ready` boolean
and per-module results. `-InstallMissing` installs only missing modules in **CurrentUser** scope using
PSGallery (including their dependencies); repository/provider trust prompts may appear. It does not
change repository trust, bypass publisher checks, require administrator access, or upgrade installed modules.
Use `-WhatIf` to preview installation or `-Confirm` to approve each install. Installation errors include
proxy/policy guidance. No Azure login, cloud calls, network tests, or permission checks happen in pre-flight.
Organizations can instead provision approved modules through their own distribution process.

Catalog and quota need subscription **Reader**. Spot placement scoring additionally needs
`Microsoft.Compute/locations/placementScores/spot/generate/action`; Microsoft's documented
**Compute Recommendations Role** supplies scoring access. Reader alone may get a 403, which is recorded
and does not prevent other regions/batches from being scanned.

Optional billable probes need **Contributor** (or equivalent permissions to create/delete resource groups
and capacity reservations). Azure enforces permissions, policy, supported SKU constraints, and quota.
The scanner does not assign roles, register providers, or change quota. Outbound access to Azure
authentication and management endpoints is needed; it makes no assumptions about customer VM networks.
Use an existing Azure cloud context; Spot scoring is documented for public Azure regions.

## Usage

```powershell
Set-Location .\gpu-scanner
.\Invoke-GpuScanner.ps1                          # Sign in, choose subscription, menu
.\Invoke-GpuScanner.ps1 -Stage All -SubscriptionId '00000000-0000-0000-0000-000000000000'
.\Invoke-GpuScanner.ps1 -Stage Catalog -GpuFilter H100
.\Invoke-GpuScanner.ps1 -Stage Quota -Regions eastus,westus3 -GpuFilter A100
.\Invoke-GpuScanner.ps1 -Stage Capacity -OutputPath 'C:\Temp\gpu-results'
```

Menu: **1 Catalog**, **2 Quota**, **3 Capacity**, **4 Run all + report**, **5 View last report**, **Q Quit**.
Without `-SubscriptionId`, automation uses the current subscription; interactive mode lists subscriptions.
Pre-authenticate unattended runs with `Connect-AzAccount` using the customer's preferred identity.
The tool disables context autosave for its process and passes the selected context explicitly to Az calls.
It never installs modules automatically; missing modules produce install guidance.

Default regions: `eastus`, `eastus2`, `centralus`, `northcentralus`, `southcentralus`, `westcentralus`,
`westus`, `westus2`, `westus3`. `-Regions` replaces these and can include other Azure region identifiers.
`-GpuFilter` is a case-insensitive literal substring of GPU type or SKU name.
GPU type is inferred from the SKU name (H100/H200/A100/MI300X/T4/A10/V100/L40S and older V100 series).
Unrecognized names remain **Unknown**, not a guessed GPU model. GPU count can be fractional.

### Spot request safeguards

The Spot Placement Score API is rate-limited per subscription (a 429 can block it for an hour), so Stage 3:

- **Scores only region/SKU pairs that are catalog `Available` and `QuotaOK`.** Other rows are `NotEligible`
  (no request sent); their verdict comes from catalog/quota (e.g. QuotaNeeded, RequestAccess). If nothing
  has quota, no Spot requests are sent. Request quota first.
- Prints the number of requests needed and sends at most `-MaxSpotRequests` (default 10, max 100). Rows
  beyond the cap are `Skipped`; narrow with `-GpuFilter`/`-Regions` or raise the cap.
- On HTTP 429, stops immediately and saves the retry time to `output\<subscriptionId>\spot-throttle.json`.
  Later runs send no Spot requests until that time passes (delete the file to override).

### Optional on-demand reservation probe

```powershell
.\Invoke-GpuScanner.ps1 -Stage Capacity -Regions eastus -GpuFilter H100 -ProbeCapacity
# Unattended explicit authorization:
.\Invoke-GpuScanner.ps1 -Stage All -Regions eastus -GpuFilter H100 -ProbeCapacity -Force
```

**Read-only is the default. `-Force` alone never enables writes.** With `-ProbeCapacity`, you must type
`PROBE` or pass `-Force` to authorize brief billing. For each available, quota-passing SKU advertising
`CapacityReservationSupported=True`, the scanner creates a unique temporary resource group, a regional
(nonzonal) capacity reservation group, and a quantity-one reservation. Unsupported or zone-restricted SKUs
are not probed. A reservation is not a VM and needs no VNet, image, disk, SSH key, or customer network access.

The entire temporary resource group is synchronously deleted in `finally`, including partially created
resources. **Cleanup failure is prominently warned, recorded with the resource group name, and stops further
billable probes.** Manually delete that group immediately if cleanup fails. Process termination, machine
failure, permission removal, locks, and Azure policy can prevent cleanup; no script can guarantee deletion
in those cases. Use the Azure resource group list (prefix `rg-gpu-probe-`, tag `purpose=gpu-scanner-temporary`)
to locate leftovers. Billing continues until the reservation is deleted.

## Output and cache

Each invocation writes `output\<subscriptionId>\<UTC timestamp>\` (or under `-OutputPath`):

- `catalog.json`: SKU specifications, region-specific restrictions/zones, request-access hints.
- `quota.json`: family and total regional limits/usage, remaining vCPUs, estimated number of VMs that fit.
- `capacity.json`: Spot scores, Spot quota availability, timestamps, optional probe and cleanup outcomes.
- `report.json` and `report.csv`: one row per region/SKU, including stage status/errors and verdict.

Only requested/prerequisite stages are produced. Stage JSON uses a versioned envelope with subscription,
regions, filter, UTC time, collection status/error, and a `Rows` array (including `[]` for empty results).
Catalog collection failure is persisted and stops dependent stages. Per-region quota errors and per-batch
Spot errors are warnings with Unknown/Forbidden/Error rows; other requests continue. **HTTP 429 (throttling)
is different: the scanner stops sending the remaining Spot requests for that run**, marks unscored rows
`RateLimited`, and reports Azure's retry delay (which can be an hour), since more calls can extend throttling.
Catalog and quota results remain valid. See [Spot request safeguards](#spot-request-safeguards). A successful empty
catalog is distinct from a failed collection; inspect the stage envelope when the report is empty.

Quota/capacity stages reuse the newest **successful matching catalog/quota cache no older than 30 minutes**,
or automatically collect prerequisites. Cache reuse preserves original observation time. Invalid files warn
and are ignored, and partial/failed files are not reused. `-Stage All` refreshes every stage. Billable probes refresh all prerequisites rather than using cached access/quota. Capacity is always
freshly requested; saved reports are historical. A non-interactive probe cancellation is recorded as a failed
capacity stage, without writes. Warnings/statuses, not just process exit codes, must be checked by automation.

The output is gitignored and can be sent back for review. It includes subscription identifiers, usage,
SKU restrictions, and Azure error details: review/redact it according to your organization's data policy.

## Interpreting results

| Verdict | Meaning |
| --- | --- |
| Deployable | An on-demand reservation succeeded at observation time and cleanup did not fail. Capacity was released; **not a future deployment guarantee**. |
| Likely | Catalog and regular quota pass, Spot score is High/Medium, and Spot quota is available. **Spot-only signal, not proof of on-demand capacity**. |
| QuotaNeeded | Family/total regional quota is zero/insufficient, or a probe reports a quota error. Use the report's portal quota link. |
| RequestAccess | A location-level `NotAvailableForSubscription` restriction requires requesting SKU access. |
| Restricted | Other location restriction or zone restrictions; inspect restriction details. The conservative region verdict does not mean every unrestricted zone is unavailable. |
| Unknown | Missing/denied data, low/stale/restricted Spot score, allocation/probe failure, or no capacity stage. Inspect status and errors. |

Quota is permission to consume resources, **not physical capacity**. Estimated regular VM count is
`floor(min(family remaining vCPUs, total regional remaining vCPUs) / SKU vCPUs)`, clamped to zero.
Usage is joined by `Name.Value` (family and `cores`), not localized display labels. Missing quotas remain
unknown rather than becoming zero. The calculation does not check subscription VM count limits, policy,
image/network compatibility, zonal allocation, or other deployment prerequisites.
Spot quota is separate from regular family/regional quota and is included in the Spot response.
Spot scores evaluate one nonzonal VM and are valid only when requested; High/Medium never guarantee
allocation or protection from eviction. Reservation failures can mean unsupported reservations, not unavailable
VM capacity. The tool never tries VM deployment as a fallback.

## Offline validation

```powershell
Install-Module Pester,PSScriptAnalyzer -Scope CurrentUser -Repository PSGallery
Invoke-Pester .\tests -Output Detailed
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error
```

Tests use Pester 5+ and mock Az commands with local signatures, so Az installation and live login are not
required. No live capacity or reservation tests run.

## Microsoft Learn references

Verified October 5, 2026. Stable Spot API **2025-06-05** is used (not the newer preview), with at most
**8 locations x 5 sizes** per request, `desiredSizes: [{ sku: ... }]`, `desiredCount: 1`,
`availabilityZones: false`, and the `placementScores` response array.

- [Spot placement score: limits, permissions, cost, caveats](https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/spot-placement-score)
- [Spot placement REST API](https://learn.microsoft.com/en-us/rest/api/recommenderrp/spot-placement-scores/post?view=rest-recommenderrp-2025-06-05)
- [Get-AzComputeResourceSku](https://learn.microsoft.com/en-us/powershell/module/az.compute/get-azcomputeresourcesku) (one unfiltered call, then local filtering)
- [Get-AzVMUsage](https://learn.microsoft.com/en-us/powershell/module/az.compute/get-azvmusage) (`-Location`, once per region)
- [New-AzCapacityReservationGroup](https://learn.microsoft.com/en-us/powershell/module/az.compute/new-azcapacityreservationgroup)
- [New-AzCapacityReservation](https://learn.microsoft.com/en-us/powershell/module/az.compute/new-azcapacityreservation) (`-ReservationGroupName`, `-CapacityToReserve`)
- [Remove-AzResourceGroup](https://learn.microsoft.com/en-us/powershell/module/az.resources/remove-azresourcegroup) (deletes the group and all its resources)
- [On-demand capacity reservations: support and billing](https://learn.microsoft.com/en-us/azure/virtual-machines/capacity-reservation-overview)
