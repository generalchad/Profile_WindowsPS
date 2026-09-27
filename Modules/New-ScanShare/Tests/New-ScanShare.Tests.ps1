# =====================================================================
# New-ScanShare.Tests.ps1 - Functional & Unit Verification Suite
#
# Runs non-destructive unit and behavioral tests for New-ScanShare:
# manifest validation, parameter constraints, path normalization,
# -WhatIf dry run execution, and IP/firewall heuristics.
#
# Run:
#   pwsh -NoProfile -File .\Modules\New-ScanShare\Tests\New-ScanShare.Tests.ps1
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
$manifestPath = Join-Path $moduleRoot 'New-ScanShare.psd1'

Write-Host "`n--- Testing New-ScanShare Module ---`n" -ForegroundColor Cyan

# 1. Manifest & Module Import
Test-Case 'Manifest parses without AST errors' {
    $t = $e = $null
    [System.Management.Automation.Language.Parser]::ParseFile($manifestPath, [ref]$t, [ref]$e)
    $null -eq $e -or $e.Count -eq 0
}

Test-Case 'Module imports cleanly and exports New-ScanShare' {
    Import-Module $manifestPath -Force
    $cmd = Get-Command -Module New-ScanShare
    $cmd.Count -eq 1 -and $cmd[0].Name -eq 'New-ScanShare'
}

# 2. Parameter Validation & Constraints
Test-Case 'Validates valid ShareName and UserName parameters' {
    $cmd = Get-Command New-ScanShare
    $paramShare = $cmd.Parameters['ShareName']
    $paramUser = $cmd.Parameters['UserName']
    $null -ne $paramShare -and $null -ne $paramUser
}

Test-Case 'Rejects invalid characters in ShareName parameter metadata' {
    try {
        New-ScanShare -ShareName 'Invalid/Share' -WhatIf -ErrorAction Stop
        $false
    } catch [System.Management.Automation.ParameterBindingException] {
        $true
    } catch {
        $false
    }
}

Test-Case 'Rejects invalid characters in UserName parameter metadata' {
    try {
        New-ScanShare -UserName 'bad*user' -WhatIf -ErrorAction Stop
        $false
    } catch [System.Management.Automation.ParameterBindingException] {
        $true
    } catch {
        $false
    }
}

# 3. Path Normalization
Test-Case 'Path normalizes trailing slash in -WhatIf simulation' {
    $res = New-ScanShare -Path 'C:\Scans\' -ShareName 'Scans' -WhatIf
    $res.Path -eq 'C:\Scans'
}

Test-Case 'Preserves filesystem root path without stripping separator' {
    $res = New-ScanShare -Path 'C:\' -ShareName 'Scans' -WhatIf
    $res.Path -eq 'C:\'
}

Test-Case 'Relative path resolves against current PowerShell location' {
    Push-Location $env:TEMP
    try {
        $expected = Join-Path (Get-Location).Path 'ScansTest'
        $res = New-ScanShare -Path '.\ScansTest' -WhatIf
        $res.Path -eq $expected
    }
    finally {
        Pop-Location
    }
}

# 4. Dry Run & Output Schema
Test-Case '-WhatIf returns PSCustomObject with complete schema' {
    $res = New-ScanShare -ShareName 'TestShare' -UserName 'testscan' -WhatIf
    $null -ne $res -and
    $res.UncPath -eq "\\$env:COMPUTERNAME\TestShare" -and
    $res.Account -eq "$env:COMPUTERNAME\testscan" -and
    $res.Steps.Count -ge 4
}

Test-Case '-WhatIf does not mutate file system or share state' {
    $testFolder = Join-Path $env:TEMP "TestScanShare_$(Get-Random)"
    $null = New-ScanShare -Path $testFolder -ShareName "TempShare$(Get-Random)" -WhatIf
    -not (Test-Path -LiteralPath $testFolder)
}

Test-Case '-ResetPassword with -WhatIf does not prompt for input' {
    # Existing local user (e.g. Administrator or Guest) should report WhatIf without blocking on Read-Host
    $existingUser = (Get-LocalUser | Select-Object -First 1)?.Name
    if (-not $existingUser) { $existingUser = 'Administrator' }
    $res = New-ScanShare -UserName $existingUser -ResetPassword -WhatIf
    $accountStep = $res.Steps | Where-Object Step -eq 'Account'
    $accountStep.Status -eq 'WhatIf'
}

Test-Case '-SkipFirewall records Skipped status in Steps' {
    $res = New-ScanShare -SkipFirewall -WhatIf
    $fwStep = $res.Steps | Where-Object Step -eq 'Firewall'
    $fwStep.Status -eq 'Skipped'
}

# 5. IP Address and Network Heuristics
Test-Case 'Primary LAN IP resolves to valid non-virtual address' {
    $mod = Get-Module New-ScanShare
    $ip = & $mod.NewBoundScriptBlock({ Get-PrimaryIPv4Address })

    $ip -and
    $ip -notmatch '^127\.' -and
    $ip -notmatch '^169\.254\.'
}

# 6. Summary
Write-Host "`nTest Results: $($script:Pass) Passed, $($script:Fail) Failed`n" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) {
    exit 1
}
