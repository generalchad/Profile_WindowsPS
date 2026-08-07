# =====================================================================
# Compress-Video - module loader
#
# Implementation lives in Private\ (internal helpers) and Public\
# (exported functions). This file only dot-sources those scripts and
# exports the public surface.
#
# _Config.ps1 MUST load first: every other file reads $script:ConfigPath
# / $script:ConfigDirectory / $script:DefaultConfig from script scope.
# =====================================================================

Set-StrictMode -Version Latest

$ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath 'Private\_Config.ps1'
if (-not (Test-Path -LiteralPath $ConfigFile)) {
    throw "Compress-Video: required configuration file is missing: $ConfigFile"
}
. $ConfigFile

$PrivateFiles = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private\*.ps1') -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '_Config.ps1' }
)

foreach ($File in $PrivateFiles) {
    try {
        . $File.FullName
    } catch {
        throw "Compress-Video: failed to import '$($File.FullName)': $_"
    }
}

$PublicFiles = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public\*.ps1') -ErrorAction SilentlyContinue
)

foreach ($File in $PublicFiles) {
    try {
        . $File.FullName
    } catch {
        throw "Compress-Video: failed to import '$($File.FullName)': $_"
    }
}

# Only the Public\ functions are exposed.
Export-ModuleMember -Function $PublicFiles.BaseName
