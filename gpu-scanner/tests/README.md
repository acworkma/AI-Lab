# GPU Scanner developer testing

These instructions are for maintainers changing the scanner. Customers do not need these tools or
commands to run it.

From the `gpu-scanner` directory in PowerShell 7:

```powershell
Install-Module Pester,PSScriptAnalyzer -Scope CurrentUser -Repository PSGallery
Invoke-Pester .\tests -Output Detailed
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error
```

Tests use Pester 5+ and mock Az commands with local signatures, so Az installation and a live Azure
login are not required. No live capacity or reservation tests run, and no Azure resources are created.
These checks validate code behavior, not actual Azure quota or capacity.

Installing the testing tools requires internet access; the tests themselves do not call Azure.
