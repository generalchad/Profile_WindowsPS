function Get-ScanShareGuiSplat {
    <#
    .SYNOPSIS
        Maps raw Show-ScanShare field values to a splat hashtable for New-ScanShare.

    .DESCRIPTION
        Converts the setup dialog's text and checkbox values into the parameter set
        New-ScanShare expects: a plain password becomes a SecureString, a
        comma/semicolon/whitespace separated address list becomes a string array, and
        blank optional fields are omitted so New-ScanShare's own defaults apply.

    .PARAMETER Path
        Destination folder text.

    .PARAMETER ShareName
        Share name text.

    .PARAMETER UserName
        Account name text.

    .PARAMETER Password
        Plain password text. Converted to a SecureString. Omitted when blank.

    .PARAMETER RemoteAddress
        One or more remote address ranges. Omitted when blank (defaults to LocalSubnet).

    .PARAMETER ResetPassword
        Whether -ResetPassword should be passed.

    .PARAMETER SkipFirewall
        Whether -SkipFirewall should be passed.

    .PARAMETER SkipVerification
        Whether -SkipVerification should be passed.

    .OUTPUTS
        Hashtable suitable for splatting into New-ScanShare.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][string]$Path,
        [Parameter()][string]$ShareName,
        [Parameter()][string]$UserName,
        [Parameter()][string]$Password,
        [Parameter()][string]$RemoteAddress,
        [Parameter()][switch]$ResetPassword,
        [Parameter()][switch]$SkipFirewall,
        [Parameter()][switch]$SkipVerification
    )

    $splat = @{}

    if (-not [string]::IsNullOrWhiteSpace($Path)) { $splat['Path'] = $Path.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($ShareName)) { $splat['ShareName'] = $ShareName.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($UserName)) { $splat['UserName'] = $UserName.Trim() }

    if (-not [string]::IsNullOrEmpty($Password)) {
        $splat['Password'] = ConvertTo-SecureString -String $Password -AsPlainText -Force
    }

    if (-not [string]::IsNullOrWhiteSpace($RemoteAddress)) {
        $addresses = @($RemoteAddress -split '[,;\s]+' | Where-Object { $_ })
        if ($addresses.Count -gt 0) { $splat['RemoteAddress'] = $addresses }
    }

    if ($ResetPassword) { $splat['ResetPassword'] = $true }
    if ($SkipFirewall) { $splat['SkipFirewall'] = $true }
    if ($SkipVerification) { $splat['SkipVerification'] = $true }

    $splat
}
