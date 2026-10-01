function Initialize-QRCoder {
    <#
    .SYNOPSIS
        Ensures the QRCoder assembly is loaded, offering to install it if missing.

    .DESCRIPTION
        The library usually is not present on first use. This loads it from the
        installed location, or - when the host is interactive - offers a one-time
        download. Non-interactive callers fail with a message pointing at
        Install-QRCoder rather than pausing on a prompt nobody can see.

        Throws on failure so New-QRCode can surface a single terminating error;
        the private helpers use throw because a nested ThrowTerminatingError does
        not stop the caller.

    .PARAMETER Version
        Optional QRCoder version to install when the library is missing. Defaults
        to the latest stable release.

    .OUTPUTS
        System.String. The full path to the loaded QRCoder.dll.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Version
    )

    if ('QRCoder.QRCodeGenerator' -as [type]) {
        return Join-Path (Get-QRCoderLibDirectory) 'QRCoder.dll'
    }

    $libDir = Get-QRCoderLibDirectory
    $dllPath = Join-Path $libDir 'QRCoder.dll'

    if (-not (Test-Path -LiteralPath $dllPath)) {
        if (-not (Request-QRCoderInstall)) {
            throw [System.IO.FileNotFoundException]::new(
                "QRCoder.dll was not found in '$libDir'. Run Install-QRCoder to download it, then retry.")
        }
        if ([string]::IsNullOrWhiteSpace($Version)) {
            $Version = Get-QRCoderLatestVersion
        }
        $null = Save-QRCoderLibrary -Version $Version -Destination $libDir
    }

    Add-Type -Path $dllPath
    return $dllPath
}
