# =====================================================================
# Optimize-VMX - module loader
#
# Implementation lives in Private\ (internal helpers) and Public\
# (exported functions). This file only dot-sources those scripts and
# exports the public surface.
# =====================================================================

Set-StrictMode -Version Latest

# Private helpers must be loaded first so Public functions can call them.
$PrivateFiles = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private\*.ps1') -ErrorAction SilentlyContinue
)

foreach ($File in $PrivateFiles) {
    try {
        . $File.FullName
    } catch {
        throw "Optimize-VMX: failed to import '$($File.FullName)': $_"
    }
}

$PublicFiles = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public\*.ps1') -ErrorAction SilentlyContinue
)

foreach ($File in $PublicFiles) {
    try {
        . $File.FullName
    } catch {
        throw "Optimize-VMX: failed to import '$($File.FullName)': $_"
    }
}

# Only the Public\ functions are exposed.
Export-ModuleMember -Function $PublicFiles.BaseName
