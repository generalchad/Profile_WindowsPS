#Requires -Version 5.1

<#
    Restart-NetworkStack
    Module loader: dot-sources every Private and Public script, then exports only
    the Public functions and their aliases.
#>

Set-StrictMode -Version Latest

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import '$($file.FullName)': $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $public.BaseName -Alias 'rns', 'Reset-NetworkStack'
