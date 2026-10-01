function Request-QRCoderInstall {
    <#
    .SYNOPSIS
        Asks the user, once, whether to download QRCoder.

    .DESCRIPTION
        Returns $true when the user accepts. Non-interactive hosts and redirected
        input return $false so the caller can fail with instructions instead of
        blocking on a prompt nobody can see.

    .OUTPUTS
        System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) {
        return $false
    }

    Write-Host ''
    Write-Host 'QRCoder is required to generate QR codes and is not installed.' -ForegroundColor Yellow
    Write-Host 'It is not bundled with this module; it will be downloaded from nuget.org.' -ForegroundColor DarkGray

    $answer = Read-Host 'Download and install QRCoder now? [Y/n]'
    if ([string]::IsNullOrWhiteSpace($answer)) { return $true }
    return $answer.Trim().ToLowerInvariant() -in @('y', 'yes')
}
