#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Local Az signatures are consumed by Pester mocks.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture factories only create in-memory objects.')]
param()

BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '..\GpuScanner.psm1') -Force
}

BeforeAll {
    # Local signatures let Pester mock Az without installing Azure modules or signing in.
    function global:Get-AzComputeResourceSku { [CmdletBinding()]param($DefaultProfile) }
    function global:Get-AzVMUsage { [CmdletBinding()]param($Location, $DefaultProfile) }
    function global:Invoke-AzRestMethod { [CmdletBinding()]param($Path, $Method, $Payload, $DefaultProfile) }
    function global:New-AzResourceGroup { [CmdletBinding()]param($Name, $Location, $Tag, $DefaultProfile) }
    function global:New-AzCapacityReservationGroup { [CmdletBinding()]param($ResourceGroupName, $Name, $Location, $DefaultProfile) }
    function global:New-AzCapacityReservation { [CmdletBinding()]param($ResourceGroupName, $ReservationGroupName, $Name, $Location, $Sku, $CapacityToReserve, $DefaultProfile) }
    function global:Remove-AzResourceGroup { [CmdletBinding()]param($Name, [switch]$Force, $DefaultProfile) }
    function global:Disable-AzContextAutosave { [CmdletBinding()]param($Scope) }
    function global:Get-AzContext { [CmdletBinding()]param() }
    function global:Connect-AzAccount { [CmdletBinding()]param($Scope) }
    function global:Set-AzContext { [CmdletBinding()]param($SubscriptionId, $Scope) }
    function global:Get-AzSubscription { [CmdletBinding()]param() }
}

AfterAll {
    Remove-Module GpuScanner
    foreach ($command in @('Get-AzComputeResourceSku', 'Get-AzVMUsage', 'Invoke-AzRestMethod',
        'New-AzResourceGroup', 'New-AzCapacityReservationGroup', 'New-AzCapacityReservation', 'Remove-AzResourceGroup',
        'Disable-AzContextAutosave', 'Get-AzContext', 'Connect-AzAccount', 'Set-AzContext', 'Get-AzSubscription')) {
        Remove-Item -LiteralPath "Function:\global:$command"
    }
}

