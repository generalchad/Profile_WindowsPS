function Get-QRCodeSlug {
    <#
    .SYNOPSIS
        Builds a filesystem-safe name from the first line of the QR code text.

    .PARAMETER Text
        The payload being encoded.

    .OUTPUTS
        System.String. A lowercase slug, or an empty string when nothing usable
        remains (the caller substitutes a default name).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $firstLine = ($Text -split "`r?`n", 2)[0]
    $slug = ($firstLine -replace '[^\p{L}\p{Nd}]+', '-').Trim('-').ToLowerInvariant()
    if ($slug.Length -gt 40) {
        $slug = $slug.Substring(0, 40).Trim('-')
    }
    return $slug
}
