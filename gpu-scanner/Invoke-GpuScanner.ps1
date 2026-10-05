[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive menu and colored customer console output use the PS7 information stream.')]
param(
    [ValidateSet('Catalog', 'Quota', 'Capacity', 'All')][string]$Stage,
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')][string]$SubscriptionId,
    [ValidateNotNullOrEmpty()][string[]]$Regions,
    [string]$GpuFilter,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'output'),
    [switch]$ProbeCapacity,
    [switch]$Force,
    [ValidateRange(1, 100)][int]$MaxSpotRequests = 10
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7+ required. Install: https://aka.ms/powershell' }
if ($ProbeCapacity -and $Stage -and $Stage -notin @('All', 'Capacity')) { throw '-ProbeCapacity requires -Stage Capacity or All.' }
foreach ($module in @('Az.Accounts', 'Az.Compute', 'Az.Resources')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "Missing $module. Run .\Test-GpuScannerPrerequisites.ps1 -InstallMissing from the gpu-scanner folder, or run: Install-Module Az.Accounts,Az.Compute,Az.Resources -Scope CurrentUser -Repository PSGallery"
    }
    Import-Module $module -ErrorAction Stop
}
Import-Module (Join-Path $PSScriptRoot 'GpuScanner.psm1') -Force
if (-not $Regions) { $Regions = @(Get-GpuScannerRegion) }
$Regions = @($Regions | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object -Unique)
foreach ($region in $Regions) { if ($region -notmatch '^[a-z][a-z0-9]+$') { throw "Use Azure region identifiers, not display names: $region" } }

Disable-AzContextAutosave -Scope Process | Out-Null
$context = Get-AzContext
if (-not $context -or -not $context.Account) {
    Write-Host 'Sign in to Azure. Automation may pre-authenticate with Connect-AzAccount (service principal or managed identity).'
    Connect-AzAccount -Scope Process | Out-Null
    $context = Get-AzContext
}
if (-not $SubscriptionId -and -not $Stage) {
    $subscriptions = @(Get-AzSubscription)
    if (-not $subscriptions.Count) { throw 'No accessible subscriptions.' }
    for ($i = 0; $i -lt $subscriptions.Count; $i++) { Write-Host "$($i + 1): $($subscriptions[$i].Name) [$($subscriptions[$i].Id)]" }
    $choice = Read-Host 'Select subscription number'
    $index = 0
    if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $subscriptions.Count) { throw 'Invalid subscription selection.' }
    $SubscriptionId = $subscriptions[$index - 1].Id
}
if ($SubscriptionId) { $context = Set-AzContext -SubscriptionId $SubscriptionId -Scope Process }
if (-not $context.Subscription.Id) { throw 'No active subscription. Specify -SubscriptionId.' }
$SubscriptionId = $context.Subscription.Id
Write-Host "Subscription: $SubscriptionId. Read-only unless -ProbeCapacity is explicitly selected."

$scan = @{
    SubscriptionId = $SubscriptionId; Regions = $Regions; GpuFilter = $GpuFilter
    OutputPath = $OutputPath; Context = $context; ProbeCapacity = $ProbeCapacity; Force = $Force
        MaxSpotRequests = $MaxSpotRequests
    }
if ($Stage) { Invoke-GpuScan -Stage $Stage @scan; return }
while ($true) {
    Write-Host "`n1 Catalog | 2 Quota | 3 Capacity | 4 Run all + report | 5 View last report | Q Quit"
    $choice = Read-Host 'Select'
    if ($choice -eq 'Q') { break }
    try {
        switch ($choice) {
            '1' { Invoke-GpuScan -Stage Catalog @scan }
            '2' { Invoke-GpuScan -Stage Quota @scan }
            '3' { Invoke-GpuScan -Stage Capacity @scan }
            '4' { Invoke-GpuScan -Stage All @scan }
            '5' {
                $root = Join-Path $OutputPath $SubscriptionId
                $last = if (Test-Path -LiteralPath $root) {
                    Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name -Descending |
                        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'report.json') } | Select-Object -First 1
                }
                if ($last) {
                    Write-Host "Saved report: $($last.FullName) (historical, not current capacity)"
                    Show-GpuReport -Report @(Get-Content -LiteralPath (Join-Path $last.FullName 'report.json') -Raw | ConvertFrom-Json)
                } else { Write-Host 'No saved report for this subscription.' }
            }
            default { Write-Warning 'Choose 1-5 or Q.' }
        }
    } catch { Write-Warning $_.Exception.Message }
}
