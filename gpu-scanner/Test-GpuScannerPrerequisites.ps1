[CmdletBinding(SupportsShouldProcess)]
param([switch]$InstallMissing)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ required. Install from https://aka.ms/powershell, then run this script in pwsh.'
}

$requiredModules = @('Az.Accounts', 'Az.Compute', 'Az.Resources')
$missing = @($requiredModules | Where-Object { -not (Get-Module -ListAvailable -Name $_) })
if ($missing.Count -and $InstallMissing) {
    if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
        throw 'Install-Module is unavailable. Install PowerShellGet or have your administrator provision the required Az modules.'
    }
    foreach ($name in $missing) {
        if ($PSCmdlet.ShouldProcess("$name (CurrentUser, PSGallery)", 'Install module and its dependencies')) {
            try {
                Install-Module -Name $name -Scope CurrentUser -Repository PSGallery -ErrorAction Stop
            } catch {
                throw "Could not install ${name}: $($_.Exception.Message) Check PSGallery access, proxy configuration, and your organization module-installation policy."
            }
        }
    }
}

$checks = @(foreach ($name in $requiredModules) {
    $installed = Get-Module -ListAvailable -Name $name | Sort-Object Version -Descending | Select-Object -First 1
    $status = 'Missing'; $detail = 'Not installed'
    if ($installed) {
        try {
            Import-Module $name -ErrorAction Stop
            $status = 'Ready'; $detail = "Version $($installed.Version)"
        } catch { $status = 'ImportFailed'; $detail = $_.Exception.Message }
    }
    [pscustomobject]@{ Module = $name; Status = $status; Detail = $detail }
})
$checks | Format-Table -AutoSize | Out-Host
$ready = @($checks | Where-Object Status -NE 'Ready').Count -eq 0
if ($ready) {
    Write-Information 'Prerequisites ready. Run .\Invoke-GpuScanner.ps1. Azure PowerShell sign-in is separate from az login; the scanner will prompt if needed.' -InformationAction Continue
} else {
    Write-Warning 'Prerequisites are not ready. Run .\Test-GpuScannerPrerequisites.ps1 -InstallMissing, or ask your administrator to provision the modules. Import failures are shown above.'
}
Write-Information 'This pre-flight does not sign in, query Azure, or verify subscription permissions/network connectivity.' -InformationAction Continue
[pscustomobject]@{ Ready = $ready; PowerShellVersion = $PSVersionTable.PSVersion.ToString(); Modules = $checks }
