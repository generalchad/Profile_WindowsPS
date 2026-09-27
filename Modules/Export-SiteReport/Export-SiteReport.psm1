function Export-SiteReport {
    <#
    .SYNOPSIS
        Generates a consolidated site-triage job-ticket artifact combining machine specifications, print inventory, and network diagnostics.

    .DESCRIPTION
        Orchestrates system inspection across ProfileTools (Get-WindowsInstallInfo), Restart-PrintStack
        (Get-PrintStackInventory), network discovery (Find-NetworkDevice / Get-PrinterInfo), and network
        triage (Get-NetworkDiagnostics). Emits a standalone, styled HTML document (and optional companion JSON)
        with timestamped filename for ticket attachment. Each subsystem degrades gracefully if the corresponding
        module or command is unavailable.

    .PARAMETER OutputFolder
        Target directory where the report file(s) will be created. Defaults to the current directory.

    .PARAMETER FilePath
        Exact file path to save the HTML report. If omitted, generates a timestamped filename
        formatted as 'SiteReport-<ComputerName>-<yyyyMMdd-HHmmss>.html'.

    .PARAMETER IncludeNetworkPrinters
        Runs a quick printer discovery sweep on the local subnet and queries responding devices via SNMP.
        Disabled by default to keep report generation rapid unless explicitly requested.

    .PARAMETER Subnet
        Optional subnet CIDR or range for the printer discovery sweep when -IncludeNetworkPrinters is set.

    .PARAMETER IncludeJson
        Writes a companion JSON data export alongside the HTML report.

    .PARAMETER PassThru
        Outputs the consolidated PSCustomObject to the pipeline.

    .OUTPUTS
        System.IO.FileInfo of the generated HTML report, or PSCustomObject if -PassThru is supplied.

    .EXAMPLE
        Export-SiteReport

    .EXAMPLE
        Export-SiteReport -OutputFolder C:\Tickets\12345 -IncludeNetworkPrinters -IncludeJson
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$OutputFolder = (Get-Location).Path,

        [Parameter()]
        [string]$FilePath,

        [Parameter()]
        [switch]$IncludeNetworkPrinters,

        [Parameter()]
        [string[]]$Subnet,

        [Parameter()]
        [switch]$IncludeJson,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        $timestamp = [System.DateTime]::UtcNow
        $computerName = $env:COMPUTERNAME

        # 1. Machine Inventory
        Write-Progress -Activity 'Generating Site Report' -Status 'Gathering system hardware and OS specs...' -PercentComplete 15
        $machineInfo = $null
        try {
            if (Get-Command Get-WindowsInstallInfo -ErrorAction SilentlyContinue) {
                $machineInfo = Get-WindowsInstallInfo -AsObject
            } else {
                # Fallback basic CIM collection if ProfileTools is unavailable
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
                $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
                $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
                $ram = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum

                $machineInfo = [pscustomobject]@{
                    WindowsVersion  = $os?.Caption ?? 'Unknown'
                    BuildNumber     = $os?.BuildNumber ?? 'Unknown'
                    FullBuildNumber = "$($os?.BuildNumber).$($os?.ServicePackMajorVersion)"
                    InstallDate     = $os?.InstallDate
                    OperationalDays = [math]::Round(((Get-Date) - ($os?.InstallDate ?? (Get-Date))).TotalDays, 1)
                    UptimeHours     = [math]::Round(((Get-Date) - ($os?.LastBootUpTime ?? (Get-Date))).TotalHours, 1)
                    Drives          = @()
                    TotalRamGB      = [math]::Round(($ram?.Sum ?? 0) / 1GB, 2)
                    CPU             = "$($cpu?.Name) ($($cpu?.NumberOfCores) cores)"
                }
            }
        } catch {
            $machineInfo = [pscustomobject]@{ Status = 'Unavailable'; Error = $_.Exception.Message }
        }

        # 2. Local Print Stack Inventory
        Write-Progress -Activity 'Generating Site Report' -Status 'Querying local print queues and ports...' -PercentComplete 35
        $printStack = @()
        try {
            if (Get-Command Get-PrintStackInventory -ErrorAction SilentlyContinue) {
                $printStack = @(Get-PrintStackInventory -AsObject -ErrorAction SilentlyContinue)
            } else {
                # Basic spooler WMI enumeration fallback
                $printStack = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        [pscustomobject]@{
                            Type        = 'Printer'
                            Name        = $_.Name
                            PortName    = $_.PortName
                            DriverName  = $_.DriverName
                            Action      = 'Keep'
                            ActionClass = 'Keep'
                            Reason      = 'Standard Queue'
                        }
                    })
            }
        } catch {
            $printStack = @([pscustomobject]@{ Type = 'Error'; Name = 'PrintStack query failed'; Reason = $_.Exception.Message })
        }

        # 3. Discovered Network Printers (Optional sweep)
        $discoveredPrinters = @()
        if ($IncludeNetworkPrinters) {
            Write-Progress -Activity 'Generating Site Report' -Status 'Sweeping network for printers & querying SNMP...' -PercentComplete 55
            try {
                if (Get-Command Find-NetworkDevice -ErrorAction SilentlyContinue) {
                    $sweepParams = @{ ProbePorts = $true; PrinterOnly = $true }
                    if ($Subnet) { $sweepParams['Subnet'] = $Subnet }
                    $printersFound = @(Find-NetworkDevice @sweepParams -ErrorAction SilentlyContinue)

                    if ($printersFound.Count -gt 0 -and (Get-Command Get-PrinterInfo -ErrorAction SilentlyContinue)) {
                        $snmpTargets = $printersFound | Where-Object { $_.HasSnmp }
                        if ($snmpTargets) {
                            $discoveredPrinters = @($snmpTargets | Get-PrinterInfo -Timeout 1500 -ErrorAction SilentlyContinue)
                        } else {
                            $discoveredPrinters = $printersFound
                        }
                    } else {
                        $discoveredPrinters = $printersFound
                    }
                }
            } catch {
                Write-Verbose "Printer network sweep omitted or failed: $_"
            }
        }

        # 4. Network Diagnostics & Triage
        Write-Progress -Activity 'Generating Site Report' -Status 'Executing network triage and reachability checks...' -PercentComplete 75
        $networkReport = $null
        try {
            if (Get-Command Get-NetworkDiagnostics -ErrorAction SilentlyContinue) {
                $networkReport = Get-NetworkDiagnostics -TimeoutMs 2000 -ErrorAction SilentlyContinue
            }
        } catch {
            $networkReport = [pscustomobject]@{ Status = 'Unavailable'; Error = $_.Exception.Message }
        }

        # 5. Build Aggregated Object
        $siteReportObj = [pscustomobject]@{
            PSTypeName               = 'SiteReport.Artifact'
            TimestampUtc             = $timestamp
            ComputerName             = $computerName
            GeneratedBy              = "$env:USERDOMAIN\$env:USERNAME"
            Machine                  = $machineInfo
            PrintStack               = $printStack
            DiscoveredNetworkPrinters = $discoveredPrinters
            Network                  = $networkReport
        }

        # 6. File Paths
        Write-Progress -Activity 'Generating Site Report' -Status 'Rendering self-contained HTML report...' -PercentComplete 90

        if (-not $FilePath) {
            $dateStr = $timestamp.ToString('yyyyMMdd-HHmmss')
            $fileName = "SiteReport-$computerName-$dateStr.html"
            if (-not (Test-Path -LiteralPath $OutputFolder)) {
                [System.IO.Directory]::CreateDirectory($OutputFolder) | Out-Null
            }
            $FilePath = Join-Path $OutputFolder $fileName
        } else {
            $parent = [System.IO.Path]::GetDirectoryName($FilePath)
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                [System.IO.Directory]::CreateDirectory($parent) | Out-Null
            }
        }

        # 7. Render HTML
        $html = ConvertTo-SiteReportHtml -Report $siteReportObj
        [System.IO.File]::WriteAllText($FilePath, $html, [System.Text.Encoding]::UTF8)

        if ($IncludeJson) {
            $jsonPath = [System.IO.Path]::ChangeExtension($FilePath, '.json')
            $json = $siteReportObj | ConvertTo-Json -Depth 8
            [System.IO.File]::WriteAllText($jsonPath, $json, [System.Text.Encoding]::UTF8)
            Write-Verbose "Exported companion JSON to $jsonPath"
        }

        Write-Progress -Activity 'Generating Site Report' -Completed
        Write-Host "Site report exported: $FilePath" -ForegroundColor Green

        if ($PassThru) {
            return $siteReportObj
        }

        return (Get-Item -LiteralPath $FilePath)
    }
}

