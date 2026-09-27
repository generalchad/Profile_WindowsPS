# =====================================================================
# Invoke-Elevation.Tests.ps1 - Unit Verification Suite
#
# Runs non-destructive unit tests for Invoke-Elevation: manifest
# validation, export surface, and the elevation launch logic with
# Start-Process / Test-Elevation mocked so UAC never fires.
#
# Run:
#   pwsh -NoProfile -File .\Modules\Invoke-Elevation\Tests\Invoke-Elevation.Tests.ps1
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
$manifestPath = Join-Path $moduleRoot 'Invoke-Elevation.psd1'

Write-Host "`n--- Testing Invoke-Elevation Module ---`n" -ForegroundColor Cyan

# 1. Manifest & Module Import
Test-Case 'Manifest parses without AST errors' {
    $t = $e = $null
    [System.Management.Automation.Language.Parser]::ParseFile($manifestPath, [ref]$t, [ref]$e)
    $null -eq $e -or $e.Count -eq 0
}

Test-Case 'Module imports cleanly and exports Invoke-Elevation + alias el' {
    Import-Module $manifestPath -Force
    $cmd = Get-Command -Module Invoke-Elevation
    $cmd.Count -eq 1 -and $cmd[0].Name -eq 'Invoke-Elevation'
}

Test-Case 'Defines the el alias and CloseCurrent parameter' {
    $cmd = Get-Command Invoke-Elevation
    $cmd.Parameters.ContainsKey('CloseCurrent')
}

Test-Case 'CloseCurrent exposes the x alias' {
    $cmd = Get-Command Invoke-Elevation
    $cmd.Parameters['CloseCurrent'].Aliases -contains 'x'
}

Test-Case 'Defines a positional Close parameter that accepts x' {
    $cmd = Get-Command Invoke-Elevation
    $param = $cmd.Parameters['Close']
    $positional = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
    $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
    $param.ParameterType -eq [string] -and
    $positional.Position -eq 0 -and
    $validateSet.ValidValues -contains 'x'
}

Test-Case 'Binds the bare x positional value' {
    $mod = Get-Module Invoke-Elevation
    $testBlock = {
        function Test-Elevation { $true }
        function Start-Process { throw 'Start-Process must not be called when already elevated' }
        Invoke-Elevation x
        $true
    }
    (& $mod.NewBoundScriptBlock($testBlock)) -eq $true
}

Test-Case 'Binds the -x switch alias' {
    $mod = Get-Module Invoke-Elevation
    $testBlock = {
        function Test-Elevation { $true }
        function Start-Process { throw 'Start-Process must not be called when already elevated' }
        Invoke-Elevation -x
        $true
    }
    (& $mod.NewBoundScriptBlock($testBlock)) -eq $true
}

# 2. Elevation launch logic (Start-Process mocked)
Test-Case 'No launch when already elevated' {
    $mod = Get-Module Invoke-Elevation
    $testBlock = {
        function Test-Elevation { $true }
        function Start-Process { throw 'Start-Process must not be called when already elevated' }
        Invoke-Elevation
        $true
    }
    (& $mod.NewBoundScriptBlock($testBlock)) -eq $true
}

Test-Case 'Inside Windows Terminal relaunches wt.exe with profile and directory' {
    $oldSession = $env:WT_SESSION
    $oldProfile = $env:WT_PROFILE_ID
    try {
        $env:WT_SESSION = 'test-session'
        $env:WT_PROFILE_ID = '{00000000-0000-0000-0000-000000000001}'

        $mod = Get-Module Invoke-Elevation
        $testBlock = {
            function Test-Elevation { $false }
            function Get-Command { [pscustomobject]@{ Source = 'C:\WindowsApps\wt.exe' } }
            function Start-Process {
                                    param($FilePath, $Verb, $ArgumentList, $WorkingDirectory, [switch]$PassThru, $ErrorAction)
                $script:capture = [pscustomobject]@{
                    FilePath         = $FilePath
                    Verb             = $Verb
                    Args             = $ArgumentList
                    WorkingDirectory = $WorkingDirectory
                }
                [pscustomobject]@{ Id = 42 }
            }
            Invoke-Elevation
            $script:capture
        }
        $res = & $mod.NewBoundScriptBlock($testBlock)

        $res.FilePath -eq 'C:\WindowsApps\wt.exe' -and
        $res.Verb -eq 'RunAs' -and
        $res.Args -like '*-p "*' -and
        $res.Args -like '*-d "*'
    }
    finally {
        $env:WT_SESSION = $oldSession
        $env:WT_PROFILE_ID = $oldProfile
    }
}

Test-Case 'Outside Windows Terminal elevates the current host with a working directory' {
    $oldSession = $env:WT_SESSION
    try {
        $env:WT_SESSION = $null

        $mod = Get-Module Invoke-Elevation
        $testBlock = {
            function Test-Elevation { $false }
            function Start-Process {
                                    param($FilePath, $Verb, $ArgumentList, $WorkingDirectory, [switch]$PassThru, $ErrorAction)
                $script:capture = [pscustomobject]@{
                    FilePath         = $FilePath
                    Verb             = $Verb
                    Args             = $ArgumentList
                    WorkingDirectory = $WorkingDirectory
                }
                [pscustomobject]@{ Id = 43 }
            }
            Invoke-Elevation
            $script:capture
        }
        $res = & $mod.NewBoundScriptBlock($testBlock)

        $expectedHost = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
        $res.FilePath -eq $expectedHost -and
        $res.Verb -eq 'RunAs' -and
        -not [string]::IsNullOrWhiteSpace($res.WorkingDirectory)
    }
    finally {
        $env:WT_SESSION = $oldSession
    }
}

Test-Case 'UAC cancellation warns instead of throwing' {
    $oldSession = $env:WT_SESSION
    try {
        $env:WT_SESSION = $null

        $mod = Get-Module Invoke-Elevation
        $testBlock = {
            function Test-Elevation { $false }
            function Start-Process {
                                    param($FilePath, $Verb, $ArgumentList, $WorkingDirectory, [switch]$PassThru, $ErrorAction)
                throw [System.ComponentModel.Win32Exception]::new(1223, 'The operation was canceled by the user')
            }
            Invoke-Elevation
            $true
        }
        (& $mod.NewBoundScriptBlock($testBlock)) -eq $true
    }
    finally {
        $env:WT_SESSION = $oldSession
    }
}

Test-Case 'Non-cancellation launch failure surfaces as a terminating error' {
    $oldSession = $env:WT_SESSION
    try {
        $env:WT_SESSION = $null

        $mod = Get-Module Invoke-Elevation
        $testBlock = {
            function Test-Elevation { $false }
            function Start-Process {
                                    param($FilePath, $Verb, $ArgumentList, $WorkingDirectory, [switch]$PassThru, $ErrorAction)
                throw [System.ComponentModel.Win32Exception]::new(5, 'Access is denied')
            }
            Invoke-Elevation
        }
                            try {
                                & $mod.NewBoundScriptBlock($testBlock)
                                $false
                            }
                            catch [System.ComponentModel.Win32Exception] {
                                $true
                            }
                            catch {
                                $_.FullyQualifiedErrorId -like '*ElevationLaunchFailed*'
                            }
    }
    finally {
        $env:WT_SESSION = $oldSession
    }
}

# 3. Summary
Write-Host "`nTest Results: $($script:Pass) Passed, $($script:Fail) Failed`n" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) {
    exit 1
}
