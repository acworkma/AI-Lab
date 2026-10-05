#Requires -Version 7.0

$script:DefaultRegions = @('eastus', 'eastus2', 'centralus', 'northcentralus', 'southcentralus', 'westcentralus', 'westus', 'westus2', 'westus3')
$script:ReportColumns = @(
    'Region', 'SKU', 'GpuType', 'GPUs', 'VCPUs', 'Family', 'MemoryGB', 'Zones', 'RestrictedZones',
    'CatalogStatus', 'CatalogHint', 'QuotaStatus', 'FamilyLimit', 'FamilyUsed', 'FamilyFree',
    'TotalRegionalFree', 'VMsFit', 'QuotaHint', 'QuotaError', 'CapacityStatus', 'SpotScore',
    'SpotQuotaAvailable', 'ProbeStatus', 'CleanupStatus', 'ProbeResourceGroup', 'CapacityError',
    'ProbeError', 'ObservedAtUtc', 'Verdict'
)

function Get-GpuScannerRegion {
    $script:DefaultRegions
}

function Get-GpuType {
    param([string]$Name)
    if ($Name -match '(?i)(MI300X|H200|H100|A100|L40S|V100|T4|A10)') { return $Matches[1].ToUpperInvariant() }
    # Older Azure size names encode the series rather than the GPU model.
    switch -Regex ($Name) {
        '^Standard_NC.*_v3$|^Standard_ND.*_v2$' { return 'V100' }
        '^Standard_NV.*ads_A10_v5$' { return 'A10' }
        '^Standard_NC.*as_T4_v3$' { return 'T4' }
        default { return 'Unknown' }
    }
}

function Get-GpuErrorStatus {
    param([string]$Message)
    switch -Regex ($Message) {
        '429|TooManyRequests|maximum number of requests' { return 'RateLimited' }
        '403|Forbidden|AuthorizationFailed' { return 'Forbidden' }
        'AllocationFailed|ZonalAllocationFailed' { return 'AllocationFailed' }
        'Quota|OperationNotAllowed.*(core|limit)' { return 'QuotaError' }
        'NotSupported|Unsupported|InvalidParameter' { return 'Unsupported' }
        default { return 'Error' }
    }
}