function ConvertTo-SiteReportHtml {
    <#
    .SYNOPSIS
        Renders the aggregated site report object into an offline, self-contained HTML job-ticket document.
    #>
    param([Parameter(Mandatory = $true)][object]$Report)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="UTF-8"><title>Site Triage Report &mdash; ' + [System.Net.WebUtility]::HtmlEncode($Report.ComputerName) + '</title>')
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine('body { font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif; background: #1d2021; color: #ebdbb2; margin: 0; padding: 28px; line-height: 1.5; }')
    [void]$sb.AppendLine('.container { max-width: 1200px; margin: 0 auto; }')
    [void]$sb.AppendLine('h1 { color: #fabd2f; margin-bottom: 4px; font-size: 1.8rem; }')
    [void]$sb.AppendLine('h2 { color: #fe8019; margin-top: 32px; border-bottom: 1px solid #504945; padding-bottom: 6px; font-size: 1.3rem; }')
    [void]$sb.AppendLine('.meta-bar { color: #a89984; font-size: 0.9rem; margin-bottom: 24px; }')
    [void]$sb.AppendLine('.grid-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; margin-bottom: 24px; }')
    [void]$sb.AppendLine('.card { background: #282828; border: 1px solid #3c3836; border-radius: 6px; padding: 16px; }')
    [void]$sb.AppendLine('.card-label { color: #a89984; font-size: 0.8rem; text-transform: uppercase; margin-bottom: 4px; }')
    [void]$sb.AppendLine('.card-value { font-size: 1.15rem; font-weight: bold; color: #83a598; word-break: break-word; }')
    [void]$sb.AppendLine('table { width: 100%; border-collapse: collapse; margin-top: 12px; background: #282828; border-radius: 6px; overflow: hidden; font-size: 0.9rem; }')
    [void]$sb.AppendLine('th, td { padding: 10px 12px; text-align: left; border-bottom: 1px solid #3c3836; vertical-align: top; }')
    [void]$sb.AppendLine('th { background: #32302f; color: #d5c4a1; font-weight: 600; }')
    [void]$sb.AppendLine('.badge { display: inline-block; padding: 2px 7px; border-radius: 4px; font-size: 0.75rem; font-weight: bold; }')
    [void]$sb.AppendLine('.badge-ok { background: #b8bb26; color: #282828; }')
    [void]$sb.AppendLine('.badge-warn { background: #fabd2f; color: #282828; }')
    [void]$sb.AppendLine('.badge-fail { background: #fb4934; color: #ebdbb2; }')
    [void]$sb.AppendLine('.badge-info { background: #83a598; color: #282828; }')
    [void]$sb.AppendLine('.progress-bar { background: #3c3836; border-radius: 4px; height: 14px; width: 100%; overflow: hidden; margin-top: 4px; }')
    [void]$sb.AppendLine('.progress-fill { background: #83a598; height: 100%; }')
    [void]$sb.AppendLine('</style>')
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body><div class="container">')

    [void]$sb.AppendLine("<h1>Site Triage Report &mdash; $([System.Net.WebUtility]::HtmlEncode($Report.ComputerName))</h1>")
    [void]$sb.AppendLine("<div class='meta-bar'>Generated: $($Report.TimestampUtc.ToString('yyyy-MM-dd HH:mm:ss UTC')) | Operator: $([System.Net.WebUtility]::HtmlEncode($Report.GeneratedBy))</div>")

    # High-level Metrics Cards
    [void]$sb.AppendLine('<div class="grid-cards">')
    [void]$sb.AppendLine("<div class='card'><div class='card-label'>Operating System</div><div class='card-value'>$([System.Net.WebUtility]::HtmlEncode($Report.Machine.WindowsVersion))</div></div>")
    [void]$sb.AppendLine("<div class='card'><div class='card-label'>Build</div><div class='card-value'>$([System.Net.WebUtility]::HtmlEncode($Report.Machine.FullBuildNumber))</div></div>")
    [void]$sb.AppendLine("<div class='card'><div class='card-label'>Public IP</div><div class='card-value'>$([System.Net.WebUtility]::HtmlEncode($Report.Network.PublicIP ?? 'Unavailable'))</div></div>")
    $egressLabel = if ($Report.Network?.Egress?.TailscaleExitNode) { "Tailscale ($($Report.Network.Egress.TailscaleExitNode))" } elseif ($Report.Network?.Egress?.ActiveVpnAdapters?.Count -gt 0) { "VPN Active" } else { "Direct" }
    [void]$sb.AppendLine("<div class='card'><div class='card-label'>Egress Path</div><div class='card-value'>$([System.Net.WebUtility]::HtmlEncode($egressLabel))</div></div>")
    [void]$sb.AppendLine('</div>')

    # Machine Specs Section
    [void]$sb.AppendLine('<h2>1. System & Hardware Specifications</h2>')
    [void]$sb.AppendLine('<table><tbody>')
    [void]$sb.AppendLine("<tr><td style='width:220px; color:#a89984;'>Processor (CPU)</td><td>$([System.Net.WebUtility]::HtmlEncode($Report.Machine.CPU))</td></tr>")
    [void]$sb.AppendLine("<tr><td style='color:#a89984;'>Physical Memory (RAM)</td><td>$($Report.Machine.TotalRamGB) GB</td></tr>")
    [void]$sb.AppendLine("<tr><td style='color:#a89984;'>System Uptime</td><td>$($Report.Machine.UptimeHours) hours</td></tr>")
    [void]$sb.AppendLine("<tr><td style='color:#a89984;'>Storage Volumes</td><td>")
    if ($Report.Machine.Drives) {
        foreach ($d in $Report.Machine.Drives) {
            $fill = [math]::Min(100, [int]$d.UsedPercent)
            $color = if ($fill -gt 90) { '#fb4934' } elseif ($fill -gt 75) { '#fabd2f' } else { '#83a598' }
            [void]$sb.AppendLine("<div style='margin-bottom:8px;'><strong>Drive $($d.Drive):</strong> $($d.FreeGB) GB free of $($d.TotalGB) GB ($($d.UsedPercent)% used)")
            [void]$sb.AppendLine("<div class='progress-bar'><div class='progress-fill' style='width:$fill%; background:$color;'></div></div></div>")
        }
    } else {
        [void]$sb.AppendLine('&mdash;')
    }
    [void]$sb.AppendLine('</td></tr></tbody></table>')

    # Network Triage Section
    [void]$sb.AppendLine('<h2>2. Network Triage & Connectivity</h2>')
    if ($Report.Network?.Adapters) {
        [void]$sb.AppendLine('<table><thead><tr><th>Adapter</th><th>MAC</th><th>IPv4 / Subnet</th><th>DHCP</th><th>Gateway</th><th>Link Speed</th></tr></thead><tbody>')
        foreach ($a in $Report.Network.Adapters) {
            $dhcpBadge = if ($a.DHCPEnabled) { "<span class='badge badge-ok'>DHCP</span>" } else { "<span class='badge badge-warn'>Static</span>" }
            $ips = ($a.IPv4 -join '<br/>')
            $gws = ($a.Gateways -join '<br/>')
            [void]$sb.AppendLine("<tr><td><strong>$($a.Name)</strong><br/><small style='color:#a89984;'>$($a.InterfaceDescription)</small></td><td>$($a.MacAddress)</td><td>$ips</td><td>$dhcpBadge</td><td>$gws</td><td>$($a.LinkSpeed)</td></tr>")
        }
        [void]$sb.AppendLine('</tbody></table>')
    }

    if ($Report.Network?.Reachability) {
        [void]$sb.AppendLine('<h3>Target Reachability</h3>')
        [void]$sb.AppendLine('<table><thead><tr><th>Target</th><th>Type</th><th>ICMP Status</th><th>ICMP Latency</th><th>TCP 443</th><th>TCP RTT</th></tr></thead><tbody>')
        foreach ($r in $Report.Network.Reachability) {
            $icmpBadge = if ($r.IcmpStatus -eq 'Reachable') { "<span class='badge badge-ok'>OK</span>" } else { "<span class='badge badge-fail'>$($r.IcmpStatus)</span>" }
            $tcpBadge  = if ($r.Tcp443 -eq 'Open') { "<span class='badge badge-ok'>OPEN</span>" } else { "<span class='badge badge-fail'>$($r.Tcp443)</span>" }
            $iMs = if ($r.IcmpRttMs -ne $null) { "$($r.IcmpRttMs) ms" } else { '&mdash;' }
            $tMs = if ($r.Tcp443Ms -ne $null) { "$($r.Tcp443Ms) ms" } else { '&mdash;' }
            [void]$sb.AppendLine("<tr><td>$($r.Target)</td><td>$($r.Type)</td><td>$icmpBadge</td><td>$iMs</td><td>$tcpBadge</td><td>$tMs</td></tr>")
        }
        [void]$sb.AppendLine('</tbody></table>')
    }

    # Print Stack & Discovered Printers
    [void]$sb.AppendLine('<h2>3. Print Stack & Imaging System</h2>')
    if ($Report.PrintStack -and $Report.PrintStack.Count -gt 0) {
        [void]$sb.AppendLine('<table><thead><tr><th>Type</th><th>Name</th><th>Port / Target</th><th>Driver</th><th>Status / Action</th></tr></thead><tbody>')
        foreach ($p in $Report.PrintStack) {
            $actionBadge = switch ($p.Action) {
                'Keep'   { "<span class='badge badge-ok'>KEEP</span>" }
                'Remove' { "<span class='badge badge-fail'>REMOVE</span>" }
                Default  { "<span class='badge badge-info'>$($p.Action)</span>" }
            }
            [void]$sb.AppendLine("<tr><td>$($p.Type)</td><td><strong>$([System.Net.WebUtility]::HtmlEncode($p.Name))</strong></td><td>$([System.Net.WebUtility]::HtmlEncode($p.PortName ?? $p.Port ?? '&mdash;'))</td><td>$([System.Net.WebUtility]::HtmlEncode($p.DriverName ?? '&mdash;'))</td><td>$actionBadge<br/><small style='color:#a89984;'>$([System.Net.WebUtility]::HtmlEncode($p.Reason))</small></td></tr>")
        }
        [void]$sb.AppendLine('</tbody></table>')
    } else {
        [void]$sb.AppendLine('<p style="color:#a89984;">No local print queues or imaging devices recorded.</p>')
    }

    if ($Report.DiscoveredNetworkPrinters -and $Report.DiscoveredNetworkPrinters.Count -gt 0) {
        [void]$sb.AppendLine('<h3>Discovered Network Printers (SNMP)</h3>')
        [void]$sb.AppendLine('<table><thead><tr><th>Address</th><th>Model</th><th>Serial</th><th>Pages</th><th>Status</th><th>Supplies</th></tr></thead><tbody>')
        foreach ($np in $Report.DiscoveredNetworkPrinters) {
            $suppliesList = @()
            if ($np.Supplies) {
                foreach ($s in $np.Supplies) {
                    $suppliesList += "$($s.Name): $($s.Percent)%"
                }
            }
            $suppliesStr = if ($suppliesList.Count -gt 0) { $suppliesList -join '<br/>' } else { '&mdash;' }
            [void]$sb.AppendLine("<tr><td>$($np.ComputerName ?? $np.IPAddress)</td><td>$([System.Net.WebUtility]::HtmlEncode($np.Model ?? $np.Vendor ?? 'Unknown'))</td><td>$([System.Net.WebUtility]::HtmlEncode($np.Serial ?? '&mdash;'))</td><td>$($np.PageCount ?? '&mdash;')</td><td>$([System.Net.WebUtility]::HtmlEncode($np.Status ?? 'Discovered'))</td><td>$suppliesStr</td></tr>")
        }
        [void]$sb.AppendLine('</tbody></table>')
    }

    [void]$sb.AppendLine('</div></body></html>')
    return $sb.ToString()
}

Export-ModuleMember -Function 'Export-SiteReport' -Alias 'New-SiteReport'
