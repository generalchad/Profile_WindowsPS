# Caches the curated OUI table across invocations within the module session.
$script:OuiTable = @{
    # Xerox
    '0000AA' = 'Xerox'; '000014' = 'Xerox'; '0000E8' = 'Xerox'; '0001A4' = 'Xerox'
    '000A00' = 'Xerox'; '001083' = 'Xerox'; '001268' = 'Xerox'; '001599' = 'Xerox'
    '00253C' = 'Xerox'; '080037' = 'Xerox'; '9C934E' = 'Xerox'
    # HP / Hewlett Packard
    '0001E6' = 'HP'; '000802' = 'HP'; '000E7F' = 'HP'; '00110A' = 'HP'
    '001438' = 'HP'; '001635' = 'HP'; '0017A4' = 'HP'; '0018FE' = 'HP'
    '001B78' = 'HP'; '001E0B' = 'HP'; '00215A' = 'HP'; '002481' = 'HP'
    '0025B3' = 'HP'; '002655' = 'HP'; '101F74' = 'HP'; '186024' = 'HP'
    '2C4138' = 'HP'; '30E171' = 'HP'; '3CD92B' = 'HP'; '645106' = 'HP'
    '78ACC0' = 'HP'; '843497' = 'HP'; 'A45D36' = 'HP'; 'AC162D' = 'HP'
    'B499BA' = 'HP'; 'C8D3FF' = 'HP'; 'F0921C' = 'HP'
    # Canon
    '000085' = 'Canon'; '001E8F' = 'Canon'; '002B67' = 'Canon'; '008087' = 'Canon'
    '001BA9' = 'Canon'; '0000F0' = 'Canon'; '84BA3B' = 'Canon'; '001A8C' = 'Canon'
    '180CAC' = 'Canon'; '7085C2' = 'Canon'
    # Ricoh
    '002673' = 'Ricoh'; '001E2A' = 'Ricoh'; '000024' = 'Ricoh'; '0002B7' = 'Ricoh'
    '001824' = 'Ricoh'; '006067' = 'Ricoh'
    # Konica Minolta
    '00206B' = 'Konica Minolta'; '001BDC' = 'Konica Minolta'; '001F9D' = 'Konica Minolta'; '000BAB' = 'Konica Minolta'
    # Kyocera
    '000A8A' = 'Kyocera'; '0017C8' = 'Kyocera'; '002507' = 'Kyocera'; '00C0EE' = 'Kyocera'
    # Brother
    '008077' = 'Brother'; '30055C' = 'Brother'; '000E8E' = 'Brother'; '346895' = 'Brother'; 'E45F01' = 'Brother'
    # Lexmark
    '000400' = 'Lexmark'; '002000' = 'Lexmark'; '000777' = 'Lexmark'; '001125' = 'Lexmark'
    '0021B7' = 'Lexmark'; '4480EB' = 'Lexmark'; 'AC7A4D' = 'Lexmark'
    # Epson
    '000048' = 'Epson'; '0026AB' = 'Epson'; 'AC1702' = 'Epson'; '08EB74' = 'Epson'
    # Sharp / Toshiba / OKI / Zebra
    '00019F' = 'Sharp'; '08001F' = 'Sharp'; '000039' = 'Toshiba'; '000092' = 'OKI'; '0004F9' = 'Zebra'
    # Dell
    '000874' = 'Dell'; '001422' = 'Dell'; '1866DA' = 'Dell'; '24B6FD' = 'Dell'; 'B82A72' = 'Dell'
    # Network / Infra
    '00000C' = 'Cisco'; '000142' = 'Cisco'; '000164' = 'Cisco'; '00156D' = 'Ubiquiti'; '24A43C' = 'Ubiquiti'
    '68D79A' = 'Ubiquiti'; '788A20' = 'Ubiquiti'; '802AA8' = 'Ubiquiti'; 'F09FC2' = 'Ubiquiti'
    '488F5A' = 'Mikrotik'; '6C3B6B' = 'Mikrotik'; 'B869F4' = 'Mikrotik'; 'D4CA6D' = 'Mikrotik'
    'A0AD9F' = 'ASUS'; '04D9F5' = 'ASUS'; '086266' = 'ASUS'; '107B44' = 'ASUS'; '14DDA9' = 'ASUS'
    '0014D1' = 'TP-Link'; '001D0F' = 'TP-Link'; '002586' = 'TP-Link'; '0418D6' = 'TP-Link'
    '000FB5' = 'Netgear'; '00146C' = 'Netgear'; '00184D' = 'Netgear'; '001F33' = 'Netgear'
    '00180A' = 'Cisco Meraki'; '00090F' = 'Fortinet'; '704CA5' = 'Fortinet'; '00045A' = 'SonicWall'
    '001132' = 'Synology'; '00089B' = 'QNAP'; 'B827EB' = 'Raspberry Pi'; 'DCA632' = 'Raspberry Pi'
    # Virtualization
    '005056' = 'VMware'; '000C29' = 'VMware'; '00155D' = 'Microsoft'
}

