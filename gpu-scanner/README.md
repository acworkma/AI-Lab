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

### Start the interactive menu

Open **PowerShell 7**, navigate to the `gpu-scanner` folder, and run:

```powershell
Set-Location .\gpu-scanner
.\Invoke-GpuScanner.ps1
```

If you are not already signed in to Azure PowerShell, the script prompts you to sign in.
It then lists your accessible subscriptions; enter the number for the subscription you want to scan.
Azure CLI's `az login` is separate from Azure PowerShell sign-in.

You will see:

```text
1 Catalog | 2 Quota | 3 Capacity | 4 Run all + report | 5 View last report | Q Quit
Select:
```

Type a menu number and press Enter. After the scan finishes, the menu returns so you can choose another
option. Type `Q` to exit. **All options are read-only unless you explicitly start with `-ProbeCapacity`.**
The script never installs modules automatically; if prerequisites are missing, follow the guidance above.

### What each menu option does

| Option | Question it answers | What happens |
| --- | --- | --- |
| **1 Catalog** | Which GPU VM sizes exist in these regions, and is my subscription allowed to use them? | Lists GPU specifications and subscription/zone restrictions. `Available` means no catalog restriction was found, **not** that quota or physical capacity is available. |
| **2 Quota** | Does my subscription have enough unused vCPU allowance for at least one of these VMs? | Checks both the GPU family's quota and the total regional quota. Reports the estimated number of VMs that fit within the remaining allowance. Zero or insufficient quota means you need a quota increase; quota is **not** physical capacity. |
| **3 Capacity** | Is there a current signal that Azure has room to allocate a matching GPU VM? | Requests Spot placement scores only for region/size pairs that passed catalog and quota checks. High/Medium scores are a **Spot-capacity signal**, not an on-demand deployment guarantee. No resources are created in default mode. |
| **4 Run all + report** | What is the combined picture for my subscription? | Refreshes Catalog, then Quota, then Capacity, and combines the results into a console summary and JSON/CSV reports. |
| **5 View last report** | What did the most recent scan find? | Displays the last saved report for this subscription under the selected output folder. It makes no new Azure checks; the results are historical. |
| **Q Quit** | How do I leave the menu? | Exits the script. |

**Suggested first run:** choose **4** for the full picture, or work through **1**, **2**, then **3** to
inspect each step separately. You do not have to run them in order: Quota automatically obtains Catalog,
and Capacity automatically obtains both Catalog and Quota when no suitable recent results are saved.
Every scan option (1-4) writes a report; options 1 and 2 leave later stages unchecked.
The script prints the output folder when each scan finishes.

If no sizes pass the catalog and quota checks, option 3 sends **no Spot requests**. Address the report's
access restrictions or quota shortfall before checking capacity again.

### Narrow the scan

Filters are chosen when you start the script and apply to every scan you run from that menu.
For example, to check only H100 sizes in two regions:

```powershell
.\Invoke-GpuScanner.ps1 -GpuFilter H100 -Regions eastus,westus3
```

To change the filters or subscription, quit and restart with different arguments.

| Argument | Default and meaning |
| --- | --- |
| `-SubscriptionId` | Uses the specified subscription instead of asking you to select one. With `-Stage` and no ID, uses the current Azure PowerShell subscription. |
| `-Regions` | Defaults to `eastus`, `eastus2`, `centralus`, `northcentralus`, `southcentralus`, `westcentralus`, `westus`, `westus2`, `westus3`. Replaces that list; use identifiers such as `eastus`, not display names such as `East US`. Other Azure regions may be supplied. |
| `-GpuFilter` | No filter by default. Matches a case-insensitive literal substring of the GPU type or SKU name, such as `H100` or `A100`. |
| `-OutputPath` | Saves results under the script's `output` folder by default. Use another folder to collect reports elsewhere. |
| `-MaxSpotRequests` | Limits Spot API requests per scan to 10 by default (allowed range 1-100). See the safeguards below. |

GPU type is inferred from the SKU name (H100/H200/A100/MI300X/T4/A10/V100/L40S and older V100 series).
Unrecognized types remain **Unknown** rather than being guessed. GPU count can be fractional.

### Run a stage without the menu

Add `-Stage Catalog`, `-Stage Quota`, `-Stage Capacity`, or `-Stage All` to run once and exit.
These correspond to menu options 1-4. Run the examples below from the `gpu-scanner` folder:

```powershell
# Full scan of a specific subscription; replace the example ID with your subscription ID.
.\Invoke-GpuScanner.ps1 -Stage All -SubscriptionId '00000000-0000-0000-0000-000000000000'

# Catalog only for H100 sizes, using the current Azure PowerShell subscription.
.\Invoke-GpuScanner.ps1 -Stage Catalog -GpuFilter H100

# Quota for A100 sizes in two regions; obtains Catalog first if needed.
.\Invoke-GpuScanner.ps1 -Stage Quota -Regions eastus,westus3 -GpuFilter A100

# Capacity signal for H100 sizes; obtains Catalog and Quota first if needed.
.\Invoke-GpuScanner.ps1 -Stage Capacity -GpuFilter H100 -OutputPath 'C:\Temp\gpu-results'
```

For unattended runs, pre-authenticate with `Connect-AzAccount` using your organization's preferred identity
and specify `-SubscriptionId` to avoid checking the wrong subscription. `-Stage` bypasses the menu, but
does not bypass sign-in if there is no authenticated context. The script disables context autosave for its
process and passes the selected context explicitly to Azure commands.

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
