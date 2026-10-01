function Get-QRCodeData {
    <#
    .SYNOPSIS
        Encodes text into QRCoder QRCodeData (module matrix and version).

    .DESCRIPTION
        Single place the encoding options live: byte mode forced to UTF-8 so
        non-ASCII payloads round-trip correctly. Requires QRCoder to be loaded.

    .PARAMETER Text
        The payload to encode.

    .PARAMETER ECCLevel
        Error-correction level: L, M, Q, or H.

    .OUTPUTS
        QRCoder.QRCodeData.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter()]
        [ValidateSet('L', 'M', 'Q', 'H')]
        [string]$ECCLevel = 'Q'
    )

    $generator = [QRCoder.QRCodeGenerator]::new()
    return $generator.CreateQrCode(
        $Text,
        [QRCoder.QRCodeGenerator+ECCLevel]$ECCLevel,
        $true,
        $false,
        [QRCoder.QRCodeGenerator+EciMode]::Utf8,
        -1
    )
}
