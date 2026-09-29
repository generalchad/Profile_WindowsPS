#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the per-user New-ScanShare install and its Desktop shortcut.

.DESCRIPTION
    Deletes the New-ScanShare module from the current user's PowerShell 7 and
    Windows PowerShell 5.1 module paths and removes the "New Scan Share" Desktop
    shortcut.

    This only removes the tool. It does not touch any scan account, folder, SMB
    share, or firewall rule that New-ScanShare created - undo those separately if
    the PC no longer needs to receive scans.

.PARAMETER ModulesPath
    One or more module-root directories to remove the module from, replacing the
    default per-user paths. Intended for alternate or machine-wide locations and
    for testing.

.PARAMETER NoShortcut
    Do not remove the Desktop shortcut.

.EXAMPLE
    .\Uninstall-ScanShare.ps1

    Removes the current user's install and shortcut.

.NOTES
    Windows only. Runs on PowerShell 7 and Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string[]]$ModulesPath,
    [switch]$NoShortcut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ModulesPath) {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $ModulesPath = @(
        (Join-Path $documents 'PowerShell\Modules'),
        (Join-Path $documents 'WindowsPowerShell\Modules')
    )
}

foreach ($root in $ModulesPath) {
    $target = Join-Path $root 'New-ScanShare'
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
        Write-Host "  Removed: $target"
    }
}

if (-not $NoShortcut) {
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'New Scan Share.lnk'
    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force
        Write-Host "  Removed: $shortcutPath"
    }
}

Write-Host 'Done. Scan accounts, folders, shares and firewall rules were left untouched.'
