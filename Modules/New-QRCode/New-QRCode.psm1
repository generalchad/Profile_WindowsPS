#Requires -Version 7.2

<#
    New-QRCode
    Module loader: dot-sources every Private and Public script, then exports only
    the Public functions. The QRCoder library is fetched on first use rather than
    referenced here, so importing the module stays cheap.
#>

Set-StrictMode -Version Latest

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "New-QRCode: failed to import '$($file.FullName)': $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $public.BaseName
