function Get-TargetAdapter {
    <#
    .SYNOPSIS
        Resolves the set of network adapters that a reset step should act on.

    .DESCRIPTION
        Preferred path uses Get-NetAdapter (NetAdapter module). When that module is
        unavailable (Server Core minimal installs, constrained endpoints, older
        builds) it falls back to parsing `netsh interface show interface`.

        With no -InterfaceAlias filter the default selection is every physical,
        non-hidden adapter whose status is Up. Pass -IncludeDisconnected to widen
        that to all physical adapters regardless of media state.

    .PARAMETER InterfaceAlias
        One or more adapter names. Wildcards are supported.

    .PARAMETER IncludeDisconnected
        Include adapters that are not currently Up.

    .OUTPUTS
        pscustomobject with Name, Status, and IsVirtual properties.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]] $InterfaceAlias,

        [switch] $IncludeDisconnected
    )

    $adapters = @()

    if (Get-Command -Name Get-NetAdapter -ErrorAction SilentlyContinue) {
        try {
            $adapters = Get-NetAdapter -Physical -ErrorAction Stop |
                ForEach-Object {
                    [pscustomobject]@{
                        Name      = $_.Name
                        Status    = $_.Status
                        IsVirtual = $_.Virtual
                    }
                }
        }
        catch {
            Write-Verbose "Get-NetAdapter failed, falling back to netsh: $($_.Exception.Message)"
            $adapters = @()
        }
    }

    if (-not $adapters -or $adapters.Count -eq 0) {
        # Fallback: parse `netsh interface show interface`.
        # Columns: Admin State | State | Type | Interface Name
        $raw = & netsh.exe interface show interface 2>&1
        foreach ($line in $raw) {
            $t = "$line".Trim()
            if (-not $t) { continue }
            if ($t -match '^(Admin\s+State|-{3,})') { continue }

            $parts = $t -split '\s{2,}'
            if ($parts.Count -lt 4) {
                $parts = $t -split '\s+', 4
            }
            if ($parts.Count -lt 4) { continue }

            $name = $parts[3].Trim()
            if (-not $name) { continue }

            $adapters += [pscustomobject]@{
                Name      = $name
                Status    = $parts[1].Trim()
                IsVirtual = $false
            }
        }
    }

    # Drop obvious virtual/tunnel plumbing that should never be bounced blindly.
    $adapters = $adapters | Where-Object {
        -not $_.IsVirtual -and
        $_.Name -notmatch '(?i)loopback|isatap|teredo|6to4|wan miniport'
    }

    if ($InterfaceAlias) {
        $matched = foreach ($pattern in $InterfaceAlias) {
            $adapters | Where-Object { $_.Name -like $pattern }
        }
        $adapters = $matched | Sort-Object -Property Name -Unique

        if (-not $adapters) {
            Write-Warning "No network adapters matched: $($InterfaceAlias -join ', ')"
        }
    }
    elseif (-not $IncludeDisconnected) {
        $adapters = $adapters | Where-Object { $_.Status -in @('Up', 'Connected') }
    }

    $adapters
}
