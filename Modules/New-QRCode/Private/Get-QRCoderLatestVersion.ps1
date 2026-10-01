function Get-QRCoderLatestVersion {
    <#
    .SYNOPSIS
        Returns the newest stable QRCoder version published on nuget.org.

    .OUTPUTS
        System.String. A semantic version, e.g. 1.8.0.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $indexUrl = 'https://api.nuget.org/v3-flatcontainer/qrcoder/index.json'
    $index = Invoke-RestMethod -Uri $indexUrl -ErrorAction Stop
    $stable = @($index.versions | Where-Object { $_ -notmatch '-' })
    if ($stable.Count -eq 0) {
        throw [System.IO.InvalidDataException]::new('No stable QRCoder versions were returned by nuget.org.')
    }
    return $stable[-1]
}
