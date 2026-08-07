#Requires -Version 5.1

# =====================================================================
# Restart-PrintStack - module loader
#
# Implementation lives in Private\ and Public\. This file only dot-sources
# those in the correct order and exports the public surface.
#
# _Config.ps1 is bootstrap and MUST load first: every private function
# reads the built-in allow-lists, protected port tables and regexes from
# script scope. An undefined lookup table in PowerShell is $null rather
# than an error, and "-in $null" silently matches nothing, so a queue that
# should have been protected would be deleted instead. Ordering here is
# load-bearing rather than cosmetic.
# =====================================================================

Set-StrictMode -Version Latest

$BootstrapFiles = @('_Config.ps1')

foreach ($Name in $BootstrapFiles) {
    $BootstrapFile = Join-Path -Path $PSScriptRoot -ChildPath "Private\$Name"
    if (-not (Test-Path -LiteralPath $BootstrapFile)) {
        throw "Restart-PrintStack: required bootstrap file is missing: $BootstrapFile"
    }
    . $BootstrapFile
}

$PrivateFiles = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $BootstrapFiles }
)
$PublicFiles = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue
)

foreach ($File in @($PrivateFiles + $PublicFiles)) {
    try {
        . $File.FullName
    }
    catch {
        throw "Restart-PrintStack: failed to import '$($File.FullName)': $($_.Exception.Message)"
    }
}

# Aliases have to be defined before they can be exported; naming them in the
# manifest alone declares an export that does not exist.
#
# 'rps' is deliberately NOT used: it is the built-in alias for Resume-Process,
# and shadowing a core cmdlet with something whose job is deleting printers is
# exactly the kind of surprise a maintenance tool should never spring. The one
# alias here is the verb a technician is likely to reach for first.
Set-Alias -Name 'Reset-PrintStack' -Value 'Restart-PrintStack' -Scope Script -Force

# Only the Public\ functions are exposed; everything in Private\ stays internal.
Export-ModuleMember -Function $PublicFiles.BaseName -Alias 'Reset-PrintStack'


