function Test-SmtpRelay {
    <#
    .SYNOPSIS
        Tests SMTP connectivity and banner retrieval for common mail relays.

    .DESCRIPTION
        Tests a target hostname against common SMTP ports (25, 587, 465, 2525).
        Includes intelligent alias mapping (e.g., typing "gmail" resolves to "smtp.gmail.com")
        and automatically detects active Tailscale exit nodes to prevent false negatives on Port 25.

    .PARAMETER HOSTNAME
        The target SMTP server FQDN or a known alias (e.g., office, gmail, sendgrid).
        If omitted, the script enters interactive mode.

    .PARAMETER PortList
        An array of specific ports to test. Defaults to 25, 587, 465, 2525.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$HOSTNAME,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateRange(1, 65535)]
        [int[]]$PortList
    )

    $RunCheck = {
        param($TargetHost, $Ports)

        switch -Regex ($TargetHost) {
            "^(gmail|google|gsuite)$"                     { $TargetHost = "smtp.gmail.com"; break }
            "^(office|o365|outlook|hotmail|live|msn)$"    { $TargetHost = "smtp.office365.com"; break }
            "^(yahoo|ymail|rocketmail|sbcglobal|att\.net)$" { $TargetHost = "smtp.mail.yahoo.com"; break }
            "^(icloud|me\.com|mac\.com)$"                 { $TargetHost = "smtp.mail.me.com"; break }
            "^sendgrid$"                                  { $TargetHost = "smtp.sendgrid.net"; break }
            "^mailgun$"                                   { $TargetHost = "smtp.mailgun.org"; break }
            "^postmark$"                                  { $TargetHost = "smtp.postmarkapp.com"; break }
            "^smtp2go$"                                   { $TargetHost = "mail.smtp2go.com"; break }
            "^mandrill$"                                  { $TargetHost = "smtp.mandrillapp.com"; break }
            "^(comcast|xfinity)$"                         { $TargetHost = "smtp.comcast.net"; break }
            "^verizon$"                                   { $TargetHost = "smtp.verizon.net"; break }
            "^(spectrum|charter)$"                        { $TargetHost = "mobile.charter.net"; break }
            "^cox$"                                       { $TargetHost = "smtp.cox.net"; break }
            "^zoho$"                                      { $TargetHost = "smtp.zoho.com"; break }
            "^godaddy$"                                   { $TargetHost = "smtpout.secureserver.net"; break }
            "^rackspace$"                                 { $TargetHost = "secure.emailsrvr.com"; break }
            "^(ionos|1and1)$"                             { $TargetHost = "smtp.ionos.com"; break }
            Default {
                # Keep custom/unmapped domains as is
            }
        }

        Write-Host "`n--- Testing SMTP Connectivity for $TargetHost ---" -ForegroundColor Yellow

        Write-Host "Resolving DNS for '$TargetHost'..." -NoNewline -ForegroundColor Cyan
        try {
            $IPAddresses = [System.Net.Dns]::GetHostAddresses($TargetHost)

            if ($IPAddresses.Count -gt 0) {
                $IPList = ($IPAddresses.IPAddressToString | Select-Object -First 3) -join ", "
                if ($IPAddresses.Count -gt 3) { $IPList += ", ..." }

                Write-Host " [OK]" -ForegroundColor Green
                Write-Host "   -> $($IPAddresses.Count) address(es): $IPList" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Host " [FAILED]" -ForegroundColor Red
            Write-Host "   ! TIP: Check if the system has valid DNS Servers (e.g., 8.8.8.8) and Gateway." -ForegroundColor DarkRed
            return
        }

        $SkipPort25 = $false
        if (Get-Command tailscale -ErrorAction SilentlyContinue) {
            try {
                $TsStatus = tailscale status --json | ConvertFrom-Json

                # Check for active exit node (Status object or direct ID)
                if ($TsStatus.BackendState -eq "Running" -and ($TsStatus.ExitNodeStatus -or $TsStatus.ExitNodeID)) {
                    $SkipPort25 = $true

                    # Robust Name/ID retrieval
                    $ExitNodeName = $TsStatus.ExitNodeStatus.Label
                    if (-not $ExitNodeName) { $ExitNodeName = $TsStatus.ExitNodeStatus.ID }
                    if (-not $ExitNodeName) { $ExitNodeName = $TsStatus.ExitNodeID }

                    Write-Host "   [INFO] Tailscale Exit Node Active ($ExitNodeName). Port 25 will be skipped." -ForegroundColor Magenta
                }
            } catch {}
        }

        Write-Host "" # Spacer

        $BatchResults = @()

        foreach ($PORT in $Ports) {
            $ResultObject = [ordered]@{
                Port     = $PORT
                Status   = "FAILED"
                Banner   = ""
            }

            Write-Host "   Checking Port $PORT... " -NoNewline -ForegroundColor Gray

            if ($PORT -eq 25 -and $SkipPort25) {
                Write-Host "[SKIPPED]" -ForegroundColor Yellow
                $ResultObject.Status = "SKIPPED"
                $ResultObject.Banner = "Blocked by Tailscale Policy"
                $BatchResults += [PSCustomObject]$ResultObject
                continue
            }

            $tcpClient = $null
            $Stream = $null
            $Reader = $null

            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient

                $connectAsync = $tcpClient.BeginConnect($TargetHost, $PORT, $null, $null)
                if (-not $connectAsync.AsyncWaitHandle.WaitOne(3000, $false)) {
                    throw "Connection timed out"
                }
                $tcpClient.EndConnect($connectAsync)

                if ($tcpClient.Connected) {
                    $ResultObject.Status = "OPEN"

                    if ($PORT -ne 465) {
                        try {
                            $Stream = $tcpClient.GetStream()
                            $Stream.ReadTimeout = 2000
                            $Reader = New-Object System.IO.StreamReader($Stream)
                            $ServerBanner = $Reader.ReadLine()

                            if (-not [string]::IsNullOrWhiteSpace($ServerBanner)) {
                                $ResultObject.Banner = $ServerBanner.Trim()
                            } else {
                                $ResultObject.Banner = "(No Banner)"
                            }
                        }
                        catch {
                            $ResultObject.Banner = "(Time out reading banner)"
                        }
                    } else {
                        $ResultObject.Banner = "Encrypted (SSL)"
                    }

                    Write-Host "[OPEN]" -ForegroundColor Green
                }
            }
            catch {
                $ErrorMessage = $_.Exception.Message
                if ($ErrorMessage -match "refused") { $ErrorMessage = "Refused" }
                if ($ErrorMessage -match "timed out") { $ErrorMessage = "Timed Out" }

                $ResultObject.Banner = "Error: $ErrorMessage"
                Write-Host "[FAILED]" -ForegroundColor Red
            }
            finally {
                # Explicitly dispose of stream objects to prevent memory/handle leaks
                if ($Reader) { $Reader.Dispose() }
                if ($Stream) { $Stream.Dispose() }
                if ($tcpClient) { $tcpClient.Close(); $tcpClient.Dispose() }
            }

            $BatchResults += [PSCustomObject]$ResultObject
        }

        Write-Host ""
        $BatchResults | Format-Table -AutoSize
    }

    if (-not $PSBoundParameters.ContainsKey('PortList')) {
        $PortList = @(25, 587, 465, 2525)
    }

    if (-not [string]::IsNullOrWhiteSpace($HOSTNAME)) {
        & $RunCheck -TargetHost $HOSTNAME -Ports $PortList
    }
    else {
        Write-Host "Entering Interactive SMTP Test Mode. Type 'exit' to quit." -ForegroundColor Gray
        while ($true) {
            Write-Host -NoNewline "> " -ForegroundColor Green
            $InputHost = Read-Host
            $InputHost = $InputHost.Trim()

            if ([string]::IsNullOrWhiteSpace($InputHost)) { continue }
            if ($InputHost -match '^(exit|quit)$') { break }

            & $RunCheck -TargetHost $InputHost -Ports $PortList
        }
    }
}
