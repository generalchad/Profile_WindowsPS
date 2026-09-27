function Get-PrimaryIPv4Address {
    <#
    .SYNOPSIS
        Detects the primary LAN IPv4 address using route metrics and adapter filtering.

    .DESCRIPTION
        Selects the IPv4 address associated with the active default gateway route with the
        lowest metric, filtering out virtual and container network adapters.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $virtualPattern = '(?i)vEthernet|WSL|VMnet|Docker|Tailscale|Loopback'
    $defaultRoutes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object { [int]$_.RouteMetric + [int]$_.InterfaceMetric })

    $primaryRoute = $defaultRoutes | Where-Object { $_.InterfaceAlias -notmatch $virtualPattern } | Select-Object -First 1
    if (-not $primaryRoute) {
        $primaryRoute = $defaultRoutes | Select-Object -First 1
    }

    if ($primaryRoute) {
        $ip = @(Get-NetIPAddress -InterfaceIndex $primaryRoute.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.PrefixOrigin -ne 'WellKnown' -and $_.IPAddress -notlike '169.254.*' } |
            Select-Object -ExpandProperty IPAddress -First 1)
        if ($ip.Count -gt 0) { return $ip[0] }
    }

    $fallback = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PrefixOrigin -ne 'WellKnown' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.InterfaceAlias -notmatch $virtualPattern
        } | Select-Object -ExpandProperty IPAddress -First 1)

    if ($fallback.Count -gt 0) { return $fallback[0] }

    $anyNonApipa = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.PrefixOrigin -ne 'WellKnown' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -ExpandProperty IPAddress -First 1)

    return if ($anyNonApipa.Count -gt 0) { $anyNonApipa[0] } else { $null }
}
