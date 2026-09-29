#Requires -Version 5.1
<#
.SYNOPSIS
    Builds the shareable New-ScanShare-Portable zip.

.DESCRIPTION
    Stages the New-ScanShare module (without its Tests and Deploy folders) plus
    the install/uninstall launchers, README, LICENSE and NOTICE, then compresses
    the result into a versioned zip that can be dropped on a network share or
    attached to a GitHub release.

    The staging directory is created under the temp path and removed afterwards.

.PARAMETER OutputPath
    Directory to write the zip into. Created if missing. Defaults to Dist\ at the
    repository root (git-ignored).

.EXAMPLE
    .\New-ScanSharePackage.ps1

    Builds Dist\New-ScanShare-Portable-<version>.zip.
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $moduleRoot)
$manifestPath = Join-Path $moduleRoot 'New-ScanShare.psd1'

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Module manifest not found at '$manifestPath'."
}

$version = [version](Import-PowerShellDataFile -LiteralPath $manifestPath).ModuleVersion

if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot 'Dist'
}

$packageName = 'New-ScanShare-Portable'
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "New-ScanShare-Package-$([guid]::NewGuid().ToString('n'))"
$packageDir = Join-Path $stagingRoot $packageName
$moduleStage = Join-Path $packageDir 'New-ScanShare'
$zipPath = Join-Path $OutputPath "$packageName-$version.zip"

try {
    New-Item -ItemType Directory -Path $moduleStage -Force | Out-Null

    # Tests and Deploy ride along in the repo but are not part of the user-facing
    # package; keeping them out keeps the download small and the folder clean.
    $excludedFromModule = @('Tests', 'Deploy')
    Get-ChildItem -LiteralPath $moduleRoot -Force |
        Where-Object { $_.Name -notin $excludedFromModule } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $moduleStage -Recurse -Force }

    $deployFiles = @(
        'Install-ScanShare.ps1',
        'Install-ScanShare.cmd',
        'Uninstall-ScanShare.ps1',
        'Uninstall-ScanShare.cmd',
        'README.txt'
    )
    foreach ($name in $deployFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $packageDir -Force
    }

    foreach ($name in @('LICENSE', 'NOTICE')) {
        $source = Join-Path $repoRoot $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $packageDir -Force
        }
    }

    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path $packageDir -DestinationPath $zipPath -Force

    Write-Host "Built: $zipPath"
    Write-Host "  Module version: $version"
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
