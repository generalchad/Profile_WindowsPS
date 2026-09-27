function Get-NetworkDiagnostics {
    <#
    .SYNOPSIS
        Performs one-shot network triage for an unfamiliar site and emits a structured report object or exported artifact.

    .DESCRIPTION
        Inspects active network adapters, IP configuration, DHCP leases, gateway reachability,
        individual DNS server resolution for internal and public domains, TCP 443 / ICMP reachability,
        public egress path (direct, VPN, or Tailscale exit node), WinHTTP/WinINET proxy configurations,
        and local hosts-file overrides. Output can be exported directly to self-contained HTML or JSON for ticket attachment.

    .PARAMETER Target
        One or more public or remote hosts to test for ICMP and TCP 443 reachability.
        Defaults to '1.1.1.1', '8.8.8.8', and 'www.microsoft.com'.

    .PARAMETER DnsTestNames
        Domain names used to validate DNS server resolution. Defaults to an internal lookup
        ($env:USERDNSDOMAIN or gateway hostname) and a public lookup ('one.one.one.one').

    .PARAMETER IncludeTraceroute
        Runs a path trace to the primary gateway and first reachable public target.
        Disabled by default as hop-by-hop tracing through managed switches adds significant latency.

    .PARAMETER MaxHops
        Maximum hops to probe when -IncludeTraceroute is enabled. Defaults to 15.

    .PARAMETER TimeoutMs
        Timeout in milliseconds for individual socket and ping probes. Defaults to 2000.

    .PARAMETER AsHtml
        Outputs the report as a standalone HTML string instead of a PSCustomObject.

    .PARAMETER AsJson
        Outputs the report as formatted JSON string instead of a PSCustomObject.

    .PARAMETER Path
        File path to save the diagnostic report. If the path ends in .html (or -AsHtml is set),
        generates an HTML file. If the path ends in .json (or -AsJson is set), writes JSON.

    .PARAMETER PassThru
        Outputs the PSCustomObject even when -Path is specified.

    .EXAMPLE
        Get-NetworkDiagnostics

    .EXAMPLE
        Get-NetworkDiagnostics -Path C:\Support\SiteTriage.html

    .EXAMPLE
        Get-NetworkDiagnostics -IncludeTraceroute -AsJson
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object')]
    param(
        [Parameter(Position = 0)]
        [string[]]$Target = @('1.1.1.1', '8.8.8.8', 'www.microsoft.com'),

        [Parameter()]
        [string[]]$DnsTestNames,

        [Parameter()]
        [switch]$IncludeTraceroute,

        [Parameter()]
        [ValidateRange(1, 64)]
        [int]$MaxHops = 15,

        [Parameter()]
        [ValidateRange(250, 30000)]
        [int]$TimeoutMs = 2000,

        [Parameter(ParameterSetName = 'Html')]
        [switch]$AsHtml,

        [Parameter(ParameterSetName = 'Json')]
        [switch]$AsJson,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        Write-Progress -Activity 'Network Diagnostics' -Status 'Gathering adapter details...' -PercentComplete 10

        # --- 1. Adapters & IP Configuration ---
        $wmiAdapters = @{}
        try {
            Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -ErrorAction SilentlyContinue |
                ForEach-Object { $wmiAdapters[$_.Description] = $_ }
        } catch {}

        $netAdapters = @()
        try {
            $netAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        } catch {}

        $netIpConfigs = @{}
        try {
            Get-NetIPConfiguration -ErrorAction SilentlyContinue |
                ForEach-Object { $netIpConfigs[$_.InterfaceAlias] = $_ }
        } catch {}

        $adapterReport = [System.Collections.Generic.List[object]]::new()
        $gateways = [System.Collections.Generic.List[string]]::new()
        $discoveredDnsServers = [System.Collections.Generic.List[string]]::new()

        foreach ($adapter in $netAdapters) {
            $alias = $adapter.Name
            $wmi = $wmiAdapters[$adapter.InterfaceDescription]
            $ipCfg = $netIpConfigs[$alias]

            $ipv4List = @()
            $ipv6List = @()
            if ($ipCfg) {
                $ipv4List = @($ipCfg.IPv4Address | ForEach-Object { $_.IPAddress })
                $ipv6List = @($ipCfg.IPv6Address | ForEach-Object { $_.IPAddress })
            } else {
                try {
                    $ips = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
                    $ipv4List = @($ips | Where-Object { $_.AddressFamily -eq 'IPv4' } | ForEach-Object { $_.IPAddress })
                    $ipv6List = @($ips | Where-Object { $_.AddressFamily -eq 'IPv6' } | ForEach-Object { $_.IPAddress })
                } catch {}
            }

            $adapterGateways = @()
            if ($ipCfg -and $ipCfg.IPv4DefaultGateway) {
                $adapterGateways = @($ipCfg.IPv4DefaultGateway | ForEach-Object { $_.NextHop } | Where-Object { $_ })
            }
            foreach ($gw in $adapterGateways) {
                if ($gw -and -not $gateways.Contains($gw)) { $gateways.Add($gw) }
            }

            $adapterDns = @()
            if ($ipCfg -and $ipCfg.DNSServer) {
                $adapterDns = @($ipCfg.DNSServer | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
            }
            foreach ($dns in $adapterDns) {
                if ($dns -and -not $discoveredDnsServers.Contains($dns)) { $discoveredDnsServers.Add($dns) }
            }

            $dhcpEnabled = $wmi?.DHCPEnabled ?? $false
            $dhcpServer  = $wmi?.DHCPServer ?? ''
            $leaseObtained = $wmi?.DHCPLeaseObtained
            $leaseExpires  = $wmi?.DHCPLeaseExpires

            $adapterReport.Add([pscustomobject]@{
                Name                 = $alias
                InterfaceDescription = $adapter.InterfaceDescription
                Status               = $adapter.Status
                LinkSpeed            = $adapter.LinkSpeed
                MacAddress           = $adapter.MacAddress
                IPv4                 = $ipv4List
                IPv6                 = $ipv6List
                DHCPEnabled          = $dhcpEnabled
                DHCPServer           = $dhcpServer
                LeaseObtained        = $leaseObtained
                LeaseExpires         = $leaseExpires
                Gateways             = $adapterGateways
                DnsServers           = $adapterDns
            })
        }

        # --- 2. DNS Validation ---
        Write-Progress -Activity 'Network Diagnostics' -Status 'Testing DNS servers...' -PercentComplete 30

        $dnsLookupNames = [System.Collections.Generic.List[string]]::new()
        if ($DnsTestNames -and $DnsTestNames.Count -gt 0) {
            foreach ($name in $DnsTestNames) { $dnsLookupNames.Add($name) }
        } else {
            $internalCandidate = $env:USERDNSDOMAIN
            if (-not $internalCandidate) {
                $internalCandidate = if ($env:USERDOMAIN -and $env:USERDOMAIN -ne $env:COMPUTERNAME) { "$($env:USERDOMAIN).local" } else { "gateway.local" }
            }
            $dnsLookupNames.Add($internalCandidate)
            $dnsLookupNames.Add('one.one.one.one')
        }

        $dnsReport = [System.Collections.Generic.List[object]]::new()
        foreach ($server in $discoveredDnsServers) {
            foreach ($lookup in $dnsLookupNames) {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $resolvedIps = @()
                $dnsStatus = 'Failed'

                try {
                    $records = Resolve-DnsName -Name $lookup -Server $server -QuickTimeout -ErrorAction Stop
                    $resolvedIps = @($records | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress })
                    if ($resolvedIps.Count -gt 0) {
                        $dnsStatus = 'Success'
                    }
                } catch {
                    $dnsStatus = "Failed: $($_.Exception.Message)"
                }
                $sw.Stop()

                $dnsReport.Add([pscustomobject]@{
                    Server      = $server
                    Domain      = $lookup
                    Status      = $dnsStatus
                    ResolvedIPs = $resolvedIps
                    LatencyMs   = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
                })
            }
        }

        # --- 3. Reachability (Gateways + Targets) ---
        Write-Progress -Activity 'Network Diagnostics' -Status 'Probing gateway and internet reachability...' -PercentComplete 50

        $pingSender = [System.Net.NetworkInformation.Ping]::new()
        $reachabilityReport = [System.Collections.Generic.List[object]]::new()

        $allTargets = [System.Collections.Generic.List[string]]::new()
        foreach ($gw in $gateways) {
            if (-not $allTargets.Contains($gw)) { $allTargets.Add($gw) }
        }
        foreach ($t in $Target) {
            if (-not $allTargets.Contains($t)) { $allTargets.Add($t) }
        }

        foreach ($hostTarget in $allTargets) {
            # ICMP probe
            $icmpStatus = 'Failed'
            $icmpRttMs = $null
            try {
                $reply = $pingSender.Send($hostTarget, $TimeoutMs)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $icmpStatus = 'Reachable'
                    $icmpRttMs = $reply.RoundtripTime
                } else {
                    $icmpStatus = $reply.Status.ToString()
                }
            } catch {
                $icmpStatus = "Error: $($_.Exception.Message)"
            }

            # TCP 443 probe (ICMP is frequently filtered by ISP/enterprise policies)
            $tcpStatus = 'Failed'
            $tcpRttMs = $null
            $tcpClient = $null
            try {
                $tcpClient = [System.Net.Sockets.TcpClient]::new()
                $swTcp = [System.Diagnostics.Stopwatch]::StartNew()
                $asyncConnect = $tcpClient.BeginConnect($hostTarget, 443, $null, $null)
                if ($asyncConnect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
                    $tcpClient.EndConnect($asyncConnect)
                    $swTcp.Stop()
                    if ($tcpClient.Connected) {
                        $tcpStatus = 'Open'
                        $tcpRttMs = [math]::Round($swTcp.Elapsed.TotalMilliseconds, 1)
                    }
                } else {
                    $swTcp.Stop()
                    $tcpStatus = 'TimedOut'
                }
            } catch {
                $tcpStatus = "Closed/Filtered"
            } finally {
                if ($tcpClient) {
                    $tcpClient.Close()
                    $tcpClient.Dispose()
                }
            }

            $isGateway = $gateways.Contains($hostTarget)
            $reachabilityReport.Add([pscustomobject]@{
                Target     = $hostTarget
                Type       = if ($isGateway) { 'Gateway' } else { 'PublicTarget' }
                IcmpStatus = $icmpStatus
                IcmpRttMs  = $icmpRttMs
                Tcp443     = $tcpStatus
                Tcp443Ms   = $tcpRttMs
            })
        }
        $pingSender.Dispose()

        # --- 4. Traceroute (Optional) ---
        $traceReport = [System.Collections.Generic.List[object]]::new()
        if ($IncludeTraceroute) {
            Write-Progress -Activity 'Network Diagnostics' -Status 'Tracing route to external target...' -PercentComplete 65
            $traceTarget = $Target | Select-Object -First 1
            if ($traceTarget) {
                $tracer = [System.Net.NetworkInformation.Ping]::new()
                $buffer = [byte[]]::new(32)
                for ($hop = 1; $hop -le $MaxHops; $hop++) {
                    $opt = [System.Net.NetworkInformation.PingOptions]::new($hop, $true)
                    try {
                        $reply = $tracer.Send($traceTarget, $TimeoutMs, $buffer, $opt)
                        $hopAddress = if ($reply.Address) { $reply.Address.ToString() } else { '*' }
                        $hopRtt = if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success -or $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::TtlExpired) {
                            $reply.RoundtripTime
                        } else { $null }

                        $traceReport.Add([pscustomobject]@{
                            Hop     = $hop
                            Address = $hopAddress
                            Status  = $reply.Status.ToString()
                            RttMs   = $hopRtt
                        })

                        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                            break
                        }
                    } catch {
                        $traceReport.Add([pscustomobject]@{
                            Hop     = $hop
                            Address = '*'
                            Status  = 'Error'
                            RttMs   = $null
                        })
                    }
                }
                $tracer.Dispose()
            }
        }

        # --- 5. Egress & Public IP Path ---
        Write-Progress -Activity 'Network Diagnostics' -Status 'Detecting public egress and VPN states...' -PercentComplete 80

        $publicIp = 'Unavailable'
        try {
            $wc = [System.Net.Http.HttpClient]::new()
            $wc.Timeout = [System.TimeSpan]::FromMilliseconds(3000)
            $res = $wc.GetStringAsync('https://api.ipify.org').GetAwaiter().GetResult()
            if ($res) { $publicIp = $res.Trim() }
            $wc.Dispose()
        } catch {
            # Fallback to secondary endpoint
            try {
                $wc2 = [System.Net.Http.HttpClient]::new()
                $wc2.Timeout = [System.TimeSpan]::FromMilliseconds(3000)
                $res2 = $wc2.GetStringAsync('https://icanhazip.com').GetAwaiter().GetResult()
                if ($res2) { $publicIp = $res2.Trim() }
                $wc2.Dispose()
            } catch {}
        }

        $tailscaleState = 'NotInstalled'
        $tailscaleExitNode = $null
        if (Get-Command tailscale -ErrorAction SilentlyContinue) {
            try {
                $rawTs = & tailscale status --json | ConvertFrom-Json
                if ($rawTs.BackendState) {
                    $tailscaleState = $rawTs.BackendState
                    if ($rawTs.ExitNodeStatus) {
                        $tailscaleExitNode = $rawTs.ExitNodeStatus.Label ?? $rawTs.ExitNodeStatus.ID
                    } elseif ($rawTs.ExitNodeID) {
                        $tailscaleExitNode = $rawTs.ExitNodeID
                    }
                }
            } catch {
                $tailscaleState = 'Error'
            }
        }

        $vpnAdapters = @()
        try {
            $vpnAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -eq 'Up' -and ($_.InterfaceDescription -match 'VPN|WireGuard|TAP|TUN|Tailscale|Cisco|GlobalProtect|Fortinet') } |
                ForEach-Object { "$($_.Name) ($($_.InterfaceDescription))" })
        } catch {}

        $defaultRoutes = @()
        try {
            $defaultRoutes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Sort-Object RouteMetric |
                ForEach-Object { [pscustomobject]@{ NextHop = $_.NextHop; Metric = $_.RouteMetric; InterfaceIndex = $_.InterfaceIndex } })
        } catch {}

        # --- 6. Proxy Settings & Hosts File ---
        Write-Progress -Activity 'Network Diagnostics' -Status 'Checking proxy configurations and hosts file...' -PercentComplete 90

        $wininet = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        $wininetProxy = [pscustomobject]@{
            Enabled       = [bool]($wininet?.ProxyEnable)
            Server        = $wininet?.ProxyServer ?? ''
            AutoConfigUrl = $wininet?.AutoConfigURL ?? ''
        }

        $winhttpProxy = 'Direct'
        try {
            $winhttpOut = netsh winhttp show proxy
            if ($winhttpOut -match 'Proxy Server\(s\)\s*:\s*(.+)') {
                $winhttpProxy = $Matches[1].Trim()
            } elseif ($winhttpOut -match 'Direct access') {
                $winhttpProxy = 'Direct access (no proxy)'
            }
        } catch {}

        $hostsOverrides = [System.Collections.Generic.List[object]]::new()
        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
        if (Test-Path -LiteralPath $hostsPath) {
            try {
                $lines = [System.IO.File]::ReadAllLines($hostsPath)
                foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if ($trimmed -and -not $trimmed.StartsWith('#')) {
                        $parts = $trimmed -split '\s+', 2
                        if ($parts.Count -ge 2) {
                            $hostsOverrides.Add([pscustomobject]@{
                                IPAddress = $parts[0]
                                Hostnames = $parts[1]
                            })
                        }
                    }
                }
            } catch {}
        }

        Write-Progress -Activity 'Network Diagnostics' -Completed

        # --- 7. Synthesize Report Object ---
        $report = [pscustomobject]@{
            PSTypeName        = 'NetworkDiagnostics.Report'
            Timestamp         = [System.DateTime]::UtcNow
            ComputerName      = $env:COMPUTERNAME
            PublicIP          = $publicIp
            Egress = [pscustomobject]@{
                PublicIP          = $publicIp
                TailscaleState    = $tailscaleState
                TailscaleExitNode = $tailscaleExitNode
                ActiveVpnAdapters = $vpnAdapters
                DefaultRoutes     = $defaultRoutes
            }
            Adapters          = $adapterReport.ToArray()
            DnsValidation     = $dnsReport.ToArray()
            Reachability      = $reachabilityReport.ToArray()
            Traceroute        = $traceReport.ToArray()
            Proxy = [pscustomobject]@{
                WinINET = $wininetProxy
                WinHTTP = $winhttpProxy
            }
            HostsOverrides    = $hostsOverrides.ToArray()
        }

        # --- 8. Export or Return ---
        $htmlOutput = $null
        if ($AsHtml -or ($Path -and $Path.EndsWith('.html', [System.StringComparison]::OrdinalIgnoreCase))) {
            $htmlOutput = ConvertTo-NetworkDiagnosticsHtml -Report $report
        }

        if ($Path) {
            $targetDir = [System.IO.Path]::GetDirectoryName($Path)
            if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
                [System.IO.Directory]::CreateDirectory($targetDir) | Out-Null
            }

            if ($Path.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase) -or $AsJson) {
                $json = $report | ConvertTo-Json -Depth 6
                [System.IO.File]::WriteAllText($Path, $json, [System.Text.Encoding]::UTF8)
            } else {
                $htmlToWrite = if ($htmlOutput) { $htmlOutput } else { ConvertTo-NetworkDiagnosticsHtml -Report $report }
                [System.IO.File]::WriteAllText($Path, $htmlToWrite, [System.Text.Encoding]::UTF8)
            }
            Write-Verbose "Report successfully exported to $Path"

            if ($PassThru) {
                return $report
            }
            return
        }

        if ($AsHtml) {
            return $htmlOutput
        }

        if ($AsJson) {
            return ($report | ConvertTo-Json -Depth 6)
        }

        return $report
    }
}

