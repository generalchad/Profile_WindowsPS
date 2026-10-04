#Requires -Version 7.2
# =====================================================================
# New-CliCommandShortcut.Tests.ps1 - selection and shortcut contract
#
# Run:
#   pwsh -NoProfile -File .\Modules\New-CliCommandShortcut\Tests\New-CliCommandShortcut.Tests.ps1
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
$manifestPath = Join-Path $moduleRoot 'New-CliCommandShortcut.psd1'

Import-Module $manifestPath -Force

$sandbox = Join-Path $env:TEMP ("New-CliCommandShortcut.Tests." + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null

function New-HistoryFile {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Lines,
        [string] $FileName = 'history.txt'
    )

    $path = Join-Path $sandbox $FileName
    Set-Content -LiteralPath $path -Value $Lines -Encoding utf8
    return $path
}

function Get-SavedCommand {
    param([Parameter(Mandatory)] [string] $ShortcutPath)

    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($ShortcutPath)
        $encoded = ($link.Arguments -split '-EncodedCommand ')[1].Trim()
        return [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
    }
    finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

function Get-SavedTarget {
    param([Parameter(Mandatory)] [string] $ShortcutPath)

    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($ShortcutPath)
        return $link.TargetPath
    }
    finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

Write-Host "`n--- Testing New-CliCommandShortcut ---`n" -ForegroundColor Cyan

try {
    Test-Case 'Creates a shortcut at the requested path' {
        $history = New-HistoryFile -Lines @('Get-Date', 'Get-ChildItem') -FileName 'creates.txt'
        $shortcut = Join-Path $sandbox 'creates.lnk'
        $result = New-CliCommandShortcut -HistoryPath $history -Path $shortcut -Force
        (Test-Path -LiteralPath $shortcut) -and $result.Command -eq 'Get-ChildItem'
    }

    Test-Case 'Targets pwsh and decodes to the selected command' {
        $history = New-HistoryFile -Lines @('Get-Date') -FileName 'encode.txt'
        $shortcut = Join-Path $sandbox 'encode.lnk'
        $result = New-CliCommandShortcut -HistoryPath $history -Path $shortcut -Force
        (Get-SavedTarget $shortcut) -like '*pwsh.exe' -and (Get-SavedCommand $shortcut) -eq 'Get-Date'
    }

    Test-Case 'Skips a destructive cmdlet at the head of history' {
        $history = New-HistoryFile -Lines @('Get-Date', 'Remove-Item .\foo -Recurse') -FileName 'destructive.txt'
        $result = New-CliCommandShortcut -HistoryPath $history -Path (Join-Path $sandbox 'd1.lnk') -Force
        $result.Command -eq 'Get-Date'
    }

    Test-Case 'Skips a destructive native alias at the head of history' {
        $history = New-HistoryFile -Lines @('Get-Date', 'del foo.txt') -FileName 'native.txt'
        $result = New-CliCommandShortcut -HistoryPath $history -Path (Join-Path $sandbox 'd2.lnk') -Force
        $result.Command -eq 'Get-Date'
    }

    Test-Case 'Skips a pipeline that contains a destructive command' {
        $history = New-HistoryFile -Lines @('Get-Date', 'Get-ChildItem | Remove-Item') -FileName 'pipeline.txt'
        $result = New-CliCommandShortcut -HistoryPath $history -Path (Join-Path $sandbox 'd3.lnk') -Force
        $result.Command -eq 'Get-Date'
    }

    Test-Case 'Allows a harmless member of a destructive verb family' {
        $history = New-HistoryFile -Lines @('Get-Date', 'Get-Process | Format-Table') -FileName 'safe.txt'
        $result = New-CliCommandShortcut -HistoryPath $history -Path (Join-Path $sandbox 's1.lnk') -Force
        $result.Command -eq 'Get-Process | Format-Table'
    }

    Test-Case 'Skips blank and comment lines' {
        $history = New-HistoryFile -Lines @('Get-Date', '', '# a comment', '   ') -FileName 'blank.txt'
        $result = New-CliCommandShortcut -HistoryPath $history -Path (Join-Path $sandbox 'b1.lnk') -Force
        $result.Command -eq 'Get-Date'
    }

    Test-Case 'Skips an unparseable multi-line fragment' {
        $history = New-HistoryFile -Lines @('Get-Date', 'if ($true) {') -FileName 'fragment.txt'
        $result = New-CliCommandShortcut -HistoryPath $history -Path (Join-Path $sandbox 'f1.lnk') -Force
        $result.Command -eq 'Get-Date'
    }

    Test-Case 'Honors additional -Exclude patterns' {
        $history = New-HistoryFile -Lines @('Get-Date', 'Invoke-CustomThing') -FileName 'exclude.txt'
        $result = New-CliCommandShortcut -HistoryPath $history -Path (Join-Path $sandbox 'e1.lnk') -Exclude 'Invoke-CustomThing' -Force
        $result.Command -eq 'Get-Date'
    }

    Test-Case 'Derives the default file name from the command' {
        $history = New-HistoryFile -Lines @('Get-Date') -FileName 'name.txt'
        $directory = Join-Path $sandbox 'name-out'
        New-Item -ItemType Directory -Path $directory | Out-Null
        $result = New-CliCommandShortcut -HistoryPath $history -Path $directory -Force
        (Split-Path -Path $result.ShortcutPath -Leaf) -eq 'Get-Date.lnk'
    }

    Test-Case 'Writes into a directory path with an explicit name' {
        $history = New-HistoryFile -Lines @('Get-Date') -FileName 'name2.txt'
        $directory = Join-Path $sandbox 'named-out'
        New-Item -ItemType Directory -Path $directory | Out-Null
        $result = New-CliCommandShortcut -HistoryPath $history -Path $directory -Name 'custom' -Force
        (Test-Path -LiteralPath (Join-Path $directory 'custom.lnk')) -and
            (Split-Path -Path $result.ShortcutPath -Leaf) -eq 'custom.lnk'
    }

    Test-Case 'Captures the working directory' {
        $history = New-HistoryFile -Lines @('Get-Date') -FileName 'workdir.txt'
        $result = New-CliCommandShortcut -HistoryPath $history -Path (Join-Path $sandbox 'w1.lnk') -WorkingDirectory $sandbox -Force
        $result.WorkingDirectory -eq $sandbox
    }

    Test-Case 'Throws when the history file is missing' {
        try {
            New-CliCommandShortcut -HistoryPath (Join-Path $sandbox 'does-not-exist.txt') -Path (Join-Path $sandbox 'n1.lnk') -Force
            $false
        }
        catch { $true }
    }

    Test-Case 'Throws when no safe command exists' {
        $history = New-HistoryFile -Lines @('Remove-Item .\foo', 'del bar.txt') -FileName 'none.txt'
        try {
            New-CliCommandShortcut -HistoryPath $history -Path (Join-Path $sandbox 'n2.lnk') -Force
            $false
        }
        catch { $true }
    }

    Test-Case 'Refuses to overwrite without -Force' {
        $history = New-HistoryFile -Lines @('Get-Date', 'Get-ChildItem') -FileName 'force.txt'
        $shortcut = Join-Path $sandbox 'force.lnk'
        New-CliCommandShortcut -HistoryPath $history -Path $shortcut -Force | Out-Null
        try {
            New-CliCommandShortcut -HistoryPath $history -Path $shortcut
            $false
        }
        catch { $true }
    }

    Test-Case 'Overwrites with -Force' {
        $history = New-HistoryFile -Lines @('Get-Date', 'Get-ChildItem') -FileName 'force2.txt'
        $shortcut = Join-Path $sandbox 'force2.lnk'
        New-CliCommandShortcut -HistoryPath $history -Path $shortcut -Force | Out-Null
        $result = New-CliCommandShortcut -HistoryPath $history -Path $shortcut -Force
        $result.Command -eq 'Get-ChildItem'
    }
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nTest Results: $($script:Pass) Passed, $($script:Fail) Failed`n" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) {
    exit 1
}