function Get-GpuCatalog {
    [CmdletBinding()]
    param([string[]]$Regions = $script:DefaultRegions, [string]$GpuFilter, [object]$Context)
    $skus = @(Get-AzComputeResourceSku -DefaultProfile $Context -ErrorAction Stop)
    foreach ($sku in $skus) {
        if ($sku.ResourceType -ne 'virtualMachines') { continue }
        $caps = @{}
        foreach ($cap in $sku.Capabilities) { $caps[$cap.Name] = $cap.Value }
        if (-not $caps.ContainsKey('GPUs') -or [double]$caps['GPUs'] -le 0) { continue }
        $gpuType = Get-GpuType $sku.Name
        if ($GpuFilter -and $gpuType.IndexOf($GpuFilter, [StringComparison]::OrdinalIgnoreCase) -lt 0 -and
            $sku.Name.IndexOf($GpuFilter, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        foreach ($region in $Regions) {
            if ($region -notin $sku.Locations) { continue }
            $info = @($sku.LocationInfo | Where-Object Location -EQ $region)
            $restrictions = @($sku.Restrictions | Where-Object {
                $locations = @($_.RestrictionInfo.Locations) + @($_.Values)
                $region -in $locations -or ($_.Type -eq 'Location' -and $locations.Count -eq 0)
            })
            $locationRestrictions = @($restrictions | Where-Object Type -EQ 'Location')
            $zoneRestrictions = @($restrictions | Where-Object Type -EQ 'Zone')
            $status = if ($locationRestrictions.Count) { 'Restricted' } elseif ($zoneRestrictions.Count) { 'ZoneRestricted' } else { 'Available' }
            [pscustomobject]@{
                Region = $region; SKU = $sku.Name; Family = $sku.Family; Size = $sku.Size
                VCPUs = [int]$caps['vCPUs']; GPUs = [double]$caps['GPUs']; GpuType = $gpuType
                MemoryGB = [double]$caps['MemoryGB']; Zones = @($info | ForEach-Object { $_.Zones } | Sort-Object -Unique)
                RestrictedZones = @($zoneRestrictions | ForEach-Object { $_.RestrictionInfo.Zones } | Sort-Object -Unique)
                Restrictions = $restrictions; CatalogStatus = $status
                CatalogHint = if ('NotAvailableForSubscription' -in $restrictions.ReasonCode) { 'Request access' } else { ($restrictions.ReasonCode | Sort-Object -Unique) -join '; ' }
                CapacityReservationSupported = $caps['CapacityReservationSupported'] -eq 'True'
            }
        }
    }
}

function Get-GpuQuota {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Catalog, [object]$Context)
    foreach ($region in @($Catalog.Region | Sort-Object -Unique)) {
        $usage = @(); $regionError = ''
        try { $usage = @(Get-AzVMUsage -Location $region -DefaultProfile $Context -ErrorAction Stop) }
        catch { $regionError = $_.Exception.Message; Write-Warning "Quota ${region}: $regionError" }
        foreach ($sku in @($Catalog | Where-Object Region -EQ $region)) {
            $errorMessage = $regionError
            $family = @($usage | Where-Object { $_.Name.Value -eq $sku.Family }) | Select-Object -First 1
            $total = @($usage | Where-Object { $_.Name.Value -eq 'cores' }) | Select-Object -First 1
            $status = 'Unknown'; $free = $null; $totalFree = $null; $fit = $null
            if ($family -and $total -and $sku.VCPUs -gt 0) {
                $free = [Math]::Max(0, $family.Limit - $family.CurrentValue)
                $totalFree = [Math]::Max(0, $total.Limit - $total.CurrentValue)
                $fit = [int][Math]::Floor([Math]::Min($free, $totalFree) / $sku.VCPUs)
                $status = if ($family.Limit -eq 0 -or $total.Limit -eq 0) { 'NoQuota' } elseif ($fit -lt 1) { 'Insufficient' } else { 'QuotaOK' }
            } elseif ($errorMessage) { $status = Get-GpuErrorStatus $errorMessage }
            else { $errorMessage = 'Missing family/cores usage or invalid vCPU count.'; Write-Warning "Quota $region/$($sku.SKU): $errorMessage" }
            [pscustomobject]@{
                Region = $region; SKU = $sku.SKU; Family = $sku.Family
                Limit = $family.Limit; Used = $family.CurrentValue; Free = $free
                TotalRegionalLimit = $total.Limit; TotalRegionalUsed = $total.CurrentValue
                TotalRegionalFree = $totalFree; VMsFit = $fit; QuotaStatus = $status; Error = $errorMessage
                QuotaHint = 'Request quota: https://portal.azure.com/#view/Microsoft_Azure_Capacity/QuotaMenuBlade/~/myQuotas'
            }
        }
    }
}

function Invoke-GpuReservationProbe {
    [CmdletBinding()]
    param([object]$Sku, [object]$Context)
    $rg = "rg-gpu-probe-$([guid]::NewGuid().ToString('N'))"
    $result = [pscustomobject]@{ ProbeStatus = 'Unknown'; ProbeError = ''; ResourceGroup = $rg; CleanupStatus = 'Pending' }
    try {
        New-AzResourceGroup -Name $rg -Location $Sku.Region -Tag @{ purpose = 'gpu-scanner-temporary' } -DefaultProfile $Context -ErrorAction Stop | Out-Null
        New-AzCapacityReservationGroup -ResourceGroupName $rg -Name 'gpu-probe' -Location $Sku.Region -DefaultProfile $Context -ErrorAction Stop | Out-Null
        New-AzCapacityReservation -ResourceGroupName $rg -ReservationGroupName 'gpu-probe' -Name 'gpu-probe' -Location $Sku.Region -Sku $Sku.SKU -CapacityToReserve 1 -DefaultProfile $Context -ErrorAction Stop | Out-Null
        $result.ProbeStatus = 'Succeeded'
    } catch {
        $result.ProbeError = $_.Exception.Message
        $result.ProbeStatus = Get-GpuErrorStatus $result.ProbeError
        Write-Warning "Probe $($Sku.Region)/$($Sku.SKU): $($result.ProbeError)"
    } finally {
        # Delete the uniquely named group, including any partially created reservation.
        try {
            $removed = Remove-AzResourceGroup -Name $rg -Force -DefaultProfile $Context -ErrorAction Stop
            if ($removed -eq $false) { throw 'Azure did not confirm resource group deletion.' }
            $result.CleanupStatus = 'Deleted'
        } catch {
            if ($_.Exception.Message -match 'ResourceGroupNotFound|ResourceNotFound|404') { $result.CleanupStatus = 'NotFound' }
            else {
                $result.CleanupStatus = 'Failed'
                $result.ProbeError += " Cleanup: $($_.Exception.Message)"
                Write-Warning "CLEANUP FAILED: manually delete $rg in subscription $($Context.Subscription.Id). Billing may continue. $($_.Exception.Message)"
            }
        }
    }
    $result
}

function Get-GpuCapacity {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Catalog, [AllowEmptyCollection()][object[]]$Quota,
        [string]$SubscriptionId, [object]$Context, [switch]$ProbeCapacity, [switch]$Force
    )
    if ($ProbeCapacity) {
        Write-Warning 'Probes require Contributor, reserve one VM worth of capacity, and incur brief billing. No VMs are deployed.'
        if (-not $Force -and (Read-Host 'Type PROBE to authorize temporary billable reservations') -cne 'PROBE') {
            throw 'Capacity probe cancelled. Use read-only capacity mode instead.'
        }
    }
    $rows = @($Catalog | ForEach-Object {
        [pscustomobject]@{
            Region = $_.Region; SKU = $_.SKU; SpotScore = 'Unknown'; SpotQuotaAvailable = $null
            CapacityStatus = 'Unknown'; Error = ''; ObservedAtUtc = [datetime]::UtcNow.ToString('o')
            ProbeStatus = if ($ProbeCapacity) { 'NotAttempted' } else { 'NotRequested' }
            ProbeError = ''; ResourceGroup = ''; CleanupStatus = 'NotApplicable'
            Signal = 'Spot capacity recommendation for one nonzonal VM; not an on-demand guarantee.'
        }
    })
    $regions = @($Catalog.Region | Sort-Object -Unique)
    $sizes = @($Catalog.SKU | Sort-Object -Unique)
    $rateLimitMessage = ''
    for ($r = 0; $r -lt $regions.Count; $r += 8) {
        $regionBatch = @($regions[$r..([Math]::Min($r + 7, $regions.Count - 1))])
        for ($s = 0; $s -lt $sizes.Count; $s += 5) {
            $sizeBatch = @($sizes[$s..([Math]::Min($s + 4, $sizes.Count - 1))])
            $batchRows = @($rows | Where-Object { $_.Region -in $regionBatch -and $_.SKU -in $sizeBatch })
            if ($rateLimitMessage) {
                # Further calls during throttling can extend the retry window.
                foreach ($row in $batchRows) { $row.CapacityStatus = 'RateLimited'; $row.Error = "Skipped after throttling. $rateLimitMessage" }
                continue
            }
            $payload = @{
                availabilityZones = $false; desiredCount = 1; desiredLocations = $regionBatch
                desiredSizes = @($sizeBatch | ForEach-Object { @{ sku = $_ } })
            } | ConvertTo-Json -Depth 5
            try {
                $path = "/subscriptions/$SubscriptionId/providers/Microsoft.Compute/locations/$($regionBatch[0])/placementScores/spot/generate?api-version=2025-06-05"
                $response = Invoke-AzRestMethod -Path $path -Method POST -Payload $payload -DefaultProfile $Context -ErrorAction Stop
                if ($response.StatusCode -eq 429) {
                    $retrySeconds = $null
                    $retryHeader = $response.Headers.RetryAfter
                    if ($retryHeader.Delta) { $retrySeconds = [int]$retryHeader.Delta.TotalSeconds }
                    elseif ("$($response.Content)" -match 'after (\d+) seconds') { $retrySeconds = [int]$Matches[1] }
                    $retryText = if ($retrySeconds) {
                        "Retry after about $([Math]::Ceiling($retrySeconds / 60)) minute(s) (~$([datetime]::Now.AddSeconds($retrySeconds).ToString('t')) local)."
                    } else { 'Retry later.' }
                    $rateLimitMessage = "HTTP 429 from Spot Placement Score API. $retryText Use -GpuFilter or -Regions to reduce request count."
                    throw $rateLimitMessage
                }
                if ($response.StatusCode -ne 200) { throw "HTTP $($response.StatusCode): $($response.Content)" }
                $scores = ($response.Content | ConvertFrom-Json -ErrorAction Stop).placementScores
                foreach ($row in $batchRows) {
                    $score = $scores | Where-Object { $_.region -eq $row.Region -and $_.sku -eq $row.SKU } | Select-Object -First 1
                    if ($score) {
                        $row.SpotScore = $score.score; $row.SpotQuotaAvailable = $score.isQuotaAvailable
                        $row.CapacityStatus = 'SpotSignal'
                    } else { $row.Error = 'No matching Spot score returned.'; Write-Warning "$($row.Region)/$($row.SKU): $($row.Error)" }
                }
            } catch {
                if (-not $rateLimitMessage -and (Get-GpuErrorStatus $_.Exception.Message) -eq 'RateLimited') {
                    $rateLimitMessage = "Spot Placement Score API throttled: $($_.Exception.Message) Use -GpuFilter or -Regions to reduce request count."
                }
                Write-Warning "Spot placement batch: $($_.Exception.Message)"
                if ($rateLimitMessage) { Write-Warning 'Stopping remaining Spot requests for this run; catalog and quota results remain valid.' }
                foreach ($row in $batchRows) { $row.CapacityStatus = Get-GpuErrorStatus $_.Exception.Message; $row.Error = $_.Exception.Message }
            }
        }
    }
    if ($ProbeCapacity) {
        foreach ($sku in $Catalog) {
            $row = $rows | Where-Object { $_.Region -eq $sku.Region -and $_.SKU -eq $sku.SKU } | Select-Object -First 1
            $q = $Quota | Where-Object { $_.Region -eq $sku.Region -and $_.SKU -eq $sku.SKU } | Select-Object -First 1
            if ($sku.CatalogStatus -ne 'Available' -or $q.QuotaStatus -ne 'QuotaOK') { $row.ProbeStatus = 'SkippedPrerequisites'; continue }
            if (-not $sku.CapacityReservationSupported) { $row.ProbeStatus = 'Unsupported'; continue }
            $probe = Invoke-GpuReservationProbe -Sku $sku -Context $Context
            foreach ($property in @('ProbeStatus', 'ProbeError', 'ResourceGroup', 'CleanupStatus')) { $row.$property = $probe.$property }
            if ($probe.CleanupStatus -eq 'Failed') {
                Write-Warning 'Stopping further billable probes because cleanup failed.'
                break
            }
        }
    }
    $rows
}

