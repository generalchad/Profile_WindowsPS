function Get-QRCoderLibDirectory {
    <#
    .SYNOPSIS
        Returns the folder QRCoder.dll is installed into.

    .DESCRIPTION
        Defaults to %LOCALAPPDATA%\New-QRCode\lib so the downloaded binary never
        lands in the repository. $env:NEWQRCODE_LIB overrides the location, which
        is used to redirect the library for testing or a shared install.

    .OUTPUTS
        System.String. The library folder.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:NEWQRCODE_LIB)) {
        return $env:NEWQRCODE_LIB
    }

    $base = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
    return Join-Path $base 'New-QRCode\lib'
}
