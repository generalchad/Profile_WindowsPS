function Get-PrinterInfo {
    <#
    .SYNOPSIS
        Queries a network printer or MFP over SNMP for its model, serial number,
        page count, status and supply levels.

    .DESCRIPTION
        Uses the standard Printer MIB (RFC 3805) and Host Resources MIB, so it works
        across vendors (Xerox, Kyocera, HP, Canon, Ricoh, Brother, Konica Minolta...)
        without vendor-specific OIDs. Needs nothing installed: SNMP is spoken
        directly over UDP 161.

        SNMP v1 fails an entire request when any OID is unknown, so on a v1 error
        each OID is retried individually and missing ones are simply left blank.

    .PARAMETER ComputerName
        Printer IP address or hostname. Accepts pipeline input.

    .PARAMETER Community
        SNMP read community. Defaults to 'public', the factory default on most MFPs.

    .PARAMETER Version
        SNMP version: '2c' (default) or '1' for older devices.

    .PARAMETER Timeout
        Receive timeout in milliseconds. Defaults to 2000.

    .OUTPUTS
        PSCustomObject per printer: ComputerName, Reachable, Model, Name, Serial,
        Location, Contact, Uptime, PageCount, Status, Supplies (array of
        Name/Level/Max/Percent), Error.

    .EXAMPLE
        Get-PrinterInfo 192.168.1.50

    .EXAMPLE
        Get-PrinterInfo 192.168.1.50 | Select-Object -ExpandProperty Supplies

        Shows toner/drum/waste levels as a table.

    .EXAMPLE
        '192.168.1.50', '192.168.1.51' | Get-PrinterInfo | Format-Table ComputerName, Model, Serial, PageCount, Status

    .NOTES
        No reply usually means SNMP is disabled on the device, the community is
        wrong, or UDP 161 is filtered - SNMP gives no error in any of those cases.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('IPAddress', 'HostName', 'Address')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [ValidateNotNullOrEmpty()]
        [string]$Community = 'public',

        [ValidateSet('1', '2c')]
        [string]$Version = '2c',

        [ValidateRange(250, 30000)]
        [int]$Timeout = 2000
    )

    begin {
        $scalarOids = [ordered]@{
            Description = '1.3.6.1.2.1.1.1.0'
            Contact     = '1.3.6.1.2.1.1.4.0'
            Name        = '1.3.6.1.2.1.1.5.0'
            Location    = '1.3.6.1.2.1.1.6.0'
            Uptime      = '1.3.6.1.2.1.1.3.0'
            Model       = '1.3.6.1.2.1.25.3.2.1.3.1'      # hrDeviceDescr
            Status      = '1.3.6.1.2.1.25.3.5.1.1.1'      # hrPrinterStatus
            Serial      = '1.3.6.1.2.1.43.5.1.1.17.1'     # prtGeneralSerialNumber
            PageCount   = '1.3.6.1.2.1.43.10.2.1.4.1.1'   # prtMarkerLifeCount
        }

        # hrPrinterStatus values (RFC 2790).
        $statusText = @{ 1 = 'Other'; 2 = 'Unknown'; 3 = 'Idle'; 4 = 'Printing'; 5 = 'Warmup' }

        # Supply rows are indexed 1..N; MFPs rarely have more than ~12 (CMYK toner,
        # drums, waste, fuser, transfer belt). Probing a fixed window avoids needing
        # GETNEXT/walk support.
        $maxSupplies = 16

        $getSafe = {
            param($address, [string[]]$oids)
            $snmp = @{ Address = $address; Community = $Community; Version = $Version; Timeout = $Timeout }
            try {
                Invoke-SnmpGet @snmp -Oid $oids
            }
            catch [System.InvalidOperationException] {
                $merged = @{}
                foreach ($o in $oids) {
                    try { $merged += Invoke-SnmpGet @snmp -Oid $o } catch [System.InvalidOperationException] { }
                }
                $merged
            }
        }
    }

    process {
        foreach ($target in $ComputerName) {
            $result = [ordered]@{
                ComputerName = $target
                Reachable    = $false
                Model        = $null
                Name         = $null
                Serial       = $null
                Location     = $null
                Contact      = $null
                Uptime       = $null
                PageCount    = $null
                Status       = $null
                Supplies     = @()
                Error        = $null
            }

            try {
                $scalars = & $getSafe $target ([string[]]$scalarOids.Values)
                $result.Reachable = $true

                $result.Model = $scalars[$scalarOids.Model]
                if (-not $result.Model) { $result.Model = $scalars[$scalarOids.Description] }
                $result.Name = $scalars[$scalarOids.Name]
                $result.Serial = $scalars[$scalarOids.Serial]
                $result.Location = $scalars[$scalarOids.Location]
                $result.Contact = $scalars[$scalarOids.Contact]
                $result.PageCount = $scalars[$scalarOids.PageCount]
                if ($null -ne $scalars[$scalarOids.Uptime]) {
                    # TimeTicks are hundredths of a second.
                    $result.Uptime = [timespan]::FromMilliseconds([double]$scalars[$scalarOids.Uptime] * 10)
                }
                $code = $scalars[$scalarOids.Status]
                if ($null -ne $code) { $result.Status = $statusText[[int]$code] ?? "Code $code" }

                $supplyOids = foreach ($i in 1..$maxSupplies) {
                    "1.3.6.1.2.1.43.11.1.1.6.1.$i"   # prtMarkerSuppliesDescription
                    "1.3.6.1.2.1.43.11.1.1.8.1.$i"   # prtMarkerSuppliesMaxCapacity
                    "1.3.6.1.2.1.43.11.1.1.9.1.$i"   # prtMarkerSuppliesLevel
                }
                $supplyData = & $getSafe $target ([string[]]$supplyOids)

                $result.Supplies = @(foreach ($i in 1..$maxSupplies) {
                        $name = $supplyData["1.3.6.1.2.1.43.11.1.1.6.1.$i"]
                        if (-not $name) { continue }
                        $max = $supplyData["1.3.6.1.2.1.43.11.1.1.8.1.$i"]
                        $level = $supplyData["1.3.6.1.2.1.43.11.1.1.9.1.$i"]
                        # RFC 3805: -1 = unrestricted, -2 = unknown, -3 = "some remaining".
                        $percent = if ($null -ne $max -and $max -gt 0 -and $null -ne $level -and $level -ge 0) {
                            [math]::Round(100 * $level / $max)
                        }
                        elseif ($level -eq -3) { 'Low' }
                        else { $null }
                        [pscustomobject]@{ Name = $name; Level = $level; Max = $max; Percent = $percent }
                    })
            }
            catch {
                # .NET method calls surface as MethodInvocationException; the socket
                # error is the inner exception.
                $err = $_.Exception
                while ($err.InnerException -and $err -isnot [System.Net.Sockets.SocketException]) {
                    $err = $err.InnerException
                }
                $noReply = $err -is [System.Net.Sockets.SocketException] -and
                    $err.SocketErrorCode -in 'TimedOut', 'ConnectionReset'
                $result.Error = if ($noReply) {
                    "No SNMP reply (SNMP disabled, wrong community '$Community', or UDP 161 filtered)."
                }
                else {
                    $err.Message
                }
            }

            [pscustomobject]$result
        }
    }
}
