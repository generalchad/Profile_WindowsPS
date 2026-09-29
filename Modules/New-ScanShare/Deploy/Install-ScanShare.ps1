#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the bundled New-ScanShare module for the current user and opens the setup dialog.

.DESCRIPTION
    Copies the New-ScanShare module bundled next to this script into the current
    user's module paths for both PowerShell 7 and Windows PowerShell 5.1, adds a
    Desktop shortcut, and launches Show-ScanShare.

    The module is installed into a real module path rather than run in place.
    Show-ScanShare relaunches itself elevated when the user clicks Create, and
    that fresh process only autoloads commands that live on a module path; a
    folder next to this installer is invisible to it. Installing per-user needs
    no administrator rights - elevation is requested later, by the dialog itself.

.PARAMETER ModulesPath
    One or more module-root directories to install into, replacing the default
    per-user paths. Intended for alternate or machine-wide locations and for
    testing.

.PARAMETER Force
    Reinstall even when the installed copy is the same version or newer.

.PARAMETER NoLaunch
    Install and create the shortcut only; do not open the Show-ScanShare dialog.

.PARAMETER NoShortcut
    Do not create the Desktop shortcut.

.EXAMPLE
    .\Install-ScanShare.ps1

    Installs for the current user and opens the setup dialog.

.EXAMPLE
    .\Install-ScanShare.ps1 -Force -NoLaunch

    Reinstalls silently; useful when pushing an update to an existing install.

.NOTES
    Windows only. The module itself requires Windows 10/11 or Server 2016+ (64-bit).
    Runs on PowerShell 7 and Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string[]]$ModulesPath,
    [switch]$Force,
    [switch]$NoLaunch,
    [switch]$NoShortcut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestName = 'New-ScanShare.psd1'
$sourceModule = Join-Path $PSScriptRoot 'New-ScanShare'
$sourceManifest = Join-Path $sourceModule $manifestName

if (-not (Test-Path -LiteralPath $sourceManifest)) {
    throw "Bundled module not found at '$sourceModule'. Keep Install-ScanShare.ps1 next to the New-ScanShare folder."
}

$sourceVersion = [version](Import-PowerShellDataFile -LiteralPath $sourceManifest).ModuleVersion
$sourceFullPath = (Get-Item -LiteralPath $sourceModule).FullName

function Install-ScanShareModule {
    param(
        [Parameter(Mandatory)][string]$ModulesRoot
    )

    $target = Join-Path $ModulesRoot 'New-ScanShare'
    $targetManifest = Join-Path $target $manifestName

    # When the install target is the module's own source (e.g. the author running
    # from their profile repo), copying over it in place would delete the source.
    # Get-Item normalizes 8.3 short names that Resolve-Path leaves alone.
    $sameLocation = (Test-Path -LiteralPath $target) -and
        ((Get-Item -LiteralPath $target).FullName -ieq $sourceFullPath)
    if ($sameLocation) {
        Write-Host "  Already in place: $target"
        return $target
    }

    if ((Test-Path -LiteralPath $targetManifest) -and -not $Force) {
        $installed = $null
        try {
            $installed = [version](Import-PowerShellDataFile -LiteralPath $targetManifest).ModuleVersion
        }
        catch {
            Write-Warning "Existing install at '$target' is unreadable and will be replaced."
        }

        if ($installed -and $installed -ge $sourceVersion) {
            Write-Host "  Up to date (v$installed): $target"
            return $target
        }
    }

    # Stage a sibling copy, then swap it in, so files dropped from a newer build
    # do not linger and a mid-copy failure leaves the existing install untouched.
    $staging = Join-Path $ModulesRoot ("New-ScanShare.tmp-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    try {
        Copy-Item -Path (Join-Path $sourceModule '*') -Destination $staging -Recurse -Force
    }
    catch {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }

    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
    Move-Item -LiteralPath $staging -Destination $target -Force
    Write-Host "  Installed v${sourceVersion}: $target"
    return $target
}

Write-Host 'Installing New-ScanShare for the current user...'

if (-not $ModulesPath) {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $ModulesPath = @(
        (Join-Path $documents 'PowerShell\Modules'),
        (Join-Path $documents 'WindowsPowerShell\Modules')
    )
}

$primaryTarget = $null
foreach ($root in $ModulesPath) {
    $installed = Install-ScanShareModule -ModulesRoot $root
    if (-not $primaryTarget) { $primaryTarget = $installed }
}

$exe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $exe) {
    $exe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
}

if ($exe -and -not $NoShortcut) {
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'New Scan Share.lnk'
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $exe
        # Bypass so the shortcut works where the execution policy is Restricted.
        $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -Command Show-ScanShare'
        $shortcut.WorkingDirectory = $primaryTarget
        $shortcut.IconLocation = "$exe,0"
        $shortcut.Description = 'Create an SMB scan-to-folder share on this PC'
        $shortcut.Save()
        Write-Host "  Desktop shortcut: $shortcutPath"
    }
    catch {
        Write-Warning "Could not create the Desktop shortcut: $($_.Exception.Message)"
    }
}

if ($NoLaunch) {
    Write-Host 'Done. Open "New Scan Share" from the Desktop to run it.'
    return
}

Write-Host 'Opening the setup dialog...'
Import-Module (Join-Path $primaryTarget $manifestName) -Force
Show-ScanShare
