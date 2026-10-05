#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module PowerShellGet -ErrorAction Stop
    $script:preflight = Join-Path $PSScriptRoot '..\Test-GpuScannerPrerequisites.ps1'
}

Describe 'GPU scanner pre-flight' {
    BeforeEach {
        Mock Get-Module {} -ParameterFilter { $ListAvailable }
        Mock Install-Module {}
        Mock Import-Module {}
        Mock Out-Host {}
        Mock Write-Warning {}
        Mock Write-Information {}
    }
    It 'reports all missing modules without installing by default' {
        $result = & $preflight
        $result.Ready | Should -BeFalse
        $result.Modules.Count | Should -Be 3
        @($result.Modules | Where-Object Status -EQ 'Missing').Count | Should -Be 3
        Should -Invoke Install-Module -Times 0 -Exactly
    }
    It 'checks importability when all modules are installed' {
        Mock Get-Module { @{ Name = $Name; Version = [version]'1.0' } } -ParameterFilter { $ListAvailable }
        $result = & $preflight
        $result.Ready | Should -BeTrue
        Should -Invoke Import-Module -Times 3 -Exactly
        Should -Invoke Install-Module -Times 0 -Exactly
    }
    It 'does not treat import failure as ready' {
        Mock Get-Module { @{ Name = $Name; Version = [version]'1.0' } } -ParameterFilter { $ListAvailable }
        Mock Import-Module { throw 'dependency missing' } -ParameterFilter { $Name -eq 'Az.Compute' }
        $result = & $preflight
        $result.Ready | Should -BeFalse
        ($result.Modules | Where-Object Module -EQ 'Az.Compute').Status | Should -Be 'ImportFailed'
        ($result.Modules | Where-Object Module -EQ 'Az.Compute').Detail | Should -Match 'dependency missing'
    }
    It 'installs only missing modules with explicit authorization and rechecks them' {
        $moduleSet = [System.Collections.Generic.HashSet[string]]::new()
        $moduleSet.Add('Az.Accounts') | Out-Null
        Mock Get-Module { if ($moduleSet.Contains($Name)) { @{ Name = $Name; Version = [version]'1.0' } } } -ParameterFilter { $ListAvailable }
        Mock Install-Module { $moduleSet.Add($Name) | Out-Null }
        $result = & $preflight -InstallMissing
        $result.Ready | Should -BeTrue
        Should -Invoke Install-Module -Times 2 -Exactly -ParameterFilter { $Scope -eq 'CurrentUser' -and $Repository -eq 'PSGallery' }
        Should -Invoke Install-Module -Times 0 -Exactly -ParameterFilter { $Name -eq 'Az.Accounts' }
    }
    It 'supports WhatIf without installing' {
        $result = & $preflight -InstallMissing -WhatIf
        $result.Ready | Should -BeFalse
        Should -Invoke Install-Module -Times 0 -Exactly
    }
    It 'surfaces installation failures with actionable guidance' {
        Mock Install-Module { throw 'network blocked' }
        { & $preflight -InstallMissing } | Should -Throw '*network blocked*proxy*policy*'
    }
}
