function Test-FileShare {
    <#
    .SYNOPSIS
        Tests SMB and FTP/SFTP/FTPS connectivity for MFP Scan-to-Folder troubleshooting.

    .DESCRIPTION
        Tests target hostnames against common file sharing ports (21, 22, 139, 445, 990).
        Includes intelligent alias mapping, automatic VPN/Tailscale SMB blocking detection,
        implicit TLS banner grabbing on Port 990, and full pipeline support.

    .PARAMETER Hostname
        The target server FQDN, IP address, or known alias (e.g., localhost, gateway, rebex, azure).

    .PARAMETER PortList
        An array of specific ports to test. Defaults to 21, 22, 139, 445, 990.

    .PARAMETER Timeout
        The connection and read timeout in milliseconds. Defaults to 3000ms.

    .PARAMETER ForceSmb
        Bypasses WAN/Tailscale SMB blocking detection and forces testing on ports 139 and 445.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Hostname,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateRange(1, 65535)]
        [int[]]$PortList = @(21, 22, 139, 445, 990),

        [Parameter(Mandatory = $false)]
        [ValidateRange(500, 30000)]
        [int]$Timeout = 3000,

        [Parameter(Mandatory = $false)]
        [switch]$ForceSmb
    )

    begin {
        # Check for Tailscale exit node once per execution batch, not per pipeline item
        $SkipSmbWan = $false
        $ExitNodeName = $null

        if (-not $ForceSmb -and (Get-Command tailscale -ErrorAction SilentlyContinue)) {
            try {
                $TsStatus = tailscale status --json | ConvertFrom-Json
                if ($TsStatus.BackendState -eq "Running" -and ($TsStatus.ExitNodeStatus -or $TsStatus.ExitNodeID)) {
                    $SkipSmbWan = $true
                    $ExitNodeName = $TsStatus.ExitNodeStatus.Label
                    if (-not $ExitNodeName) { $ExitNodeName = $TsStatus.ExitNodeStatus.ID }
                    if (-not $ExitNodeName) { $ExitNodeName = $TsStatus.ExitNodeID }
                    Write-Verbose "Active Tailscale Exit Node detected ($ExitNodeName). SMB ports will be skipped unless -ForceSmb is used."
                }
            } catch {
                Write-Verbose "Tailscale command found, but status could not be queried: $_"
            }
        }
    }

    process {
        foreach ($Target in $Hostname) {
            # 1. Resolve Aliases
            $ResolvedHost = switch -Regex ($Target) {
                "^(local|localhost|self|thispc)$" { $env:COMPUTERNAME; break }
                "^(gateway|router)$" {
                    try {
                        $gw = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
                              Select-Object -ExpandProperty NextHop -First 1
                        if ($gw) { $gw } else { "192.168.1.1" }
                    } catch { "192.168.1.1" }
                    break
                }
                "^(rebex|testftp|testsftp)$"      { "test.rebex.net"; break }
                "^(tele2|speedtest|testftp2)$"    { "speedtest.tele2.net"; break }
                "^(azure|azurefiles)$"            { "storage.file.core.windows.net"; break }
                "^(box|ftpbox)$"                  { "ftp.box.com"; break }
                "^(egnyte)$"                      { "ftp.egnyte.com"; break }
                "^(drivehq)$"                     { "ftp.drivehq.com"; break }
                Default                           { $Target }
            }

            Write-Verbose "Testing target: $ResolvedHost (Original input: $Target)"

            # 2. DNS Resolution Check
            $IPAddresses = @()
            try {
                $IPAddresses = [System.Net.Dns]::GetHostAddresses($ResolvedHost)
                Write-Verbose "Resolved $ResolvedHost to: $($IPAddresses.IPAddressToString -join ', ')"
            } catch {
                Write-Error "DNS Resolution failed for '$ResolvedHost'. Check DNS servers and routing."

                # Emit a failure object to maintain pipeline continuity
                foreach ($Port in $PortList) {
                    [PSCustomObject]@{
                        TargetHost = $ResolvedHost
                        IPAddress  = "N/A"
                        Port       = $Port
                        Status     = "DNS_FAILED"
                        Banner     = "Error: Could not resolve hostname"
                    }
                }
                continue
            }

            $PrimaryIP = $IPAddresses[0].IPAddressToString

            # 3. Port Testing Loop
            foreach ($Port in $PortList) {
                Write-Progress -Activity "Testing File Share Connectivity" -Status "Checking ${ResolvedHost}:${Port}" -PercentComplete (($PortList.IndexOf($Port) / $PortList.Count) * 100)

                $Status = "FAILED"
                $Banner = ""

                # Handle VPN/Tailscale SMB blocking
                if ($Port -in @(139, 445) -and $SkipSmbWan) {
                    [PSCustomObject]@{
                        TargetHost = $ResolvedHost
                        IPAddress  = $PrimaryIP
                        Port       = $Port
                        Status     = "SKIPPED"
                        Banner     = "Blocked by Tailscale Exit Node ($ExitNodeName)"
                    }
                    continue
                }

                $tcpClient = $null
                $Stream = $null
                $SslStream = $null
                $Reader = $null

                try {
                    $tcpClient = [System.Net.Sockets.TcpClient]::new()
                    $connectAsync = $tcpClient.BeginConnect($ResolvedHost, $Port, $null, $null)

                    if (-not $connectAsync.AsyncWaitHandle.WaitOne($Timeout, $false)) {
                        throw "Connection timed out after ${Timeout}ms"
                    }
                    $tcpClient.EndConnect($connectAsync)

                    if ($tcpClient.Connected) {
                        $Status = "OPEN"
                        $Stream = $tcpClient.GetStream()
                        $Stream.ReadTimeout = $Timeout

                        if ($Port -in @(139, 445)) {
                            $Banner = if ($Port -eq 139) { "NetBIOS Session Service (Legacy SMBv1)" } else { "Direct SMB Service (SMBv2/v3 Reachable)" }
                        }
                        elseif ($Port -eq 990) {
                            try {
                                $SslCallback = { param($sender, $cert, $chain, $errors) return $true }
                                $SslStream = [System.Net.Security.SslStream]::new($Stream, $false, $SslCallback)
                                $SslStream.AuthenticateAsClient($ResolvedHost)
                                $Reader = [System.IO.StreamReader]::new($SslStream)
                                $ServerBanner = $Reader.ReadLine()
                                $Banner = if (-not [string]::IsNullOrWhiteSpace($ServerBanner)) { "[TLS] " + $ServerBanner.Trim() } else { "[TLS] (No Banner)" }
                            } catch {
                                $Banner = "Encrypted (TLS Handshake Failed)"
                            }
                        }
                        else {
                            try {
                                $Reader = [System.IO.StreamReader]::new($Stream)
                                $ServerBanner = $Reader.ReadLine()
                                $Banner = if (-not [string]::IsNullOrWhiteSpace($ServerBanner)) { $ServerBanner.Trim() } else { "(No Banner)" }
                            } catch {
                                $Banner = "(Timeout reading banner)"
                            }
                        }
                    }
                }
                catch {
                    $ErrorMessage = $_.Exception.Message -replace "No connection could be made because the target machine actively refused it", "Connection Refused"
                    $Banner = "Error: $ErrorMessage"
                }
                finally {
                    if ($Reader)    { $Reader.Dispose() }
                    if ($SslStream) { $SslStream.Dispose() }
                    if ($Stream)    { $Stream.Dispose() }
                    if ($tcpClient) { $tcpClient.Close(); $tcpClient.Dispose() }
                }

                # Emit clean object to pipeline
                [PSCustomObject]@{
                    TargetHost = $ResolvedHost
                    IPAddress  = $PrimaryIP
                    Port       = $Port
                    Status     = $Status
                    Banner     = $Banner
                }
            }
        }
        Write-Progress -Activity "Testing File Share Connectivity" -Completed
    }
}

Export-ModuleMember -Function 'Test-FileShare'
