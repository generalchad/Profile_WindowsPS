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

Test-Case 'Module imports cleanly and exports both elevation functions' {
    Import-Module $manifestPath -Force
    $names = @(Get-Command -Module Invoke-Elevation | ForEach-Object Name)
    $names.Count -eq 2 -and $names -contains 'Invoke-Elevation' -and $names -contains 'Invoke-Unelevation'
}

Test-Case 'Defines the el alias and CloseCurrent parameter' {
    $cmd = Get-Command Invoke-Elevation
    $cmd.Parameters.ContainsKey('CloseCurrent')
}

Test-Case 'CloseCurrent exposes the x alias' {
    $cmd = Get-Command Invoke-Elevation
    $cmd.Parameters['CloseCurrent'].Aliases -contains 'x'
}

Test-Case 'Defines positional Flag and Flag2 parameters (alias Close) accepting x and u' {
    $cmd = Get-Command Invoke-Elevation
    $flag = $cmd.Parameters['Flag']
    $flag2 = $cmd.Parameters['Flag2']
    $pos0 = $flag.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
    $pos1 = $flag2.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
    $validate = $flag.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
    $flag.ParameterType -eq [string] -and
    $flag.Aliases -contains 'Close' -and
    $pos0.Position -eq 0 -and
    $pos1.Position -eq 1 -and
    $validate.ValidValues -contains 'x' -and
    $validate.ValidValues -contains 'u'
}

Test-Case 'Unelevate exposes the u alias and lives in both parameter sets' {
    $cmd = Get-Command Invoke-Elevation
    $param = $cmd.Parameters['Unelevate']
    $sets = @($param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | ForEach-Object ParameterSetName)
    $param.Aliases -contains 'u' -and $sets -contains 'Elevate' -and $sets -contains 'Run'
}

Test-Case 'Exports el, isudo and elevate aliases for Invoke-Elevation' {
    Import-Module $manifestPath -Force
    $names = Get-Alias | Where-Object Definition -eq 'Invoke-Elevation' | Select-Object -ExpandProperty Name
    $names -contains 'el' -and $names -contains 'isudo' -and $names -contains 'elevate'
}

Test-Case 'ScriptBlock is positional 0, mandatory, in the Run parameter set' {
    $cmd = Get-Command Invoke-Elevation
    $param = $cmd.Parameters['ScriptBlock']
    $attr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
    $param.ParameterType -eq [scriptblock] -and
    $attr.Position -eq 0 -and
    $attr.Mandatory -and
    $attr.ParameterSetName -eq 'Run'
}

Test-Case 'Flag belongs to the Elevate parameter set' {
    $cmd = Get-Command Invoke-Elevation
    $attr = $cmd.Parameters['Flag'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
    $attr.ParameterSetName -eq 'Elevate'
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

# 3. Script block execution (Start-Process mocked, -EncodedCommand decoded)
Test-Case 'Inside Windows Terminal runs a script block elevated via -EncodedCommand' {
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
                    FilePath = $FilePath
                    Verb     = $Verb
                    Args     = $ArgumentList
                }
                [pscustomobject]@{ Id = 42 }
            }
            Invoke-Elevation { New-ScanShare -Path 'D:\Scans' -ShareName 'Scans' }
            $script:capture
        }
        $res = & $mod.NewBoundScriptBlock($testBlock)

        $expectedHost = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
        $m = [regex]::Match($res.Args, '-EncodedCommand\s+([A-Za-z0-9+/=]+)')
        $decoded = if ($m.Success) { [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups[1].Value)) } else { $null }

        $res.FilePath -eq 'C:\WindowsApps\wt.exe' -and
        $res.Verb -eq 'RunAs' -and
        $res.Args -like '*-p "*' -and
        $res.Args -like '*-d "*' -and
        $res.Args -like "*-- $expectedHost*" -and
        $decoded -eq "New-ScanShare -Path 'D:\Scans' -ShareName 'Scans'"
    }
    finally {
        $env:WT_SESSION = $oldSession
        $env:WT_PROFILE_ID = $oldProfile
    }
}