function Get-GpuReport {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Catalog, [AllowEmptyCollection()][object[]]$Quota, [AllowEmptyCollection()][object[]]$Capacity)
    foreach ($sku in $Catalog) {
        $q = $Quota | Where-Object { $_.Region -eq $sku.Region -and $_.SKU -eq $sku.SKU } | Select-Object -First 1
        $c = $Capacity | Where-Object { $_.Region -eq $sku.Region -and $_.SKU -eq $sku.SKU } | Select-Object -First 1
        $verdict = 'Unknown'
        if ($sku.CatalogStatus -eq 'Restricted') {
            $verdict = if ($sku.CatalogHint -eq 'Request access') { 'RequestAccess' } else { 'Restricted' }
        } elseif ($sku.CatalogStatus -eq 'ZoneRestricted') { $verdict = 'Restricted' }
        elseif ($q.QuotaStatus -in @('NoQuota', 'Insufficient') -or $c.ProbeStatus -eq 'QuotaError') { $verdict = 'QuotaNeeded' }
        elseif ($q.QuotaStatus -eq 'QuotaOK' -and $c.CleanupStatus -ne 'Failed') {
            if ($c.ProbeStatus -eq 'Succeeded') { $verdict = 'Deployable' }
            elseif ($c.ProbeStatus -in @('NotRequested', 'Unsupported') -and $c.SpotScore -in @('High', 'Medium') -and $c.SpotQuotaAvailable -eq $true) { $verdict = 'Likely' }
        }
        [pscustomobject]@{
            Region = $sku.Region; SKU = $sku.SKU; GpuType = $sku.GpuType; GPUs = $sku.GPUs; VCPUs = $sku.VCPUs
            Family = $sku.Family; MemoryGB = $sku.MemoryGB; Zones = $sku.Zones -join ';'; RestrictedZones = $sku.RestrictedZones -join ';'
            CatalogStatus = $sku.CatalogStatus; CatalogHint = $sku.CatalogHint; QuotaStatus = $q.QuotaStatus
            FamilyLimit = $q.Limit; FamilyUsed = $q.Used; FamilyFree = $q.Free; TotalRegionalFree = $q.TotalRegionalFree
            VMsFit = $q.VMsFit; QuotaHint = $q.QuotaHint; QuotaError = $q.Error
            CapacityStatus = $c.CapacityStatus; SpotScore = $c.SpotScore; SpotQuotaAvailable = $c.SpotQuotaAvailable
            ProbeStatus = $c.ProbeStatus; CleanupStatus = $c.CleanupStatus; ProbeResourceGroup = $c.ResourceGroup
            CapacityError = $c.Error; ProbeError = $c.ProbeError; ObservedAtUtc = $c.ObservedAtUtc; Verdict = $verdict
        }
    }
}

