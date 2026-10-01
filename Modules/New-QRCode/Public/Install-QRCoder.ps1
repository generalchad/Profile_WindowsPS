function Install-QRCoder {
    <#
    .SYNOPSIS
        Downloads the QRCoder library used by New-QRCode.

    .DESCRIPTION
        Fetches a QRCoder release from nuget.org and extracts the best-matching
        QRCoder.dll for this host into a local library folder. The binary is kept
        outside the repository (see -Destination) and is only needed once, the
        first time a QR code is generated.

    .PARAMETER Version
        The QRCoder version to install. Defaults to the latest stable release.

    .PARAMETER Destination
        The folder to install QRCoder.dll into. Defaults to
        %LOCALAPPDATA%\New-QRCode\lib, or $env:NEWQRCODE_LIB when set.

    .PARAMETER Force
        Reinstalls even when QRCoder.dll is already present.

    .OUTPUTS
        PSCustomObject with Name, Version, Framework, Path, and Installed. When a
        copy already exists and -Force is not used, Installed is $false.

    .EXAMPLE
        Install-QRCoder

    .EXAMPLE
        Install-QRCoder -Version 1.8.0 -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidatePattern('^\d+\.\d+(\.\d+)?')]
        [string]$Version,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Destination = (Get-QRCoderLibDirectory),

        [Parameter()]
        [switch]$Force
    )

    $dllPath = Join-Path $Destination 'QRCoder.dll'

    if ((Test-Path -LiteralPath $dllPath) -and -not $Force) {
        return [PSCustomObject]@{
            Name      = 'QRCoder'
            Version   = (Get-Item -LiteralPath $dllPath).VersionInfo.FileVersion
            Framework = $null
            Path      = $dllPath
            Installed = $false
        }
    }

    try {
        if (-not $Version) {
            $Version = Get-QRCoderLatestVersion
        }

        if (-not $PSCmdlet.ShouldProcess($dllPath, "Download QRCoder $Version from nuget.org")) {
            return
        }

        return Save-QRCoderLibrary -Version $Version -Destination $Destination
    }
    catch {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $_.Exception,
            'QRCoderInstallFailed',
            [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
            $Destination
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
}