Describe 'GPU scanner offline behavior' {
    InModuleScope GpuScanner {
        BeforeAll {
            function New-TestSku {
                param($Name = 'Standard_NC40ads_H100_v5', $Family = 'standardNCH100Family', $Locations = @('eastus', 'westus3'))
                [pscustomobject]@{
                    Name = $Name; Family = $Family; Size = 'NC40ads_H100_v5'; ResourceType = 'virtualMachines'
                    Locations = $Locations; LocationInfo = @($Locations | ForEach-Object { @{ Location = $_; Zones = @('1', '2', '3') } })
                    Restrictions = @()
                    Capabilities = @(
                        @{ Name = 'GPUs'; Value = '1' }, @{ Name = 'vCPUs'; Value = '40' }
                        @{ Name = 'MemoryGB'; Value = '320' }, @{ Name = 'CapacityReservationSupported'; Value = 'True' }
                    )
                }
            }
            function New-TestUsage {
                param($FamilyLimit = 200, $FamilyUsed = 40, $TotalLimit = 100, $TotalUsed = 20)
                @(
                    @{ Name = @{ Value = 'standardNCH100Family' }; Limit = $FamilyLimit; CurrentValue = $FamilyUsed }
                    @{ Name = @{ Value = 'cores' }; Limit = $TotalLimit; CurrentValue = $TotalUsed }
                )
            }
        }
        BeforeEach {
            $script:context = [pscustomobject]@{ Subscription = @{ Id = '00000000-0000-0000-0000-000000000001' } }
            Mock Get-AzComputeResourceSku { New-TestSku }
            Mock Get-AzVMUsage { New-TestUsage }
            Mock Invoke-AzRestMethod {
                $body = $Payload | ConvertFrom-Json
                $scores = @(foreach ($region in $body.desiredLocations) {
                    foreach ($size in $body.desiredSizes) { @{ region = $region; sku = $size.sku; score = 'High'; isQuotaAvailable = $true } }
                })
                @{ StatusCode = 200; Content = (@{ placementScores = $scores } | ConvertTo-Json -Depth 6) }
            }
            Mock New-AzResourceGroup {}
            Mock New-AzCapacityReservationGroup {}
            Mock New-AzCapacityReservation {}
            Mock Remove-AzResourceGroup { $true }
            Mock Write-Warning {}
            Mock Write-Host {}
            $script:catalog = @(Get-GpuCatalog -Regions eastus,westus3 -Context $context)
            $script:quota = @(Get-GpuQuota -Catalog $catalog -Context $context)
        }

        It 'has the nine approved default regions' {
            @(Get-GpuScannerRegion).Count | Should -Be 9
            Get-GpuScannerRegion | Should -Contain 'westcentralus'
        }
        It 'collects catalog with one unfiltered call and keeps US GPU rows' {
            Mock Get-AzComputeResourceSku {
                New-TestSku
                New-TestSku -Locations @('northeurope')
                $cpu = New-TestSku; $cpu.Capabilities[0].Value = '0'; $cpu
                $other = New-TestSku; $other.ResourceType = 'disks'; $other
            }
            $result = @(Get-GpuCatalog -Regions eastus,westus3 -Context $context)
            $result.Count | Should -Be 2
            $result[0].GpuType | Should -Be 'H100'
            $result[0].VCPUs | Should -Be 40
            $result[0].MemoryGB | Should -Be 320
            $result[0].Zones.Count | Should -Be 3
            Should -Invoke Get-AzComputeResourceSku -Times 2 -Exactly
        }
        It 'filters literally and handles an empty catalog' {
            @(Get-GpuCatalog -Regions eastus -GpuFilter A100 -Context $context).Count | Should -Be 0
            @(Get-GpuCatalog -Regions eastus -GpuFilter '[' -Context $context).Count | Should -Be 0
            Mock Get-AzComputeResourceSku {}
            @(Get-GpuCatalog -Context $context).Count | Should -Be 0
        }
        It 'maps explicit GPU models and legacy V100 without guessing unknowns' {
            foreach ($model in @('H100', 'H200', 'A100', 'MI300X', 'T4', 'A10', 'V100', 'L40S')) {
                Get-GpuType "Standard_NC_$model" | Should -Be $model
            }
            Get-GpuType 'Standard_NC6s_v3' | Should -Be 'V100'
            Get-GpuType 'Standard_NC6' | Should -Be 'Unknown'
        }
        It 'preserves fractional GPU counts' {
            Mock Get-AzComputeResourceSku { $sku = New-TestSku; $sku.Capabilities[0].Value = '0.5'; $sku }
            (Get-GpuCatalog -Regions eastus).GPUs | Should -Be 0.5
        }
        It 'scopes access restrictions and zone restrictions to the correct region' {
            Mock Get-AzComputeResourceSku {
                $sku = New-TestSku
                $sku.Restrictions = @(
                    @{ Type = 'Location'; Values = @('eastus'); ReasonCode = 'NotAvailableForSubscription'; RestrictionInfo = @{ Locations = @('eastus') } }
                    @{ Type = 'Zone'; Values = @('westus3'); ReasonCode = 'NotAvailableForSubscription'; RestrictionInfo = @{ Locations = @('westus3'); Zones = @('2') } }
                )
                $sku
            }
            $result = @(Get-GpuCatalog -Regions eastus,westus3)
            $result[0].CatalogStatus | Should -Be 'Restricted'
            $result[0].CatalogHint | Should -Be 'Request access'
            $result[1].CatalogStatus | Should -Be 'ZoneRestricted'
            $result[1].RestrictedZones | Should -Contain '2'
        }
        It 'uses the minimum of family and total quota with a single call per region' {
            $quota[0].VMsFit | Should -Be 2
            $quota[0].QuotaStatus | Should -Be 'QuotaOK'
            Should -Invoke Get-AzVMUsage -Times 1 -Exactly -ParameterFilter { $Location -eq 'eastus' }
            Should -Invoke Get-AzVMUsage -Times 1 -Exactly -ParameterFilter { $Location -eq 'westus3' }
        }
        It 'labels zero and insufficient quota without negative fit counts' {
            Mock Get-AzVMUsage { New-TestUsage -FamilyLimit 0 }
            $result = @(Get-GpuQuota -Catalog $catalog)
            $result[0].QuotaStatus | Should -Be 'NoQuota'
            $result[0].VMsFit | Should -Be 0
            Mock Get-AzVMUsage { New-TestUsage -TotalLimit 50 -TotalUsed 20 }
            @(Get-GpuQuota -Catalog $catalog)[0].QuotaStatus | Should -Be 'Insufficient'
        }
        It 'does not invent quota when family or total usage is missing' {
            Mock Get-AzVMUsage { @{ Name = @{ Value = 'localized display text' }; Limit = 100; CurrentValue = 0 } }
            $result = @(Get-GpuQuota -Catalog $catalog)
            $result[0].QuotaStatus | Should -Be 'Unknown'
            $result[0].VMsFit | Should -BeNullOrEmpty
        }
        It 'continues after quota 403 in one region' {
            Mock Get-AzVMUsage { throw 'HTTP 403 AuthorizationFailed' } -ParameterFilter { $Location -eq 'eastus' }
            $result = @(Get-GpuQuota -Catalog $catalog)
            $result[0].QuotaStatus | Should -Be 'Forbidden'
            $result[1].QuotaStatus | Should -Be 'QuotaOK'
        }
        It 'uses verified REST payload and is read-only even with Force alone' {
            $result = @(Get-GpuCapacity -Catalog $catalog -Quota $quota -Context $context -SubscriptionId $context.Subscription.Id -Force)
            $result.Count | Should -Be 2
            $result[0].SpotScore | Should -Be 'High'
            Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter {
                $body = $Payload | ConvertFrom-Json
                $Method -eq 'POST' -and $Path -like '*api-version=2025-06-05' -and
                $body.desiredCount -eq 1 -and $body.availabilityZones -eq $false -and
                $body.desiredSizes[0].sku -eq $catalog[0].SKU -and $DefaultProfile -eq $context
            }
            Should -Invoke New-AzResourceGroup -Times 0 -Exactly
        }
        It 'batches nine regions and six SKUs into four bounded requests' {
            $many = @(foreach ($region in Get-GpuScannerRegion) {
                foreach ($n in 1..6) { [pscustomobject]@{ Region = $region; SKU = "Standard_NC$n"; CatalogStatus = 'Available' } }
            })
            @(Get-GpuCapacity -Catalog $many -Quota @() -Context $context -SubscriptionId $context.Subscription.Id).Count | Should -Be 54
            Should -Invoke Invoke-AzRestMethod -Times 4 -Exactly -ParameterFilter {
                $body = $Payload | ConvertFrom-Json
                $body.desiredLocations.Count -le 8 -and $body.desiredSizes.Count -le 5
            }
        }
        It 'records HTTP 403 without throwing and labels missing scores unknown' {
            Mock Invoke-AzRestMethod { @{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed"}}' } }
            $result = @(Get-GpuCapacity -Catalog $catalog -Quota $quota -SubscriptionId $context.Subscription.Id)
            $result[0].CapacityStatus | Should -Be 'Forbidden'
            Mock Invoke-AzRestMethod { @{ StatusCode = 200; Content = '{"placementScores":[]}' } }
            $result = @(Get-GpuCapacity -Catalog $catalog -Quota $quota)
            $result[0].CapacityStatus | Should -Be 'Unknown'
            $result[0].Error | Should -Match 'No matching'
        }
        It 'makes no calls for empty capacity input' {
            @(Get-GpuCapacity -Catalog @() -Quota @()).Count | Should -Be 0
            Should -Invoke Invoke-AzRestMethod -Times 0 -Exactly
        }
        It 'continues to the next region batch after a Spot authorization failure' {
            $many = @(foreach ($region in Get-GpuScannerRegion) { @{ Region = $region; SKU = 'Standard_NC40ads_H100_v5' } })
            Mock Invoke-AzRestMethod { throw 'HTTP 403 Forbidden' } -ParameterFilter { $Path -like '*/locations/centralus/*' }
            $result = @(Get-GpuCapacity -Catalog $many -Quota @() -SubscriptionId $context.Subscription.Id)
            @($result | Where-Object CapacityStatus -EQ 'Forbidden').Count | Should -Be 8
            @($result | Where-Object SpotScore -EQ 'High').Count | Should -Be 1
            Should -Invoke Invoke-AzRestMethod -Times 2 -Exactly
        }
        It 'surfaces malformed responses as errors and throttling as rate limited' {
            Mock Invoke-AzRestMethod { @{ StatusCode = 200; Content = 'not json' } }
            @(Get-GpuCapacity -Catalog $catalog -Quota $quota)[0].CapacityStatus | Should -Be 'Error'
            Mock Invoke-AzRestMethod { @{ StatusCode = 429; Content = 'Please try again after 3600 seconds.' } }
            $result = @(Get-GpuCapacity -Catalog $catalog -Quota $quota)
            $result[0].CapacityStatus | Should -Be 'RateLimited'
            $result[0].Error | Should -Match '429.*60 minute'
        }
        It 'stops sending Spot requests after the first throttled batch' {
            $many = @(foreach ($region in Get-GpuScannerRegion) {
                foreach ($n in 1..6) { [pscustomobject]@{ Region = $region; SKU = "Standard_NC$n"; CatalogStatus = 'Available' } }
            })
            Mock Invoke-AzRestMethod { @{ StatusCode = 429; Content = 'Please try again after 3600 seconds.' } }
            $result = @(Get-GpuCapacity -Catalog $many -Quota @() -SubscriptionId $context.Subscription.Id)
            Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly
            @($result | Where-Object CapacityStatus -EQ 'RateLimited').Count | Should -Be 54
            @($result | Where-Object Error -Match 'Skipped after throttling').Count | Should -Be 14
        }
        It 'also stops after a thrown throttling exception' {
            $many = @(foreach ($n in 1..6) { [pscustomobject]@{ Region = 'eastus'; SKU = "Standard_NC$n" } })
            Mock Invoke-AzRestMethod { throw 'TooManyRequests' }
            $result = @(Get-GpuCapacity -Catalog $many -Quota @())
            Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly
            @($result | Where-Object CapacityStatus -EQ 'RateLimited').Count | Should -Be 6
        }
        It 'requires explicit probe confirmation before any Azure call' {
            Mock Read-Host { 'no' }
            { Get-GpuCapacity -Catalog $catalog -Quota $quota -ProbeCapacity } | Should -Throw '*cancelled*'
            Should -Invoke Invoke-AzRestMethod -Times 0 -Exactly
            Should -Invoke New-AzResourceGroup -Times 0 -Exactly
        }
        It 'creates quantity-one reservations with documented parameters and cleans each group' {
            $result = @(Get-GpuCapacity -Catalog $catalog -Quota $quota -Context $context -ProbeCapacity -Force)
            $result[0].ProbeStatus | Should -Be 'Succeeded'
            $result[0].CleanupStatus | Should -Be 'Deleted'
            Should -Invoke New-AzCapacityReservation -Times 2 -Exactly -ParameterFilter {
                $ReservationGroupName -eq 'gpu-probe' -and $CapacityToReserve -eq 1 -and $Sku -eq $catalog[0].SKU -and $DefaultProfile -eq $context
            }
            Should -Invoke Remove-AzResourceGroup -Times 2 -Exactly -ParameterFilter { $Name -like 'rg-gpu-probe-*' -and $Force }
        }
        It 'skips unsupported, restricted and quota-failing probes' {
            $catalog[0].CapacityReservationSupported = $false
            $catalog[1].CatalogStatus = 'ZoneRestricted'
            $result = @(Get-GpuCapacity -Catalog $catalog -Quota $quota -ProbeCapacity -Force)
            $result[0].ProbeStatus | Should -Be 'Unsupported'
            $result[1].ProbeStatus | Should -Be 'SkippedPrerequisites'
            $catalog[0].CapacityReservationSupported = $true
            $quota[0].QuotaStatus = 'Insufficient'
            Get-GpuCapacity -Catalog $catalog -Quota $quota -ProbeCapacity -Force | Out-Null
            Should -Invoke New-AzResourceGroup -Times 0 -Exactly
        }
        It 'cleans partial reservations on allocation failure and continues' {
            Mock New-AzCapacityReservation { throw 'AllocationFailed' }
            $result = @(Get-GpuCapacity -Catalog $catalog -Quota $quota -ProbeCapacity -Force)
            $result[0].ProbeStatus | Should -Be 'AllocationFailed'
            Should -Invoke Remove-AzResourceGroup -Times 2 -Exactly
        }
        It 'cleans even when group creation fails and distinguishes quota errors' {
            Mock New-AzCapacityReservationGroup { throw 'QuotaExceeded' }
            $result = @(Get-GpuCapacity -Catalog $catalog -Quota $quota -ProbeCapacity -Force)
            $result[0].ProbeStatus | Should -Be 'QuotaError'
            Should -Invoke Remove-AzResourceGroup -Times 2 -Exactly
        }
        It 'records cleanup failure and stops further probes' {
            Mock Remove-AzResourceGroup { throw '403 deletion denied' }
            $result = @(Get-GpuCapacity -Catalog $catalog -Quota $quota -ProbeCapacity -Force)
            $result[0].CleanupStatus | Should -Be 'Failed'
            $result[0].ResourceGroup | Should -Match '^rg-gpu-probe-'
            $result[1].ProbeStatus | Should -Be 'NotAttempted'
            @(Get-GpuReport -Catalog $catalog -Quota $quota -Capacity $result)[0].Verdict | Should -Be 'Unknown'
            Should -Invoke New-AzResourceGroup -Times 1 -Exactly
        }
        It 'handles false deletion responses and already absent groups' {
            Mock Remove-AzResourceGroup { $false }
            (Invoke-GpuReservationProbe -Sku $catalog[0]).CleanupStatus | Should -Be 'Failed'
            Mock New-AzResourceGroup { throw '403 AuthorizationFailed' }
            Mock Remove-AzResourceGroup { throw '404 ResourceGroupNotFound' }
            $result = Invoke-GpuReservationProbe -Sku $catalog[0]
            $result.ProbeStatus | Should -Be 'Forbidden'
            $result.CleanupStatus | Should -Be 'NotFound'
        }
        It 'joins verdicts conservatively without treating Spot as guaranteed capacity' {
            $capacity = @(Get-GpuCapacity -Catalog $catalog -Quota $quota)
            @(Get-GpuReport -Catalog $catalog -Quota $quota -Capacity $capacity)[0].Verdict | Should -Be 'Likely'
            $capacity[0].SpotQuotaAvailable = $false
            @(Get-GpuReport -Catalog $catalog -Quota $quota -Capacity $capacity)[0].Verdict | Should -Be 'Unknown'
            $capacity[0].ProbeStatus = 'Succeeded'; $capacity[0].CleanupStatus = 'Deleted'
            @(Get-GpuReport -Catalog $catalog -Quota $quota -Capacity $capacity)[0].Verdict | Should -Be 'Deployable'
            $catalog[0].CatalogStatus = 'Restricted'; $catalog[0].CatalogHint = 'Request access'
            @(Get-GpuReport -Catalog $catalog -Quota $quota -Capacity $capacity)[0].Verdict | Should -Be 'RequestAccess'
            $catalog[0].CatalogStatus = 'ZoneRestricted'
            @(Get-GpuReport -Catalog $catalog -Quota $quota -Capacity $capacity)[0].Verdict | Should -Be 'Restricted'
            $catalog[0].CatalogStatus = 'Available'; $quota[0].QuotaStatus = 'NoQuota'
            @(Get-GpuReport -Catalog $catalog -Quota $quota -Capacity $capacity)[0].Verdict | Should -Be 'QuotaNeeded'
        }
        It 'does not override a failed probe with a favorable Spot signal' {
            $capacity = @(Get-GpuCapacity -Catalog $catalog -Quota $quota)
            $capacity[0].ProbeStatus = 'AllocationFailed'
            @(Get-GpuReport -Catalog $catalog -Quota $quota -Capacity $capacity)[0].Verdict | Should -Be 'Unknown'
        }
        It 'writes array-shaped empty stage files and rejects mismatched and stale caches' {
            $root = Join-Path $TestDrive 'cache'
            $dir = Join-Path $root '20261005'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $path = Join-Path $dir 'catalog.json'
            Save-GpuStage -Path $path -SubscriptionId 'sub1' -Regions eastus -GpuFilter H100 -Rows @()
            $json = Get-Content $path -Raw
            $json | Should -Match '"Rows":\s*\[\s*\]'
            Read-GpuCache -Root $root -FileName catalog.json -SubscriptionId sub1 -Regions eastus -GpuFilter H100 | Should -Not -BeNullOrEmpty
            Read-GpuCache -Root $root -FileName catalog.json -SubscriptionId sub2 -Regions eastus -GpuFilter H100 | Should -BeNullOrEmpty
            Read-GpuCache -Root $root -FileName catalog.json -SubscriptionId sub1 -Regions westus -GpuFilter H100 | Should -BeNullOrEmpty
            Read-GpuCache -Root $root -FileName catalog.json -SubscriptionId sub1 -Regions eastus -GpuFilter A100 | Should -BeNullOrEmpty
            $cache = $json | ConvertFrom-Json
            $cache.GeneratedAtUtc = [datetime]::UtcNow.AddMinutes(-31).ToString('o')
            $cache | ConvertTo-Json | Set-Content $path
            Read-GpuCache -Root $root -FileName catalog.json -SubscriptionId sub1 -Regions eastus -GpuFilter H100 | Should -BeNullOrEmpty
            'invalid json' | Set-Content $path
            Read-GpuCache -Root $root -FileName catalog.json -SubscriptionId sub1 -Regions eastus -GpuFilter H100 | Should -BeNullOrEmpty
        }
        It 'runs all and persists all stages and reports, then reuses prerequisites' {
            $root = Join-Path $TestDrive 'all'
            $result = Invoke-GpuScan -Stage All -SubscriptionId $context.Subscription.Id -Regions eastus -OutputPath $root -Context $context
            foreach ($file in @('catalog.json', 'quota.json', 'capacity.json', 'report.json', 'report.csv')) {
                Test-Path (Join-Path $result.OutputDirectory $file) | Should -BeTrue
            }
            $report = Get-Content (Join-Path $result.OutputDirectory 'report.json') -Raw
            $report.TrimStart().StartsWith('[') | Should -BeTrue
            @(Import-Csv (Join-Path $result.OutputDirectory 'report.csv')).Count | Should -Be 1
            $result2 = Invoke-GpuScan -Stage Capacity -SubscriptionId $context.Subscription.Id -Regions eastus -OutputPath $root -Context $context
            $result2.Report[0].Verdict | Should -Be 'Likely'
            Should -Invoke Get-AzComputeResourceSku -Times 2 -Exactly
            Should -Invoke Get-AzVMUsage -Times 3 -Exactly
            $original = Get-Content (Join-Path $result.OutputDirectory 'catalog.json') -Raw | ConvertFrom-Json
            $copied = Get-Content (Join-Path $result2.OutputDirectory 'catalog.json') -Raw | ConvertFrom-Json
            $copied.GeneratedAtUtc | Should -Be $original.GeneratedAtUtc
        }
        It 'automatically runs prerequisites when cache is missing' {
            $result = Invoke-GpuScan -Stage Capacity -SubscriptionId $context.Subscription.Id -Regions eastus -OutputPath (Join-Path $TestDrive 'missing')
            $result.Report[0].Verdict | Should -Be 'Likely'
            Test-Path (Join-Path $result.OutputDirectory 'catalog.json') | Should -BeTrue
        }
        It 'persists failed catalog collection distinctly from successful empty results' {
            Mock Get-AzComputeResourceSku { throw '403 AuthorizationFailed' }
            $result = Invoke-GpuScan -Stage All -SubscriptionId $context.Subscription.Id -Regions eastus -OutputPath (Join-Path $TestDrive 'failed')
            $saved = Get-Content (Join-Path $result.OutputDirectory 'catalog.json') -Raw | ConvertFrom-Json
            $saved.Status | Should -Be 'Failed'
            $saved.Error | Should -Match '403'
            $result.Report.Count | Should -Be 0
            Test-Path (Join-Path $result.OutputDirectory 'quota.json') | Should -BeFalse
            Mock Get-AzComputeResourceSku {}
            $empty = Invoke-GpuScan -Stage All -SubscriptionId $context.Subscription.Id -Regions eastus -OutputPath (Join-Path $TestDrive 'empty')
            (Get-Content (Join-Path $empty.OutputDirectory 'catalog.json') -Raw | ConvertFrom-Json).Status | Should -Be 'Succeeded'
            (Get-Content (Join-Path $empty.OutputDirectory 'report.json') -Raw).Trim() | Should -Be '[]'
            $header = (Get-Content (Join-Path $empty.OutputDirectory 'report.csv') -TotalCount 1) -replace '"', ''
            ($header -split ',') -join ',' | Should -Be ($script:ReportColumns -join ',')
        }
        It 'marks quota failures partial so they cannot become reusable cache successes' {
            Mock Get-AzVMUsage { throw '403 Forbidden' }
            $result = Invoke-GpuScan -Stage Quota -SubscriptionId $context.Subscription.Id -Regions eastus -OutputPath (Join-Path $TestDrive 'partial')
            (Get-Content (Join-Path $result.OutputDirectory 'quota.json') -Raw | ConvertFrom-Json).Status | Should -Be 'Partial'
            $result.Report[0].Verdict | Should -Be 'Unknown'
        }
        It 'refreshes prerequisite data for billable probes despite matching caches' {
            $root = Join-Path $TestDrive 'probe-refresh'
            Invoke-GpuScan -Stage All -SubscriptionId $context.Subscription.Id -Regions eastus -OutputPath $root -Context $context | Out-Null
            $result = Invoke-GpuScan -Stage Capacity -SubscriptionId $context.Subscription.Id -Regions eastus -OutputPath $root -Context $context -ProbeCapacity -Force
            $result.Report[0].Verdict | Should -Be 'Deployable'
            Should -Invoke Get-AzComputeResourceSku -Times 3 -Exactly
        }
        It 'does not carry a missing-family warning over to a valid SKU' {
            $other = $catalog[0].PSObject.Copy(); $other.SKU = 'missing'; $other.Family = 'missing'
            $result = @(Get-GpuQuota -Catalog @($other, $catalog[0]))
            $result[0].QuotaStatus | Should -Be 'Unknown'
            $result[1].QuotaStatus | Should -Be 'QuotaOK'
            $result[1].Error | Should -BeNullOrEmpty
        }
    }
}

Describe 'Customer entry point' {
    BeforeAll { $script:entryPoint = Join-Path $PSScriptRoot '..\Invoke-GpuScanner.ps1' }
    BeforeEach {
        $script:id = '00000000-0000-0000-0000-000000000001'
        $script:activeContext = [pscustomobject]@{ Account = @{ Id = 'test' }; Subscription = @{ Id = $id } }
        Mock Get-Module { [pscustomobject]@{ Name = $Name } } -ParameterFilter { $ListAvailable -and $Name -in @('Az.Accounts', 'Az.Compute', 'Az.Resources') }
        Mock Import-Module {} -ParameterFilter { $Name -in @('Az.Accounts', 'Az.Compute', 'Az.Resources') -or $Name -like '*GpuScanner.psm1' }
        Mock Disable-AzContextAutosave {}
        Mock Get-AzContext { $activeContext }
        Mock Set-AzContext { $activeContext }
        Mock Connect-AzAccount {}
        Mock Get-AzSubscription { @{ Name = 'test'; Id = $id } }
        Mock Invoke-GpuScan {}
        Mock Write-Host {}
    }
    It 'reports missing modules before authentication' {
        Mock Get-Module {} -ParameterFilter { $ListAvailable -and $Name -eq 'Az.Accounts' }
        { & $entryPoint -Stage Catalog } | Should -Throw '*Install-Module Az.Accounts*'
        Should -Invoke Connect-AzAccount -Times 0 -Exactly
        Should -Invoke Invoke-GpuScan -Times 0 -Exactly
    }
    It 'normalizes regions and wires non-interactive switches to the selected process context' {
        & $entryPoint -Stage All -SubscriptionId $id -Regions ' EastUS ',westus3 -GpuFilter H100 -OutputPath $TestDrive -ProbeCapacity -Force
        Should -Invoke Set-AzContext -Times 1 -Exactly -ParameterFilter { $SubscriptionId -eq $id -and $Scope -eq 'Process' }
        Should -Invoke Invoke-GpuScan -Times 1 -Exactly -ParameterFilter {
            $Stage -eq 'All' -and $SubscriptionId -eq $id -and ($Regions -join ',') -eq 'eastus,westus3' -and
            $GpuFilter -eq 'H100' -and $OutputPath -eq $TestDrive -and $ProbeCapacity -and $Force -and $Context -eq $activeContext
        }
        Should -Invoke Connect-AzAccount -Times 0 -Exactly
    }
    It 'rejects invalid region identifiers and incompatible probe stages before login' {
        { & $entryPoint -Stage All -Regions 'East US' } | Should -Throw '*region identifiers*'
        { & $entryPoint -Stage Quota -ProbeCapacity } | Should -Throw '*requires -Stage Capacity or All*'
        Should -Invoke Connect-AzAccount -Times 0 -Exactly
    }
    It 'signs in when no existing account context is available' {
        $script:signedIn = $false
        Mock Get-AzContext { if ($script:signedIn) { $activeContext } }
        Mock Connect-AzAccount { $script:signedIn = $true }
        & $entryPoint -Stage Catalog
        Should -Invoke Connect-AzAccount -Times 1 -Exactly -ParameterFilter { $Scope -eq 'Process' }
        Should -Invoke Invoke-GpuScan -Times 1 -Exactly -ParameterFilter { $SubscriptionId -eq $id -and -not $ProbeCapacity }
    }
    It 'runs the menu without probing by default and exits on Q' {
        $answers = [System.Collections.Generic.Queue[string]]::new()
        foreach ($answer in @('1', '4', '5', 'Q')) { $answers.Enqueue($answer) }
        Mock Read-Host { $answers.Dequeue() }
        & $entryPoint -SubscriptionId $id -OutputPath $TestDrive
        Should -Invoke Invoke-GpuScan -Times 1 -Exactly -ParameterFilter { $Stage -eq 'Catalog' -and -not $ProbeCapacity }
        Should -Invoke Invoke-GpuScan -Times 1 -Exactly -ParameterFilter { $Stage -eq 'All' -and -not $ProbeCapacity }
        Should -Invoke Read-Host -Times 4 -Exactly
    }
}