function Show-GpuReport {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Report)
    if (-not $Report.Count) { Write-Host 'No matching GPU SKUs. See stage JSON for collection status.'; return }
    foreach ($group in $Report | Group-Object GpuType | Sort-Object Name) {
        Write-Host "`nGPU: $($group.Name)" -ForegroundColor Cyan
        Write-Host ('{0,-18} {1,-42} {2,-18} {3,-16} {4,-10} {5}' -f 'Region', 'SKU', 'Catalog', 'Quota', 'Spot', 'Verdict')
        foreach ($row in $group.Group | Sort-Object Region, SKU) {
            $color = switch ($row.Verdict) { 'Deployable' { 'Green' } 'Likely' { 'Green' } 'Unknown' { 'Gray' } default { 'Yellow' } }
            Write-Host ('{0,-18} {1,-42} {2,-18} {3,-16} {4,-10} {5}' -f $row.Region, $row.SKU, $row.CatalogStatus, $row.QuotaStatus, $row.SpotScore, $row.Verdict) -ForegroundColor $color
        }
    }
    Write-Host 'Spot scores are not on-demand guarantees. Probe capacity was released; all observations are point-in-time.'
}

function Save-GpuStage {
    [CmdletBinding()]
    param([string]$Path, [string]$SubscriptionId, [string[]]$Regions, [string]$GpuFilter,
        [AllowEmptyCollection()][object[]]$Rows, [string]$Status = 'Succeeded', [string]$ErrorMessage = '')
    @{
        SchemaVersion = 1; SubscriptionId = $SubscriptionId; Regions = @($Regions | Sort-Object -Unique)
        GpuFilter = $GpuFilter; GeneratedAtUtc = [datetime]::UtcNow.ToString('o')
        Status = $Status; Error = $ErrorMessage; Rows = @($Rows)
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8 -ErrorAction Stop
}

function Read-GpuCache {
    [CmdletBinding()]
    param([string]$Root, [string]$FileName, [string]$SubscriptionId, [string[]]$Regions, [string]$GpuFilter)
    if (-not (Test-Path -LiteralPath $Root)) { return }
    foreach ($directory in Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name -Descending) {
        $path = Join-Path $directory.FullName $FileName
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $cache = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $age = [datetime]::UtcNow - ([datetime]$cache.GeneratedAtUtc).ToUniversalTime()
            if ($cache.SchemaVersion -eq 1 -and $cache.Status -eq 'Succeeded' -and $cache.SubscriptionId -eq $SubscriptionId -and
                $cache.GpuFilter -eq $GpuFilter -and ($cache.Regions -join ',') -eq (($Regions | Sort-Object -Unique) -join ',') -and
                $age.TotalMinutes -ge 0 -and $age.TotalMinutes -le 30) { return $cache }
        } catch { Write-Warning "Ignoring invalid cache ${path}: $($_.Exception.Message)" }
    }
}

