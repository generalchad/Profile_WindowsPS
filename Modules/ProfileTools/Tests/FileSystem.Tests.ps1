# =====================================================================
# FileSystem.Tests.ps1 - Find-Text contract verification
#
# Covers both Find-Text modes: -Path (file contents) and pipeline input.
#
# Run:
#   pwsh -NoProfile -File .\Modules\ProfileTools\Tests\FileSystem.Tests.ps1
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
$manifestPath = Join-Path $moduleRoot 'ProfileTools.psd1'

Import-Module $manifestPath -Force

$probe = Join-Path $env:TEMP "Find-Text-$PID.txt"
Set-Content -LiteralPath $probe -Value @('alpha', 'bravo', 'charlie') -Encoding utf8

Write-Host "`n--- Testing ProfileTools Find-Text ---`n" -ForegroundColor Cyan

try {
    Test-Case 'Searches file contents when -Path is supplied' {
        $m = @(Find-Text -Regex 'bravo' -Path $probe)
        $m.Count -eq 1 -and $m[0].Line -eq 'bravo'
    }

    Test-Case 'Searches piped input when -Path is omitted' {
        $m = @('alpha', 'bravo', 'charlie' | Find-Text 'charlie')
        $m.Count -eq 1 -and $m[0].Line -eq 'charlie'
    }

    Test-Case 'Returns nothing when there is no match' {
        @(Find-Text -Regex 'zulu' -Path $probe).Count -eq 0
    }

    Test-Case 'Treats a piped path string as text, not a file' {
        $m = @(($probe) | Find-Text 'alpha')
        $m.Count -eq 0
    }
}
finally {
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
}

Write-Host "`nTest Results: $($script:Pass) Passed, $($script:Fail) Failed`n" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) {
    exit 1
}
