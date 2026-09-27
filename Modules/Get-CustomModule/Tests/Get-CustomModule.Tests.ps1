# =====================================================================
# Get-CustomModule.Tests.ps1 - Name-filter contract verification
#
# Run:
#   pwsh -NoProfile -File .\Modules\Get-CustomModule\Tests\Get-CustomModule.Tests.ps1
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:Pass = 0
$script:Fail = 0

function Test-Case {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Body
    )

    try {
        $result = & $Body
        if ($result) {
            Write-Host "  [PASS] $Name" -ForegroundColor Green
            $script:Pass++
        }
        else {
            Write-Host "  [FAIL] $Name" -ForegroundColor Red
            $script:Fail++
        }
    }
    catch {
        Write-Host "  [FAIL] $Name : $($_.Exception.Message)" -ForegroundColor Red
        $script:Fail++
    }
}

$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path $moduleRoot 'Get-CustomModule.psd1'

Import-Module $manifestPath -Force

Write-Host "`n--- Testing Get-CustomModule ---`n" -ForegroundColor Cyan

Test-Case 'Returns all custom modules by default' {
    @(Get-CustomModule).Count -gt 0
}

Test-Case 'Filters modules by wildcard' {
    $names = @(Get-CustomModule -Name '*Print*').Name
    $names -contains 'Restart-PrintStack' -and $names -contains 'Get-PrinterInfo'
}

Test-Case 'Does not clobber the automatic $Matches variable' {
    'abc' -match 'b' | Out-Null
    Get-CustomModule -Name 'Get-CustomModule' | Out-Null
    $Matches[0] -eq 'b'
}

Test-Case 'Returns nothing for an explicitly empty name filter' {
    @(Get-CustomModule -Name @()).Count -eq 0
}

Write-Host "`nTest Results: $($script:Pass) Passed, $($script:Fail) Failed`n" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) {
    exit 1
}