Test-Case 'Outside Windows Terminal runs a script block elevated via pwsh -EncodedCommand' {
    $oldSession = $env:WT_SESSION
    try {
        $env:WT_SESSION = $null

        $mod = Get-Module Invoke-Elevation
        $testBlock = {
            function Test-Elevation { $false }
            function Start-Process {
                param($FilePath, $Verb, $ArgumentList, $WorkingDirectory, [switch]$PassThru, $ErrorAction)
                $script:capture = [pscustomobject]@{
                    FilePath = $FilePath
                    Verb     = $Verb
                    Args     = $ArgumentList
                }
                [pscustomobject]@{ Id = 43 }
            }
            Invoke-Elevation { Write-Output 'hello' }
            $script:capture
        }
        $res = & $mod.NewBoundScriptBlock($testBlock)

        $expectedHost = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
        $m = [regex]::Match($res.Args, '-EncodedCommand\s+([A-Za-z0-9+/=]+)')
        $decoded = if ($m.Success) { [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups[1].Value)) } else { $null }

        $res.FilePath -eq $expectedHost -and
        $res.Verb -eq 'RunAs' -and
        $decoded -eq "Write-Output 'hello'"
    }
    finally {
        $env:WT_SESSION = $oldSession
    }
}

# 4. Unelevation
Test-Case 'Keeps the -Close x named shorthand' {
    $mod = Get-Module Invoke-Elevation
    $testBlock = {
        function Test-Elevation { $true }
        function Start-Process { throw 'Start-Process must not be called when already elevated' }
        Invoke-Elevation -Close x
        $true
    }
    (& $mod.NewBoundScriptBlock($testBlock)) -eq $true
}

Test-Case 'No unelevation launch when already unelevated' {
    $mod = Get-Module Invoke-Elevation
    $testBlock = {
        function Test-Elevation { $false }
        function Start-Process { throw 'Start-Process must not be called when already unelevated' }
        Invoke-Elevation u
        $true
    }
    (& $mod.NewBoundScriptBlock($testBlock)) -eq $true
}

Test-Case 'Accepts the combined u x positional shorthand' {
    $mod = Get-Module Invoke-Elevation
    $testBlock = {
        function Test-Elevation { $false }
        function Start-Process { throw 'Start-Process must not be called when already unelevated' }
        Invoke-Elevation u x
        $true
    }
    (& $mod.NewBoundScriptBlock($testBlock)) -eq $true
}

Test-Case 'From elevated, bare u launches the host with a filtered token' {
    $oldSession = $env:WT_SESSION
    try {
        $env:WT_SESSION = $null
        $mod = Get-Module Invoke-Elevation
        $testBlock = {
            function Test-Elevation { $true }
            function Start-LimitedProcess {
                param($FilePath, $CommandLine, $WorkingDirectory)
                $script:capture = [pscustomobject]@{
                    FilePath    = $FilePath
                    CommandLine = $CommandLine
                }
                7
            }
            function Start-Process { throw 'runas fallback must not run when a linked token exists' }
            Invoke-Elevation u
            $script:capture
        }
        $res = & $mod.NewBoundScriptBlock($testBlock)
        $expectedHost = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }

        $res.FilePath -eq (Join-Path $PSHOME ($expectedHost + '.exe')) -and
        $res.CommandLine -like "*$expectedHost*" -and
        $res.CommandLine -notlike '*runas*'
    }
    finally {
        $env:WT_SESSION = $oldSession
    }
}

Test-Case 'From elevated, the -Unelevate switch launches a filtered token' {
    $oldSession = $env:WT_SESSION
    try {
        $env:WT_SESSION = $null
        $mod = Get-Module Invoke-Elevation
        $testBlock = {
            function Test-Elevation { $true }
            function Start-LimitedProcess {
                param($FilePath, $CommandLine, $WorkingDirectory)
                $script:capture = [pscustomobject]@{ FilePath = $FilePath; CommandLine = $CommandLine }
                8
            }
            function Start-Process { throw 'runas fallback must not run when a linked token exists' }
            Invoke-Elevation -Unelevate
            $script:capture
        }
        $res = & $mod.NewBoundScriptBlock($testBlock)

        $res.FilePath -like '*.exe' -and $res.CommandLine -notlike '*runas*'
    }
    finally {
        $env:WT_SESSION = $oldSession
    }
}