function Resolve-OuiVendor {
    param([string]$MacAddress)
    if ([string]::IsNullOrWhiteSpace($MacAddress)) { return 'Unknown' }
    $clean = ($MacAddress -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($clean.Length -ge 6) {
        $oui = $clean.Substring(0, 6)
        if ($script:OuiTable.ContainsKey($oui)) {
            return $script:OuiTable[$oui]
        }
    }
    return 'Unknown'
}

function Get-SubnetIpRange {
    param([string]$Subnet)

    if ($Subnet -match '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') {
        $baseIp = $Matches[1]
        $prefix = [int]$Matches[2]
        if ($prefix -lt 16 -or $prefix -gt 30) {
            throw "Prefix /$prefix is out of sweep range (supported /16 to /30)"
        }

        $mask = [uint32]([uint32]::MaxValue -shl (32 - $prefix))
        $ipBytes = [System.Net.IPAddress]::Parse($baseIp).GetAddressBytes()
        if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($ipBytes) }
        $ipInt = [System.BitConverter]::ToUInt32($ipBytes, 0)

        $netInt = $ipInt -band $mask
        $bcastInt = $netInt -bor (-bnot $mask)
        $start = $netInt + 1
        $end = $bcastInt - 1

        $ips = [System.Collections.Generic.List[string]]::new()
        for ($curr = $start; $curr -le $end; $curr++) {
            $bytes = [System.BitConverter]::GetBytes([uint32]$curr)
            if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($bytes) }
            $ips.Add(([System.Net.IPAddress]::new($bytes)).ToString())
        }
        return $ips
    }

    if ($Subnet -match '^(\d{1,3}(?:\.\d{1,3}){3})-(\d{1,3}(?:\.\d{1,3}){3})$') {
        $ip1 = [System.Net.IPAddress]::Parse($Matches[1]).GetAddressBytes()
        $ip2 = [System.Net.IPAddress]::Parse($Matches[2]).GetAddressBytes()
        if ([System.BitConverter]::IsLittleEndian) {
            [System.Array]::Reverse($ip1)
            [System.Array]::Reverse($ip2)
        }
        $start = [System.BitConverter]::ToUInt32($ip1, 0)
        $end = [System.BitConverter]::ToUInt32($ip2, 0)

        $ips = [System.Collections.Generic.List[string]]::new()
        for ($curr = $start; $curr -le $end; $curr++) {
            $bytes = [System.BitConverter]::GetBytes([uint32]$curr)
            if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($bytes) }
            $ips.Add(([System.Net.IPAddress]::new($bytes)).ToString())
        }
        return $ips
    }

    throw "Invalid subnet format '$Subnet'. Expected CIDR (e.g. 192.168.1.0/24) or range (192.168.1.1-192.168.1.50)."
}

