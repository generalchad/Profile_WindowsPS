# =====================================================================
# Optimize-VMX - module loader
#
# Implementation lives in Public\. This file only dot-sources those
# scripts and exports the public surface.
# =====================================================================

Set-StrictMode -Version Latest

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