Test-Case 'Unelevating inside Windows Terminal targets wt.exe with the profile and directory' {
    $oldSession = $env:WT_SESSION
    $oldProfile = $env:WT_PROFILE_ID
    try {
        $env:WT_SESSION = 'test-session'
        $env:WT_PROFILE_ID = '{00000000-0000-0000-0000-000000000001}'

        $mod = Get-Module Invoke-Elevation
        $testBlock = {
            function Test-Elevation { $true }
            function Get-Command { [pscustomobject]@{ Source = 'C:\WindowsApps\wt.exe' } }
            function Start-LimitedProcess {
                param($FilePath, $CommandLine, $WorkingDirectory)
                $script:capture = [pscustomobject]@{ FilePath = $FilePath; CommandLine = $CommandLine }
                9
            }
            function Start-Process { throw 'runas fallback must not run when a linked token exists' }
            Invoke-Elevation u
            $script:capture
        }
        $res = & $mod.NewBoundScriptBlock($testBlock)

        $res.FilePath -eq 'C:\WindowsApps\wt.exe' -and
        $res.CommandLine -like '*C:\WindowsApps\wt.exe*' -and
        $res.CommandLine -like '*-p "*' -and
        $res.CommandLine -like '*-d "*'
    }
    finally {
        $env:WT_SESSION = $oldSession
        $env:WT_PROFILE_ID = $oldProfile
    }
}

Test-Case 'Unelevate accepts a script block via -u' {
    $oldSession = $env:WT_SESSION
    try {
        $env:WT_SESSION = $null
        $mod = Get-Module Invoke-Elevation
        $testBlock = {
            function Test-Elevation { $true }
            function Start-LimitedProcess {
                param($FilePath, $CommandLine, $WorkingDirectory)
                $script:capture = [pscustomobject]@{ FilePath = $FilePath; CommandLine = $CommandLine }
                11
            }
            function Start-Process { throw 'runas fallback must not run when a linked token exists' }
            Invoke-Elevation -u { Write-Output 'hi' }
            $script:capture
        }
        $res = & $mod.NewBoundScriptBlock($testBlock)
        $m = [regex]::Match($res.CommandLine, '-EncodedCommand\s+([A-Za-z0-9+/=]+)')
        $decoded = if ($m.Success) { [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups[1].Value)) } else { $null }

        $res.FilePath -like '*.exe' -and
        $decoded -eq "Write-Output 'hi'"
    }
    finally {
        $env:WT_SESSION = $oldSession
    }
}

Test-Case 'Exports the uel alias for Invoke-Unelevation' {
    Import-Module $manifestPath -Force
    (Get-Alias -Name uel -ErrorAction SilentlyContinue).Definition -eq 'Invoke-Unelevation'
}

Test-Case 'uel launches an unelevated session from an elevated one' {
    $oldSession = $env:WT_SESSION
    try {
        $env:WT_SESSION = $null
        $mod = Get-Module Invoke-Elevation
        $testBlock = {
            function Test-Elevation { $true }
            function Start-LimitedProcess {
                param($FilePath, $CommandLine, $WorkingDirectory)
                $script:capture = [pscustomobject]@{ FilePath = $FilePath; CommandLine = $CommandLine }
                10
            }
            function Start-Process { throw 'runas fallback must not run when a linked token exists' }
            Invoke-Unelevation
            $script:capture
        }
        $res = & $mod.NewBoundScriptBlock($testBlock)

        $res.FilePath -like '*.exe' -and $res.CommandLine -notlike '*runas*'
    }
    finally {
        $env:WT_SESSION = $oldSession
    }
}

Test-Case 'Falls back to runas /trustlevel when no linked token exists' {
    $oldSession = $env:WT_SESSION
    try {
        $env:WT_SESSION = $null
        $mod = Get-Module Invoke-Elevation
        $testBlock = {
            function Test-Elevation { $true }
            function Start-LimitedProcess { param($FilePath, $CommandLine, $WorkingDirectory) $null }
            function Start-Process {
                param($FilePath, $Verb, $ArgumentList, $WorkingDirectory, [switch]$PassThru, $ErrorAction, $WindowStyle)
                $script:capture = [pscustomobject]@{ FilePath = $FilePath; Args = $ArgumentList }
                [pscustomobject]@{ Id = 12 }
            }
            Invoke-Elevation u
            $script:capture
        }
        $res = & $mod.NewBoundScriptBlock($testBlock)

        $res.FilePath -eq 'runas.exe' -and $res.Args -like '/trustlevel:0x20000*'
    }
    finally {
        $env:WT_SESSION = $oldSession
    }
}

# 5. Summary
Write-Host "`nTest Results: $($script:Pass) Passed, $($script:Fail) Failed`n" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) {
    exit 1
}