function Find-NetworkDevice {
    <#
    .SYNOPSIS
        Sweeps local or specified subnets to discover network devices, MAC addresses, OUI vendors, and printer services.

    .DESCRIPTION
        Performs a fast parallel ICMP sweep over the subnet, inspects the local ARP cache for MAC addresses,
        looks up vendor OUIs via a bundled offline database, probes common printer ports (HTTP, HTTPS, SMB,
        LPD, IPP, JetDirect 9100, and SNMP 161), and flags likely printers. Output pipes directly into
        Get-PrinterInfo by IPAddress / ComputerName.

    .PARAMETER Subnet
        One or more subnets in CIDR format (e.g., '192.168.1.0/24') or IP range ('192.168.1.1-192.168.1.100').
        If omitted, automatically sweeps the local subnets of all active physical network adapters.

    .PARAMETER ProbePorts
        Probes common device and printer ports (80, 443, 445, 515, 631, 9100, 161/udp).

    .PARAMETER Ports
        Custom list of TCP/UDP ports to probe when -ProbePorts is used. Defaults to 80, 443, 445, 515, 631, 9100, 161.

    .PARAMETER PrinterOnly
        Filters discovered devices to only those flagged as likely printers or MFPs.

    .PARAMETER ThrottleLimit
        Maximum concurrent threads for the parallel ping sweep. Defaults to 64.

    .PARAMETER PingTimeoutMs
        Ping response timeout per target in milliseconds. Defaults to 1000.

    .PARAMETER ProbeTimeoutMs
        Timeout in milliseconds for port connect probes. Defaults to 1000.

    .OUTPUTS
        PSCustomObject with IPAddress, ComputerName, HostName, MacAddress, Vendor, IsLikelyPrinter, OpenPorts, HasSnmp, and LatencyMs.

    .EXAMPLE
        Find-NetworkDevice

    .EXAMPLE
        Find-NetworkDevice -Subnet '192.168.50.0/24' -ProbePorts

    .EXAMPLE
        Find-NetworkDevice -ProbePorts -PrinterOnly | Get-PrinterInfo
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string[]]$Subnet,

        [Parameter()]
        [switch]$ProbePorts,

        [Parameter()]
        [int[]]$Ports = @(80, 443, 445, 515, 631, 9100, 161),

        [Parameter()]
        [switch]$PrinterOnly,

        [Parameter()]
        [ValidateRange(1, 256)]
        [int]$ThrottleLimit = 64,

        [Parameter()]
        [ValidateRange(100, 10000)]
        [int]$PingTimeoutMs = 1000,

        [Parameter()]
        [ValidateRange(200, 10000)]
        [int]$ProbeTimeoutMs = 1000
    )

    process {
        # 1. Determine targets to sweep
        $targets = [System.Collections.Generic.List[string]]::new()
        if ($Subnet -and $Subnet.Count -gt 0) {
            foreach ($s in $Subnet) {
                $subIps = Get-SubnetIpRange -Subnet $s
                foreach ($ip in $subIps) { if (-not $targets.Contains($ip)) { $targets.Add($ip) } }
            }
        } else {
            # Find active non-virtual/non-loopback IPv4 adapters
            $activeIps = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
                    $_.InterfaceAlias -notmatch '(?i)vEthernet|WSL|Docker|Loopback'
                })

            if ($activeIps.Count -eq 0) {
                # Fall back to any non-loopback IPv4
                $activeIps = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -notmatch '^127\.' })
            }

            foreach ($ipObj in $activeIps) {
                if ($ipObj.PrefixLength -and $ipObj.PrefixLength -ge 16 -and $ipObj.PrefixLength -le 30) {
                    $cidr = "$($ipObj.IPAddress)/$($ipObj.PrefixLength)"
                    try {
                        $subIps = Get-SubnetIpRange -Subnet $cidr
                        foreach ($ip in $subIps) { if (-not $targets.Contains($ip)) { $targets.Add($ip) } }
                    } catch {}
                }
            }
        }

        if ($targets.Count -eq 0) {
            Write-Warning "No active network subnets found to sweep. Specify -Subnet explicitly."
            return
        }

        Write-Progress -Activity 'Finding Network Devices' -Status "Pinging $($targets.Count) hosts..." -PercentComplete 10

        # 2. Parallel Ping Sweep (Populates kernel ARP table even when ICMP is blocked)
        $pingTimeout = $PingTimeoutMs
        $pingResults = $targets | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            $ping = [System.Net.NetworkInformation.Ping]::new()
            try {
                $reply = $ping.Send($_, $using:pingTimeout)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    [pscustomobject]@{
                        IPAddress = $_
                        LatencyMs = $reply.RoundtripTime
                    }
                }
            } catch {}
            finally { $ping.Dispose() }
        }

        $pingMap = @{}
        if ($pingResults) {
            foreach ($pr in $pingResults) { $pingMap[$pr.IPAddress] = $pr.LatencyMs }
        }

        Write-Progress -Activity 'Finding Network Devices' -Status "Reading ARP cache and discovering devices..." -PercentComplete 40

        # 3. Read ARP Table for MAC Addresses
        $arpTable = @{}
        try {
            Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.LinkLayerAddress -match '^[0-9a-fA-F]{2}' -and
                    $_.LinkLayerAddress -notmatch '^(00-00-00-00-00-00|FF-FF-FF-FF-FF-FF|01-00-5E)' -and
                    $_.State -ne 'Unreachable'
                } |
                ForEach-Object { $arpTable[$_.IPAddress] = $_.LinkLayerAddress.ToUpperInvariant().Replace(':', '-') }
        } catch {}

        # Fallback to arp -a if Get-NetNeighbor returned nothing
        if ($arpTable.Count -eq 0) {
            try {
                $arpOutput = arp -a
                foreach ($line in $arpOutput) {
                    if ($line -match '(\d{1,3}(?:\.\d{1,3}){3})\s+([0-9a-fA-F-]{17})') {
                        $ipPart = $Matches[1]
                        $macPart = $Matches[2].ToUpperInvariant().Replace(':', '-')
                        if ($macPart -notmatch '^(00-00-00-00-00-00|FF-FF-FF-FF-FF-FF|01-00-5E)') {
                            $arpTable[$ipPart] = $macPart
                        }
                    }
                }
            } catch {}
        }

        # Consolidate responsive hosts: those answering ICMP or registered with valid MAC in ARP
        $discoveredIps = [System.Collections.Generic.List[string]]::new()
        foreach ($t in $targets) {
            if ($pingMap.ContainsKey($t) -or $arpTable.ContainsKey($t)) {
                if (-not $discoveredIps.Contains($t)) { $discoveredIps.Add($t) }
            }
        }

        if ($discoveredIps.Count -eq 0) {
            Write-Progress -Activity 'Finding Network Devices' -Completed
            Write-Verbose "Subnet sweep completed. No responsive hosts or ARP entries found."
            return
        }

        # 4. Process each live host (Hostname, OUI, Ports)
        $results = [System.Collections.Generic.List[object]]::new()
        $totalLive = $discoveredIps.Count
        $counter = 0

        # Standard SNMPv2c GET sysDescr.0 packet payload for port 161 probe
        $snmpPacket = [byte[]]@(
            0x30, 0x29, 0x02, 0x01, 0x01, 0x04, 0x06, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63,
            0xa0, 0x1c, 0x02, 0x04, 0x00, 0x00, 0x00, 0x01, 0x02, 0x01, 0x00, 0x02, 0x01,
            0x00, 0x30, 0x0e, 0x30, 0x0c, 0x06, 0x08, 0x2b, 0x06, 0x01, 0x02, 0x01, 0x01,
            0x01, 0x00, 0x05, 0x00
        )

        foreach ($ip in $discoveredIps) {
            $counter++
            Write-Progress -Activity 'Finding Network Devices' -Status "Inspecting $ip ($counter of $totalLive)..." -PercentComplete (50 + [int](($counter / $totalLive) * 45))

            $mac = $arpTable[$ip]
            $vendor = if ($mac) { Resolve-OuiVendor -MacAddress $mac } else { 'Unknown' }
            $latency = if ($pingMap.ContainsKey($ip)) { $pingMap[$ip] } else { $null }

            # Reverse DNS lookup with quick fail
            $hostName = $null
            try {
                $dnsTask = [System.Net.Dns]::GetHostEntryAsync($ip)
                if ($dnsTask.Wait(400)) {
                    $hostName = $dnsTask.Result.HostName
                }
            } catch {}

            $openPorts = [System.Collections.Generic.List[int]]::new()
            $hasSnmp = $false

            if ($ProbePorts) {
                foreach ($port in $Ports) {
                    if ($port -eq 161) {
                        # SNMP over UDP probe
                        $udp = [System.Net.Sockets.UdpClient]::new()
                        $udp.Client.ReceiveTimeout = $ProbeTimeoutMs
                        $udp.Client.SendTimeout = $ProbeTimeoutMs
                        try {
                            $endpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($ip), 161)
                            [void]$udp.Send($snmpPacket, $snmpPacket.Length, $endpoint)
                            $remoteEp = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
                            $recv = $udp.Receive([ref]$remoteEp)
                            if ($recv.Length -gt 0) {
                                $openPorts.Add(161)
                                $hasSnmp = $true
                            }
                        } catch {}
                        finally { $udp.Dispose() }
                    } else {
                        # TCP Port Probe
                        $tcp = [System.Net.Sockets.TcpClient]::new()
                        try {
                            $async = $tcp.BeginConnect($ip, $port, $null, $null)
                            if ($async.AsyncWaitHandle.WaitOne($ProbeTimeoutMs, $false)) {
                                $tcp.EndConnect($async)
                                if ($tcp.Connected) {
                                    $openPorts.Add($port)
                                }
                            }
                        } catch {}
                        finally {
                            $tcp.Close()
                            $tcp.Dispose()
                        }
                    }
                }
            }

            # Printer classification heuristics:
            # - Printer ports open: 515 (LPD), 631 (IPP), 9100 (RAW JetDirect)
            # - Open SNMP (161) with HTTP (80/443)
            # - Known printer manufacturer in OUI (Xerox, HP, Canon, Ricoh, Lexmark, Kyocera, Brother, Epson)
            $isPrinterVendor = $vendor -match '(?i)Xerox|HP|Canon|Ricoh|Lexmark|Kyocera|Brother|Konica|Epson|Sharp|Toshiba|OKI|Zebra'
            $hasPrintPort = ($openPorts -contains 515 -or $openPorts -contains 631 -or $openPorts -contains 9100)
            $isLikelyPrinter = $hasPrintPort -or ($isPrinterVendor -and ($openPorts.Count -gt 0 -or $mac))

            if ($PrinterOnly -and -not $isLikelyPrinter) {
                continue
            }

            $results.Add([pscustomobject]@{
                IPAddress       = $ip
                ComputerName    = $ip # Property alias ensures immediate pipeline binding to Get-PrinterInfo
                HostName        = $hostName
                MacAddress      = $mac
                Vendor          = $vendor
                IsLikelyPrinter = $isLikelyPrinter
                OpenPorts       = $openPorts.ToArray()
                HasSnmp         = $hasSnmp
                LatencyMs       = $latency
            })
        }

        Write-Progress -Activity 'Finding Network Devices' -Completed

        # Output results sorted by numerical IP address
        return ($results | Sort-Object { [version]$_.IPAddress })
    }
}

Export-ModuleMember -Function 'Find-NetworkDevice' -Alias 'Sweep-Subnet'
