function Restart-NetworkStack {
    <#
    .SYNOPSIS
        Resets and refreshes the Windows networking stack (DNS, DHCP, adapters,
        Winsock, TCP/IP, firewall, proxy, ARP/NetBIOS) from a single command.

    .DESCRIPTION
        Restart-NetworkStack replaces the usual pile of manually typed commands
        (ipconfig /release, ipconfig /renew, ipconfig /flushdns, ipconfig /registerdns,
        netsh winsock reset, netsh int ip reset, arp -d *, nbtstat -R, ...) with one
        cmdlet that runs the steps you ask for, in the correct order, with proper
        WhatIf support and a readable summary.

        Every step prefers a first-party PowerShell cmdlet when one exists and is
        functional (Clear-DnsClientCache, Register-DnsClient, Restart-NetAdapter,
        Remove-NetNeighbor, Restart-Service). Where Windows never shipped a cmdlet
        equivalent - Winsock catalog reset, TCP/IP stack reset, firewall policy reset,
        WinHTTP proxy reset, NetBIOS cache purge - the classic console tools are used
        as the fallback. If a cmdlet is missing or throws, the native command is used
        automatically.

        SAFETY MODEL
        Steps are split into two tiers.

        Non-destructive tier (-Dns, -ArpNetBios, -Dhcp, -Adapter, and -Safe which runs
        all four). These only clear caches or bounce the link. Nothing persistent is
        altered and they run without any confirmation prompt. The worst side effect is
        roughly ten seconds without connectivity.

        Destructive tier (-Winsock, -TcpIp, -Firewall, -Proxy). These discard persistent
        configuration. They trigger a single consolidated confirmation prompt that
        itemises exactly what will be lost, and - unless -NoBackup is given - the current
        configuration is exported to a timestamped folder under %TEMP% first, with the
        restore command printed in the summary.

        With no switches at all the cmdlet performs only the safe DNS refresh.

    .PARAMETER Safe
        Run every non-destructive step, in order: ARP/NetBIOS purge, adapter bounce,
        DHCP release/renew, DNS flush and re-registration. This is the everyday
        "fix my connection" option. No prompt, no persistent configuration is changed,
        no reboot required.

    .PARAMETER Dns
        Flush the resolver cache, re-register the client's records with DNS, and
        restart the DNS Client (Dnscache) service. Non-destructive.
        Cmdlets: Clear-DnsClientCache, Register-DnsClient, Restart-Service Dnscache
        Fallback: ipconfig /flushdns, ipconfig /registerdns

    .PARAMETER Dhcp
        Release and renew DHCP leases on the target adapters. Non-destructive, but
        briefly drops connectivity (and therefore any remote session).
        Cmdlet: Invoke-CimMethod on Win32_NetworkAdapterConfiguration
        Fallback: ipconfig /release + /renew (and /release6 + /renew6 with -IncludeIPv6)

    .PARAMETER Adapter
        Bounce (disable then re-enable) the target network adapters. Non-destructive;
        adapter configuration is preserved. Drops connectivity for a few seconds.
        Cmdlet: Restart-NetAdapter
        Fallback: netsh interface set interface "<name>" admin=disabled|enabled

    .PARAMETER ArpNetBios
        Purge the ARP neighbour cache and the NetBIOS name cache, and force a NetBIOS
        name refresh. Non-destructive; entries are re-learned automatically.
        Cmdlet: Remove-NetNeighbor
        Fallback: netsh interface ip delete arpcache, nbtstat -R, nbtstat -RR

    .PARAMETER Winsock
        DESTRUCTIVE. Resets the Winsock catalog with 'netsh winsock reset'. This
        unregisters third-party layered service providers, so some VPN clients,
        antivirus network filters and packet shapers will stop working until they are
        reinstalled. Requires a reboot. No cmdlet equivalent exists and no meaningful
        backup is possible.

    .PARAMETER TcpIp
        DESTRUCTIVE. Resets the TCP/IP stack with 'netsh int ip reset' (plus
        'netsh int ipv6 reset' with -IncludeIPv6). Static IP addresses, gateways and
        manually configured DNS servers are erased and the adapters revert to DHCP.
        Requires a reboot. The previous configuration is exported first unless
        -NoBackup is specified.

    .PARAMETER Firewall
        DESTRUCTIVE. Restores Windows Defender Firewall to its out-of-box policy with
        'netsh advfirewall reset', deleting every custom rule. The current policy is
        exported to a .wfw file first unless -NoBackup is specified.

    .PARAMETER Proxy
        DESTRUCTIVE. Clears the WinHTTP proxy ('netsh winhttp reset proxy') and disables
        the per-user WinINET proxy. On a network that mandates a proxy this can cut off
        HTTP access until the settings are re-provisioned. Current values are recorded
        first unless -NoBackup is specified.

    .PARAMETER Full
        Perform every step, non-destructive and destructive alike, in the recommended
        order. Prompts once before the destructive steps and requires a reboot.

    .PARAMETER InterfaceAlias
        Limit adapter-scoped work (-Adapter, -Dhcp) to the named adapters. Wildcards
        are supported. Defaults to all physical adapters that are currently Up.

    .PARAMETER IncludeIPv6
        Also perform the IPv6 variants of DHCP release/renew, the stack reset, and the
        neighbour cache purge.

    .PARAMETER Force
        Skip the consolidated confirmation prompt for the destructive steps, and do not
        warn about the temporary loss of connectivity.

    .PARAMETER NoBackup
        Do not export the current IP, firewall and proxy configuration before running
        the destructive steps.

    .PARAMETER Restart
        Reboot the computer at the end of the run if any step reported that a reboot is
        required. Without -Force you are still asked before the reboot happens.

    .PARAMETER SkipConnectivityTest
        Do not run the post-reset DNS resolution and ping sanity check.

    .PARAMETER PassThru
        Emit the per-step result objects to the pipeline in addition to printing the
        summary table.

    .EXAMPLE
        Restart-NetworkStack

        Safe default: flush the DNS cache, re-register DNS records and restart the DNS
        Client service. No prompt.

    .EXAMPLE
        Restart-NetworkStack -Safe

        The everyday fix. Purges ARP and NetBIOS caches, bounces the adapters, renews
        the DHCP lease and refreshes DNS. Nothing persistent is changed and no reboot
        is needed.

    .EXAMPLE
        Restart-NetworkStack -Dns -Dhcp

        Renews the lease and clears the resolver cache without touching the adapters.

    .EXAMPLE
        Restart-NetworkStack -Adapter -InterfaceAlias 'Ethernet*'

        Bounces only the adapters whose names start with Ethernet.

    .EXAMPLE
        Restart-NetworkStack -Full -WhatIf

        Lists every command a full reset would execute, without running any of them.

    .EXAMPLE
        Restart-NetworkStack -Full -Force -Restart

        Complete reset with no prompts, backups still taken, reboots when finished.

    .EXAMPLE
        Restart-NetworkStack -Safe -PassThru | Where-Object Status -ne 'Success'

        Runs the safe sequence and returns only the steps that did not succeed.

    .OUTPUTS
        RestartNetworkStack.StepResult (with -PassThru)

    .NOTES
        Author  : GenChadt
        Requires: Administrator rights for everything except a plain DNS cache flush.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Selective')]
    [Alias('rns', 'Reset-NetworkStack')]
    [OutputType('RestartNetworkStack.StepResult')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Safe')]
        [switch] $Safe,

        [Parameter(Mandatory, ParameterSetName = 'Full')]
        [switch] $Full,

        [Parameter(ParameterSetName = 'Selective')]
        [switch] $Dns,

        [Parameter(ParameterSetName = 'Selective')]
        [switch] $Dhcp,

        [Parameter(ParameterSetName = 'Selective')]
        [switch] $Adapter,

        [Parameter(ParameterSetName = 'Selective')]
        [switch] $ArpNetBios,

        [Parameter(ParameterSetName = 'Selective')]
        [switch] $Winsock,

        [Parameter(ParameterSetName = 'Selective')]
        [switch] $TcpIp,

        [Parameter(ParameterSetName = 'Selective')]
        [switch] $Firewall,

        [Parameter(ParameterSetName = 'Selective')]
        [switch] $Proxy,

        [ArgumentCompleter({
                param($commandName, $parameterName, $wordToComplete)
                if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
                    (Get-NetAdapter -ErrorAction SilentlyContinue).Name |
                        Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { "'$_'" }
                }
            })]
        [string[]] $InterfaceAlias,

        [switch] $IncludeIPv6,

        [switch] $Force,

        [switch] $NoBackup,

        [switch] $Restart,

        [switch] $SkipConnectivityTest,

        [switch] $PassThru
    )

    begin {
        $rebootRequired = $false
        $results = [System.Collections.Generic.List[object]]::new()
        $backupRoot = $null

        # ---- Resolve which steps to run --------------------------------------
        $doDns = $false; $doDhcp = $false; $doAdapter = $false; $doArp = $false
        $doWinsock = $false; $doTcpIp = $false; $doFirewall = $false; $doProxy = $false

        if ($Full) {
            $doDns = $doDhcp = $doAdapter = $doArp = $true
            $doWinsock = $doTcpIp = $doFirewall = $doProxy = $true
        }
        elseif ($Safe) {
            $doDns = $doDhcp = $doAdapter = $doArp = $true
        }
        else {
            $doDns = $Dns.IsPresent
            $doDhcp = $Dhcp.IsPresent
            $doAdapter = $Adapter.IsPresent
            $doArp = $ArpNetBios.IsPresent
            $doWinsock = $Winsock.IsPresent
            $doTcpIp = $TcpIp.IsPresent
            $doFirewall = $Firewall.IsPresent
            $doProxy = $Proxy.IsPresent

            $anyRequested = $doDns -or $doDhcp -or $doAdapter -or $doArp -or
            $doWinsock -or $doTcpIp -or $doFirewall -or $doProxy

            if (-not $anyRequested) {
                $doDns = $true
                Write-Host 'No steps specified - performing the safe DNS refresh only.' -ForegroundColor Cyan
                Write-Host 'Use -Safe for the full non-destructive sequence, or -Full for everything.' -ForegroundColor DarkGray
                Write-Host ''
            }
        }

        $anyDestructive = $doWinsock -or $doTcpIp -or $doFirewall -or $doProxy
        $needsAdmin = $anyDestructive -or $doDhcp -or $doAdapter -or $doArp
        $dryRun = [bool] $WhatIfPreference

        # ---- Elevation gate ---------------------------------------------------
        $elevated = Test-Elevation

        if ($needsAdmin -and -not $elevated) {
            if ($dryRun) {
                Write-Warning "Not elevated - this is a preview only. Running these steps requires: $(Get-ElevationHint)"
            }
            else {
                throw ("Restart-NetworkStack requires an elevated session for the requested steps. " +
                    "Relaunch with: $(Get-ElevationHint)")
            }
        }
        if ($doDns -and -not $elevated -and -not $dryRun) {
            Write-Warning 'Not elevated: the DNS cache will be flushed, but re-registration and the Dnscache service restart will be skipped.'
        }

        # ---- Consolidated confirmation, destructive steps only ----------------
        if ($anyDestructive -and -not $dryRun -and -not $Force) {
            $warnings = [System.Collections.Generic.List[string]]::new()
            if ($doWinsock) { $warnings.Add('  Winsock reset  - unregisters third-party LSPs; some VPN/AV filters may stop working') }
            if ($doTcpIp) { $warnings.Add('  TCP/IP reset   - erases static IPs, gateways and manually set DNS servers') }
            if ($doFirewall) { $warnings.Add('  Firewall reset - DELETES ALL custom firewall rules') }
            if ($doProxy) { $warnings.Add('  Proxy reset    - clears WinHTTP and per-user proxy settings') }

            Write-Host ''
            Write-Host 'The following DESTRUCTIVE operations will run:' -ForegroundColor Yellow
            $warnings | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
            if (-not $NoBackup) {
                Write-Host '  Current configuration will be backed up to %TEMP% first.' -ForegroundColor DarkGray
            }
            else {
                Write-Host '  -NoBackup specified: NO backup will be taken.' -ForegroundColor Red
            }
            Write-Host ''

            if (-not $PSCmdlet.ShouldContinue(
                    'Proceed with these destructive changes?',
                    'Restart-NetworkStack')) {
                Write-Host 'Cancelled - nothing was changed.' -ForegroundColor Cyan
                return
            }
        }

        if ($doAdapter -or $doDhcp) {
            if (-not $Force -and -not $dryRun) {
                Write-Warning 'Network connectivity will drop briefly while adapters and leases are cycled.'
            }
        }

        $proceed = $true
    }

    process {
        if (-not $proceed) { return }

        $targets = $null
        if ($doAdapter -or $doDhcp) {
            $targets = @(Get-TargetAdapter -InterfaceAlias $InterfaceAlias)
            if ($targets.Count) {
                Write-Verbose "Target adapters: $(($targets.Name) -join ', ')"
            }
        }

        # =====================================================================
        # 0. Backups, taken before anything destructive happens
        # =====================================================================
        if ($anyDestructive -and -not $NoBackup) {
            $backupRoot = if ($dryRun) { Join-Path $env:TEMP 'RestartNetworkStack_<timestamp>' } else { New-ConfigBackupRoot }

            if ($backupRoot) {
                if ($doTcpIp) { $results.Add((Backup-IPConfiguration -BackupRoot $backupRoot -DryRun:$dryRun)) }
                if ($doFirewall) { $results.Add((Backup-FirewallPolicy -BackupRoot $backupRoot -DryRun:$dryRun)) }
                if ($doProxy) { $results.Add((Backup-ProxyConfiguration -BackupRoot $backupRoot -DryRun:$dryRun)) }
            }
        }

        # =====================================================================
        # 1. Winsock catalog reset  (DESTRUCTIVE, no cmdlet equivalent)
        # =====================================================================
        if ($doWinsock) {
            $r = Invoke-NativeCommand -Step 'Winsock reset' -FilePath 'netsh.exe' `
                -ArgumentList @('winsock', 'reset') -DryRun:$dryRun
            $results.Add($r)
            if ($r.Status -eq 'Success') { $rebootRequired = $true }
        }

        # =====================================================================
        # 2. TCP/IP stack reset  (DESTRUCTIVE, no cmdlet equivalent)
        # =====================================================================
        if ($doTcpIp) {
            $r = Invoke-NativeCommand -Step 'TCP/IP reset (IPv4)' -FilePath 'netsh.exe' `
                -ArgumentList @('int', 'ip', 'reset') -SuccessExitCodes @(0, 1) -DryRun:$dryRun
            $results.Add($r)
            if ($r.Status -eq 'Success') { $rebootRequired = $true }

            if ($IncludeIPv6) {
                $r6 = Invoke-NativeCommand -Step 'TCP/IP reset (IPv6)' -FilePath 'netsh.exe' `
                    -ArgumentList @('int', 'ipv6', 'reset') -SuccessExitCodes @(0, 1) -DryRun:$dryRun
                $results.Add($r6)
                if ($r6.Status -eq 'Success') { $rebootRequired = $true }
            }
        }

        # =====================================================================
        # 3. Firewall policy reset  (DESTRUCTIVE: removes custom rules)
        # =====================================================================
        if ($doFirewall) {
            $results.Add((Invoke-NativeCommand -Step 'Firewall reset' -FilePath 'netsh.exe' `
                        -ArgumentList @('advfirewall', 'reset') -DryRun:$dryRun))
        }

        # =====================================================================
        # 4. Proxy reset  (DESTRUCTIVE: WinHTTP via netsh, WinINET via registry)
        # =====================================================================
        if ($doProxy) {
            $results.Add((Invoke-NativeCommand -Step 'WinHTTP proxy reset' -FilePath 'netsh.exe' `
                        -ArgumentList @('winhttp', 'reset', 'proxy') -DryRun:$dryRun))

            $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
            if ($dryRun) {
                $results.Add((Write-StepResult -Step 'WinINET proxy reset' -Method 'Registry' `
                            -Command "Set-ItemProperty '$regPath' ProxyEnable 0" -Status 'WhatIf' `
                            -Message 'Registry value was not modified (WhatIf).'))
            }
            else {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    Set-ItemProperty -Path $regPath -Name 'ProxyEnable' -Value 0 -ErrorAction Stop
                    Remove-ItemProperty -Path $regPath -Name 'ProxyServer' -ErrorAction SilentlyContinue
                    $sw.Stop()
                    $results.Add((Write-StepResult -Step 'WinINET proxy reset' -Method 'Registry' `
                                -Command "Set-ItemProperty '$regPath' ProxyEnable 0" -Status 'Success' `
                                -Duration $sw.Elapsed -Message 'Per-user proxy disabled.'))
                }
                catch {
                    $sw.Stop()
                    $results.Add((Write-StepResult -Step 'WinINET proxy reset' -Method 'Registry' `
                                -Command "Set-ItemProperty '$regPath' ProxyEnable 0" -Status 'Failed' `
                                -Duration $sw.Elapsed -Message $_.Exception.Message))
                }
            }
        }

        # =====================================================================
        # 5. ARP + NetBIOS caches  (non-destructive)
        # =====================================================================
        if ($doArp) {
            $arpDone = $false
            if ((Get-Command Remove-NetNeighbor -ErrorAction SilentlyContinue) -and -not $dryRun) {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    Remove-NetNeighbor -AddressFamily IPv4 -Confirm:$false -ErrorAction Stop
                    if ($IncludeIPv6) {
                        Remove-NetNeighbor -AddressFamily IPv6 -Confirm:$false -ErrorAction SilentlyContinue
                    }
                    $sw.Stop()
                    $results.Add((Write-StepResult -Step 'ARP cache purge' -Method 'Cmdlet' `
                                -Command 'Remove-NetNeighbor -AddressFamily IPv4' -Status 'Success' `
                                -Duration $sw.Elapsed -Message 'Neighbour cache cleared.'))
                    $arpDone = $true
                }
                catch {
                    $sw.Stop()
                    Write-Verbose "Remove-NetNeighbor failed, falling back to netsh: $($_.Exception.Message)"
                }
            }

            if (-not $arpDone) {
                $results.Add((Invoke-NativeCommand -Step 'ARP cache purge' -FilePath 'netsh.exe' `
                            -ArgumentList @('interface', 'ip', 'delete', 'arpcache') `
                            -SuccessExitCodes @(0, 1) -DryRun:$dryRun))
            }

            $results.Add((Invoke-NativeCommand -Step 'NetBIOS cache purge' -FilePath 'nbtstat.exe' `
                        -ArgumentList @('-R') -SuccessExitCodes @(0, 1) -DryRun:$dryRun))
            $results.Add((Invoke-NativeCommand -Step 'NetBIOS name refresh' -FilePath 'nbtstat.exe' `
                        -ArgumentList @('-RR') -SuccessExitCodes @(0, 1) -DryRun:$dryRun))
        }

        # =====================================================================
        # 6. Adapter bounce  (non-destructive; config is preserved)
        # =====================================================================
        if ($doAdapter) {
            if (-not $targets -or $targets.Count -eq 0) {
                $results.Add((Write-StepResult -Step 'Adapter restart' -Status 'Skipped' `
                            -Message 'No matching adapters were found.'))
            }
            else {
                foreach ($nic in $targets) {
                    $step = "Adapter restart [$($nic.Name)]"
                    $done = $false

                    if ((Get-Command Restart-NetAdapter -ErrorAction SilentlyContinue) -and -not $dryRun) {
                        $sw = [System.Diagnostics.Stopwatch]::StartNew()
                        try {
                            Restart-NetAdapter -Name $nic.Name -Confirm:$false -ErrorAction Stop
                            $sw.Stop()
                            $results.Add((Write-StepResult -Step $step -Method 'Cmdlet' `
                                        -Command "Restart-NetAdapter -Name '$($nic.Name)'" -Status 'Success' `
                                        -Duration $sw.Elapsed -Message 'Adapter cycled.'))
                            $done = $true
                        }
                        catch {
                            $sw.Stop()
                            Write-Verbose "Restart-NetAdapter failed for '$($nic.Name)', falling back to netsh: $($_.Exception.Message)"
                        }
                    }

                    if (-not $done) {
                        $results.Add((Invoke-NativeCommand -Step "$step (disable)" -FilePath 'netsh.exe' `
                                    -ArgumentList @('interface', 'set', 'interface', "name=$($nic.Name)", 'admin=disabled') `
                                    -DryRun:$dryRun))
                        if (-not $dryRun) { Start-Sleep -Seconds 3 }
                        $results.Add((Invoke-NativeCommand -Step "$step (enable)" -FilePath 'netsh.exe' `
                                    -ArgumentList @('interface', 'set', 'interface', "name=$($nic.Name)", 'admin=enabled') `
                                    -DryRun:$dryRun))
                    }
                }

                if (-not $dryRun) {
                    Write-Verbose 'Waiting for adapters to come back up...'
                    Start-Sleep -Seconds 5
                }
            }
        }

        # =====================================================================
        # 7. DHCP release / renew  (non-destructive)
        # =====================================================================
        if ($doDhcp) {
            $cimDone = $false

            if (-not $dryRun -and (Get-Command Invoke-CimMethod -ErrorAction SilentlyContinue)) {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $filter = 'IPEnabled = True AND DHCPEnabled = True'
                    $configs = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter $filter -ErrorAction Stop)

                    if ($targets -and $targets.Count) {
                        $names = $targets.Name
                        $nicIndexes = Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction SilentlyContinue |
                            Where-Object { $_.NetConnectionID -in $names } |
                            Select-Object -ExpandProperty InterfaceIndex
                        if ($nicIndexes) {
                            $configs = @($configs | Where-Object { $_.InterfaceIndex -in $nicIndexes })
                        }
                    }

                    if ($configs.Count -eq 0) { throw 'No DHCP-enabled adapter configurations were found.' }

                    foreach ($cfg in $configs) {
                        $null = Invoke-CimMethod -InputObject $cfg -MethodName ReleaseDHCPLease -ErrorAction Stop
                        $null = Invoke-CimMethod -InputObject $cfg -MethodName RenewDHCPLease -ErrorAction Stop
                    }
                    $sw.Stop()
                    $results.Add((Write-StepResult -Step 'DHCP release/renew' -Method 'Cmdlet' `
                                -Command 'Invoke-CimMethod ReleaseDHCPLease / RenewDHCPLease' -Status 'Success' `
                                -Duration $sw.Elapsed -Message "Renewed $($configs.Count) adapter configuration(s)."))
                    $cimDone = $true
                }
                catch {
                    $sw.Stop()
                    Write-Verbose "CIM DHCP renewal failed, falling back to ipconfig: $($_.Exception.Message)"
                }
            }

            if (-not $cimDone) {
                $results.Add((Invoke-NativeCommand -Step 'DHCP release' -FilePath 'ipconfig.exe' `
                            -ArgumentList @('/release') -DryRun:$dryRun))
                if ($IncludeIPv6) {
                    $results.Add((Invoke-NativeCommand -Step 'DHCP release (IPv6)' -FilePath 'ipconfig.exe' `
                                -ArgumentList @('/release6') -DryRun:$dryRun))
                }
                $results.Add((Invoke-NativeCommand -Step 'DHCP renew' -FilePath 'ipconfig.exe' `
                            -ArgumentList @('/renew') -DryRun:$dryRun))
                if ($IncludeIPv6) {
                    $results.Add((Invoke-NativeCommand -Step 'DHCP renew (IPv6)' -FilePath 'ipconfig.exe' `
                                -ArgumentList @('/renew6') -DryRun:$dryRun))
                }
            }
        }

        # =====================================================================
        # 8. DNS: flush, re-register, restart Dnscache  (non-destructive)
        # =====================================================================
        if ($doDns) {
            $flushed = $false
            if ((Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) -and -not $dryRun) {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    Clear-DnsClientCache -ErrorAction Stop
                    $sw.Stop()
                    $results.Add((Write-StepResult -Step 'DNS cache flush' -Method 'Cmdlet' `
                                -Command 'Clear-DnsClientCache' -Status 'Success' -Duration $sw.Elapsed `
                                -Message 'Resolver cache cleared.'))
                    $flushed = $true
                }
                catch {
                    $sw.Stop()
                    Write-Verbose "Clear-DnsClientCache failed, falling back to ipconfig: $($_.Exception.Message)"
                }
            }
            if (-not $flushed) {
                $results.Add((Invoke-NativeCommand -Step 'DNS cache flush' -FilePath 'ipconfig.exe' `
                            -ArgumentList @('/flushdns') -DryRun:$dryRun))
            }

            if ($elevated -or $dryRun) {
                $registered = $false
                if ((Get-Command Register-DnsClient -ErrorAction SilentlyContinue) -and -not $dryRun) {
                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    try {
                        Register-DnsClient -ErrorAction Stop
                        $sw.Stop()
                        $results.Add((Write-StepResult -Step 'DNS registration' -Method 'Cmdlet' `
                                    -Command 'Register-DnsClient' -Status 'Success' -Duration $sw.Elapsed `
                                    -Message 'Client records re-registered.'))
                        $registered = $true
                    }
                    catch {
                        $sw.Stop()
                        Write-Verbose "Register-DnsClient failed, falling back to ipconfig: $($_.Exception.Message)"
                    }
                }
                if (-not $registered) {
                    $results.Add((Invoke-NativeCommand -Step 'DNS registration' -FilePath 'ipconfig.exe' `
                                -ArgumentList @('/registerdns') -DryRun:$dryRun))
                }

                if ($dryRun) {
                    $results.Add((Write-StepResult -Step 'Dnscache service restart' -Method 'Cmdlet' `
                                -Command 'Restart-Service -Name Dnscache -Force' -Status 'WhatIf' `
                                -Message 'Service was not restarted (WhatIf).'))
                }
                else {
                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    try {
                        Restart-Service -Name 'Dnscache' -Force -ErrorAction Stop
                        $sw.Stop()
                        $results.Add((Write-StepResult -Step 'Dnscache service restart' -Method 'Cmdlet' `
                                    -Command 'Restart-Service -Name Dnscache -Force' -Status 'Success' `
                                    -Duration $sw.Elapsed -Message 'DNS Client service restarted.'))
                    }
                    catch {
                        $sw.Stop()
                        # Dnscache is protected on modern Windows builds; expected and harmless.
                        $results.Add((Write-StepResult -Step 'Dnscache service restart' -Method 'Cmdlet' `
                                    -Command 'Restart-Service -Name Dnscache -Force' -Status 'Skipped' `
                                    -Duration $sw.Elapsed `
                                    -Message 'Service is protected by Windows and cannot be restarted; the cache flush above is sufficient.'))
                    }
                }
            }
            else {
                $results.Add((Write-StepResult -Step 'DNS registration' -Status 'Skipped' `
                            -Message 'Requires elevation.'))
            }
        }
    }

    end {
        if (-not $proceed) { return }

        # ---- Summary ---------------------------------------------------------
        Write-Host ''
        Write-Host 'Network stack reset summary' -ForegroundColor Cyan
        Write-Host ('-' * 72) -ForegroundColor DarkGray

        foreach ($r in $results) {
            $color = switch ($r.Status) {
                'Success' { 'Green' }
                'Failed' { 'Red' }
                'Skipped' { 'Yellow' }
                'WhatIf' { 'DarkGray' }
                default { 'Gray' }
            }
            Write-Host ('  {0,-9} ' -f $r.Status) -ForegroundColor $color -NoNewline
            Write-Host ('{0,-36} ' -f $r.Step) -NoNewline
            Write-Host $r.Command -ForegroundColor DarkGray
            if ($r.Status -eq 'Failed' -and $r.Message) {
                Write-Host ("            -> $($r.Message)") -ForegroundColor Red
            }
        }

        Write-Host ('-' * 72) -ForegroundColor DarkGray
        $failed = @($results | Where-Object Status -EQ 'Failed').Count
        Write-Host ("  {0} step(s), {1} failed" -f $results.Count, $failed) `
            -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
        Write-Host ''

        # ---- Backup pointer ---------------------------------------------------
        if ($backupRoot) {
            Write-Host 'Configuration backup:' -ForegroundColor Cyan
            Write-Host "  $backupRoot" -ForegroundColor Gray
            foreach ($b in @($results | Where-Object { $_.Step -like 'Backup:*' -and $_.Message })) {
                Write-Host "  $($b.Message)" -ForegroundColor DarkGray
            }
            Write-Host ''
        }

        # ---- Connectivity sanity check ---------------------------------------
        if (-not $SkipConnectivityTest -and -not $dryRun -and -not $rebootRequired) {
            Write-Host 'Connectivity check:' -ForegroundColor Cyan

            $dnsOk = $false
            try {
                if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
                    $null = Resolve-DnsName -Name 'microsoft.com' -Type A -DnsOnly -ErrorAction Stop
                }
                else {
                    $null = [System.Net.Dns]::GetHostEntry('microsoft.com')
                }
                $dnsOk = $true
            }
            catch { $dnsOk = $false }
            Write-Host '  DNS resolution  : ' -NoNewline
            Write-Host $(if ($dnsOk) { 'OK' } else { 'FAILED' }) -ForegroundColor $(if ($dnsOk) { 'Green' } else { 'Yellow' })

            $pingOk = $false
            try {
                $pingOk = Test-Connection -TargetName '1.1.1.1' -Count 1 -Quiet -ErrorAction Stop
            }
            catch {
                try { $pingOk = Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction Stop }
                catch { $pingOk = $false }
            }
            Write-Host '  ICMP to 1.1.1.1 : ' -NoNewline
            Write-Host $(if ($pingOk) { 'OK' } else { 'FAILED' }) -ForegroundColor $(if ($pingOk) { 'Green' } else { 'Yellow' })
            Write-Host ''
        }

        # ---- Reboot handling --------------------------------------------------
        if ($rebootRequired) {
            Write-Warning 'A reboot is REQUIRED to complete the Winsock / TCP-IP reset. Networking may behave oddly until then.'

            if ($Restart -and -not $dryRun) {
                if ($Force -or $PSCmdlet.ShouldContinue('Restart the computer now?', 'Reboot required')) {
                    Write-Host 'Restarting...' -ForegroundColor Yellow
                    Restart-Computer -Force
                }
            }
            elseif (-not $Restart) {
                Write-Host 'Run with -Restart to reboot automatically next time.' -ForegroundColor DarkGray
            }
        }

        if ($PassThru) {
            $results
        }
    }
}
