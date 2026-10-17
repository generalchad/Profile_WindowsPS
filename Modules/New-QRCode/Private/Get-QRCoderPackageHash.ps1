function Get-QRCoderPackageHash {
    <#
    .SYNOPSIS
        Returns the expected SHA-512 of a QRCoder .nupkg as an uppercase hex string.

    .DESCRIPTION
        The pinned version uses the hash stored in the module, so a compromised or
        spoofed feed cannot substitute the default download. Any other version
        falls back to the packageHash nuget.org publishes in its catalog, which
        catches corruption and tampering in transit but trusts nuget.org itself.

    .PARAMETER Version
        The QRCoder version being downloaded.

    .OUTPUTS
        System.String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    if ($Version -eq $script:QRCoderPinnedVersion) {
        return $script:QRCoderPinnedSha512
    }

    Write-Warning "QRCoder $Version is not the pinned release ($script:QRCoderPinnedVersion); verifying it against nuget.org's published hash only."
    $leaf = Invoke-RestMethod -Uri ('https://api.nuget.org/v3/registration5-gz-semver2/qrcoder/{0}.json' -f $Version.ToLowerInvariant()) -ErrorAction Stop
    $catalog = Invoke-RestMethod -Uri $leaf.catalogEntry -ErrorAction Stop
    if ($catalog.packageHashAlgorithm -ne 'SHA512' -or [string]::IsNullOrWhiteSpace($catalog.packageHash)) {
        throw [System.IO.InvalidDataException]::new("nuget.org did not publish a SHA512 package hash for QRCoder $Version.")
    }
    return [System.Convert]::ToHexString([System.Convert]::FromBase64String($catalog.packageHash))
}
