# Requires -Version 7.6
# =====================================================================
# Rename-MediaFile - module loader
#
# Implementation lives in Private\ and Public\. This file only dot-sources
# those in the correct order and exports the public surface.
#
# _Config.ps1 MUST load first: every private function reads the shared
# regex library and lookup tables from script scope. An undefined regex
# in PowerShell is $null rather than an error, and "-replace $null" fails
# silently, so ordering here is load-bearing rather than cosmetic.
# =====================================================================

$ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath 'Private\_Config.ps1'
if (-not (Test-Path -LiteralPath $ConfigFile)) {
    throw "Rename-MediaFile: required configuration file is missing: $ConfigFile"
}
. $ConfigFile

$PrivateFiles = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private\*.ps1') -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '_Config.ps1' }
)
$PublicFiles = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public\*.ps1') -ErrorAction SilentlyContinue
)

foreach ($File in @($PrivateFiles + $PublicFiles)) {
    try {
        . $File.FullName
    } catch {
        throw "Rename-MediaFile: failed to import '$($File.FullName)': $_"
    }
}

# Only the Public\ functions are exposed; everything in Private\ stays internal.
Export-ModuleMember -Function $PublicFiles.BaseName
