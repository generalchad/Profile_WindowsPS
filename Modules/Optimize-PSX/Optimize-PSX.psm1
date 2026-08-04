# Requires -Version 7.6
# =====================================================================
# Optimize-PSX - module loader
#
# Implementation lives in Private\ and Public\. This file only dot-sources
# those in the correct order and exports the public surface.
#
# Files prefixed with an underscore are bootstrap and MUST load first, in
# the order listed in $BootstrapFiles:
#
#   _Config.ps1     every private function reads the shared extension
#                   tables, chdman command map and codec defaults from
#                   script scope. An undefined lookup table in PowerShell
#                   is $null rather than an error, and "-in $null"
#                   silently matches nothing, so ordering here is
#                   load-bearing rather than cosmetic.
#
#   _StreamPump.ps1 compiles the child-process output reader used by
#                   Start-ChdmanProcess, so the type must exist before
#                   any conversion begins.
# =====================================================================

Set-StrictMode -Version Latest

$BootstrapFiles = @('_Config.ps1', '_StreamPump.ps1')

foreach ($Name in $BootstrapFiles) {
    $BootstrapFile = Join-Path -Path $PSScriptRoot -ChildPath "Private\$Name"
    if (-not (Test-Path -LiteralPath $BootstrapFile)) {
        throw "Optimize-PSX: required bootstrap file is missing: $BootstrapFile"
    }
    . $BootstrapFile
}

$PrivateFiles = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private\*.ps1') -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $BootstrapFiles }
)
$PublicFiles = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public\*.ps1') -ErrorAction SilentlyContinue
)

foreach ($File in @($PrivateFiles + $PublicFiles)) {
    try {
        . $File.FullName
    } catch {
        throw "Optimize-PSX: failed to import '$($File.FullName)': $_"
    }
}

# Only the Public\ functions are exposed; everything in Private\ stays internal.
Export-ModuleMember -Function $PublicFiles.BaseName -Alias 'opsx'