function ConvertTo-NetworkDiagnosticsHtml {
    <#
    .SYNOPSIS
        Generates a self-contained HTML triage report from a network diagnostics object.
    #>
    param([Parameter(Mandatory = $true)][object]$Report)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="UTF-8"><title>Network Diagnostics Report</title>')
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine('body { font-family: -apple-system, Segoe UI, Helvetica, Arial, sans-serif; background: #1d2021; color: #ebdbb2; margin: 0; padding: 24px; line-height: 1.5; }')
    [void]$sb.AppendLine('h1, h2, h3 { color: #fabd2f; margin-top: 24px; border-bottom: 1px solid #3c3836; padding-bottom: 6px; }')
    [void]$sb.AppendLine('.summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin: 20px 0; }')
    [void]$sb.AppendLine('.card { background: #282828; border: 1px solid #3c3836; border-radius: 6px; padding: 14px; }')
    [void]$sb.AppendLine('.card-title { color: #a89984; font-size: 0.85rem; text-transform: uppercase; margin-bottom: 6px; }')
    [void]$sb.AppendLine('.card-value { font-size: 1.15rem; font-weight: bold; color: #83a598; word-break: break-all; }')
    [void]$sb.AppendLine('table { width: 100%; border-collapse: collapse; margin-top: 12px; background: #282828; border-radius: 6px; overflow: hidden; }')
    [void]$sb.AppendLine('th, td { padding: 10px 14px; text-align: left; border-bottom: 1px solid #3c3836; }')
    [void]$sb.AppendLine('th { background: #32302f; color: #fe8019; font-weight: 600; font-size: 0.9rem; }')
    [void]$sb.AppendLine('.badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.8rem; font-weight: bold; }')
    [void]$sb.AppendLine('.badge-ok { background: #b8bb26; color: #282828; }')
    [void]$sb.AppendLine('.badge-warn { background: #fabd2f; color: #282828; }')
    [void]$sb.AppendLine('.badge-fail { background: #fb4934; color: #ebdbb2; }')
    [void]$sb.AppendLine('pre { background: #282828; padding: 12px; border-radius: 6px; overflow-x: auto; color: #bdae93; }')
    [void]$sb.AppendLine('</style>')
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')

    [void]$sb.AppendLine("<h1>Network Diagnostics Report &mdash; $($Report.ComputerName)</h1>")
    [void]$sb.AppendLine("<p style='color: #a89984;'>Generated at $($Report.Timestamp.ToString('yyyy-MM-dd HH:mm:ss UTC'))</p>")

    # Cards Grid
    [void]$sb.AppendLine('<div class="summary-grid">')
    [void]$sb.AppendLine("<div class='card'><div class='card-title'>Public IP</div><div class='card-value'>$([System.Net.WebUtility]::HtmlEncode($Report.PublicIP))</div></div>")
    $tsLabel = if ($Report.Egress.TailscaleExitNode) { "Tailscale ($($Report.Egress.TailscaleExitNode))" } elseif ($Report.Egress.ActiveVpnAdapters.Count -gt 0) { "VPN Active" } else { "Direct Egress" }
    [void]$sb.AppendLine("<div class='card'><div class='card-title'>Egress Routing</div><div class='card-value'>$([System.Net.WebUtility]::HtmlEncode($tsLabel))</div></div>")
    [void]$sb.AppendLine("<div class='card'><div class='card-title'>Active Adapters</div><div class='card-value'>$($Report.Adapters.Count)</div></div>")
    [void]$sb.AppendLine("<div class='card'><div class='card-title'>WinHTTP Proxy</div><div class='card-value'>$([System.Net.WebUtility]::HtmlEncode($Report.Proxy.WinHTTP))</div></div>")
    [void]$sb.AppendLine('</div>')

    # Adapters Table
    [void]$sb.AppendLine('<h2>Network Adapters</h2>')
    [void]$sb.AppendLine('<table><thead><tr><th>Name</th><th>MAC</th><th>IPv4 / Subnet</th><th>DHCP</th><th>Lease Expires</th><th>Speed</th><th>Gateway</th></tr></thead><tbody>')
    foreach ($a in $Report.Adapters) {
        $dhcpBadge = if ($a.DHCPEnabled) { "<span class='badge badge-ok'>DHCP</span>" } else { "<span class='badge badge-warn'>Static</span>" }
        $ips = ($a.IPv4 -join '<br/>')
        $gws = ($a.Gateways -join '<br/>')
        $lease = if ($a.LeaseExpires) { $a.LeaseExpires.ToString('yyyy-MM-dd HH:mm') } else { '&mdash;' }
        [void]$sb.AppendLine("<tr><td><strong>$($a.Name)</strong><br/><small style='color:#a89984;'>$($a.InterfaceDescription)</small></td><td>$($a.MacAddress)</td><td>$ips</td><td>$dhcpBadge</td><td>$lease</td><td>$($a.LinkSpeed)</td><td>$gws</td></tr>")
    }
    [void]$sb.AppendLine('</tbody></table>')

    # Reachability Table
    [void]$sb.AppendLine('<h2>Target Reachability</h2>')
    [void]$sb.AppendLine('<table><thead><tr><th>Target</th><th>Type</th><th>ICMP Ping</th><th>Latency</th><th>TCP 443 (HTTPS)</th><th>TCP RTT</th></tr></thead><tbody>')
    foreach ($r in $Report.Reachability) {
        $icmpBadge = if ($r.IcmpStatus -eq 'Reachable') { "<span class='badge badge-ok'>OK</span>" } else { "<span class='badge badge-fail'>$($r.IcmpStatus)</span>" }
        $tcpBadge  = if ($r.Tcp443 -eq 'Open') { "<span class='badge badge-ok'>OPEN</span>" } else { "<span class='badge badge-fail'>$($r.Tcp443)</span>" }
        $icmpMs = if ($r.IcmpRttMs -ne $null) { "$($r.IcmpRttMs) ms" } else { '&mdash;' }
        $tcpMs  = if ($r.Tcp443Ms -ne $null) { "$($r.Tcp443Ms) ms" } else { '&mdash;' }
        [void]$sb.AppendLine("<tr><td><strong>$($r.Target)</strong></td><td>$($r.Type)</td><td>$icmpBadge</td><td>$icmpMs</td><td>$tcpBadge</td><td>$tcpMs</td></tr>")
    }
    [void]$sb.AppendLine('</tbody></table>')

    # DNS Table
    [void]$sb.AppendLine('<h2>DNS Resolution Validation</h2>')
    [void]$sb.AppendLine('<table><thead><tr><th>DNS Server</th><th>Domain Tested</th><th>Status</th><th>Resolved IPs</th><th>Latency</th></tr></thead><tbody>')
    foreach ($d in $Report.DnsValidation) {
        $badge = if ($d.Status -eq 'Success') { "<span class='badge badge-ok'>RESOLVED</span>" } else { "<span class='badge badge-fail'>$($d.Status)</span>" }
        $ips = ($d.ResolvedIPs -join ', ')
        [void]$sb.AppendLine("<tr><td>$($d.Server)</td><td>$($d.Domain)</td><td>$badge</td><td>$ips</td><td>$($d.LatencyMs) ms</td></tr>")
    }
    [void]$sb.AppendLine('</tbody></table>')

    # Hosts file overrides if any
    if ($Report.HostsOverrides -and $Report.HostsOverrides.Count -gt 0) {
        [void]$sb.AppendLine("<h2>Hosts File Overrides ($($Report.HostsOverrides.Count))</h2>")
        [void]$sb.AppendLine('<table><thead><tr><th>IP Address</th><th>Hostnames</th></tr></thead><tbody>')
        foreach ($h in $Report.HostsOverrides) {
            [void]$sb.AppendLine("<tr><td>$($h.IPAddress)</td><td>$([System.Net.WebUtility]::HtmlEncode($h.Hostnames))</td></tr>")
        }
        [void]$sb.AppendLine('</tbody></table>')
    }

    [void]$sb.AppendLine('</body></html>')
    return $sb.ToString()
}

Export-ModuleMember -Function 'Get-NetworkDiagnostics' -Alias 'Test-NetworkDiagnostics'
