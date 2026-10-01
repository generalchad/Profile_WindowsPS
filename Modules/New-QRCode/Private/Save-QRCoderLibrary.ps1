function Save-QRCoderLibrary {
    <#
    .SYNOPSIS
        Downloads a QRCoder release and extracts QRCoder.dll into a library folder.

    .DESCRIPTION
        The download core shared by Install-QRCoder and Initialize-QRCoder. It
        throws on any failure so callers higher in the stack decide how to present
        it; the repository is never touched because the destination is a local
        library folder.

    .PARAMETER Version
        The QRCoder version to download.

    .PARAMETER Destination
        The folder QRCoder.dll is written to.

    .OUTPUTS
        PSCustomObject with Name, Version, Framework, Path, and Installed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    $dllPath = Join-Path $Destination 'QRCoder.dll'
    $nupkgUrl = 'https://api.nuget.org/v3-flatcontainer/qrcoder/{0}/qrcoder.{0}.nupkg' -f $Version
    $tempNupkg = Join-Path ([System.IO.Path]::GetTempPath()) ('qrcoder-{0}.nupkg' -f ([guid]::NewGuid()))

    try {
        Invoke-WebRequest -Uri $nupkgUrl -OutFile $tempNupkg -ErrorAction Stop

        # QRCoder ships per-targetFramework binaries; net6.0 is the newest target
        # and runs on the .NET that PowerShell 7 carries. Fall back for older hosts.
        $framework = $null
        $zip = [System.IO.Compression.ZipFile]::OpenRead($tempNupkg)
        try {
            $entry = $null
            foreach ($tfm in @('net6.0', 'net5.0', 'netstandard2.1', 'netstandard2.0')) {
                $candidate = $zip.GetEntry("lib/$tfm/QRCoder.dll")
                if ($candidate) {
                    $framework = $tfm
                    $entry = $candidate
                    break
                }
            }

            if (-not $entry) {
                throw [System.IO.InvalidDataException]::new("QRCoder $Version does not contain a supported QRCoder.dll.")
            }

            $null = New-Item -ItemType Directory -Path $Destination -Force
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dllPath, $true)
        }
        finally {
            $zip.Dispose()
        }
    }
    finally {
        Remove-Item -LiteralPath $tempNupkg -Force -ErrorAction SilentlyContinue
    }

    if (-not ('QRCoder.QRCodeGenerator' -as [type])) {
        Add-Type -Path $dllPath
    }

    return [PSCustomObject]@{
        Name      = 'QRCoder'
        Version   = $Version
        Framework = $framework
        Path      = $dllPath
        Installed = $true
    }
}