function Invoke-GpuScan {
    [CmdletBinding()]
    param(
        [ValidateSet('Catalog', 'Quota', 'Capacity', 'All')][string]$Stage,
        [string]$SubscriptionId, [string[]]$Regions = $script:DefaultRegions, [string]$GpuFilter,
        [string]$OutputPath, [object]$Context, [switch]$ProbeCapacity, [switch]$Force
    )
    $root = Join-Path $OutputPath $SubscriptionId
    $directory = Join-Path $root ([datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    $catalog = @(); $quota = @(); $capacity = @()
    foreach ($name in @('Catalog', 'Quota', 'Capacity')) {
        if ($Stage -eq 'Catalog' -and $name -ne 'Catalog') { break }
        if ($Stage -eq 'Quota' -and $name -eq 'Capacity') { break }
        $file = "$($name.ToLowerInvariant()).json"
        $cache = if (-not $ProbeCapacity -and $Stage -ne 'All' -and $Stage -ne $name) {
            Read-GpuCache -Root $root -FileName $file -SubscriptionId $SubscriptionId -Regions $Regions -GpuFilter $GpuFilter
        }
        $status = 'Succeeded'; $errorMessage = ''
        try {
            $rows = if ($cache) { @($cache.Rows) } else {
                switch ($name) {
                    'Catalog' { @(Get-GpuCatalog -Regions $Regions -GpuFilter $GpuFilter -Context $Context) }
                    'Quota' { @(Get-GpuQuota -Catalog $catalog -Context $Context) }
                    'Capacity' { @(Get-GpuCapacity -Catalog $catalog -Quota $quota -SubscriptionId $SubscriptionId -Context $Context -ProbeCapacity:$ProbeCapacity -Force:$Force) }
                }
            }
            $rows = @($rows)
            if ($name -eq 'Quota' -and @($rows | Where-Object QuotaStatus -In @('Unknown', 'Forbidden', 'Error')).Count) { $status = 'Partial' }
            if ($name -eq 'Capacity' -and @($rows | Where-Object {
                $_.CapacityStatus -ne 'SpotSignal' -or $_.CleanupStatus -eq 'Failed' -or $_.ProbeStatus -in @('NotAttempted', 'Error', 'Forbidden', 'QuotaError', 'AllocationFailed')
            }).Count) { $status = 'Partial' }
        } catch {
            $rows = @(); $status = 'Failed'; $errorMessage = $_.Exception.Message
            Write-Warning "${name}: $errorMessage"
        }
        $path = Join-Path $directory $file
        if ($cache) {
            # Preserve the observation time; copying a cache must not extend its lifetime.
            $cache | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8 -ErrorAction Stop
        } else { Save-GpuStage -Path $path -SubscriptionId $SubscriptionId -Regions $Regions -GpuFilter $GpuFilter -Rows $rows -Status $status -ErrorMessage $errorMessage }
        switch ($name) { 'Catalog' { $catalog = $rows } 'Quota' { $quota = $rows } 'Capacity' { $capacity = $rows } }
        if ($status -eq 'Failed') { break }
    }
    $report = @(Get-GpuReport -Catalog $catalog -Quota $quota -Capacity $capacity)
    ConvertTo-Json -InputObject $report -Depth 10 | Set-Content -LiteralPath (Join-Path $directory 'report.json') -Encoding utf8 -ErrorAction Stop
    if ($report.Count) {
        $report | Select-Object -Property $script:ReportColumns |
            Export-Csv -LiteralPath (Join-Path $directory 'report.csv') -NoTypeInformation -Encoding utf8 -ErrorAction Stop
    } else {
        ($script:ReportColumns | ForEach-Object { '"' + $_ + '"' }) -join ',' |
            Set-Content -LiteralPath (Join-Path $directory 'report.csv') -Encoding utf8 -ErrorAction Stop
    }
    Show-GpuReport -Report $report
    Write-Information "Output: $directory" -InformationAction Continue
    [pscustomobject]@{ OutputDirectory = $directory; Report = $report }
}

Export-ModuleMember -Function Get-GpuScannerRegion, Get-GpuCatalog, Get-GpuQuota, Get-GpuCapacity, Get-GpuReport, Show-GpuReport, Save-GpuStage, Read-GpuCache, Invoke-GpuScan
