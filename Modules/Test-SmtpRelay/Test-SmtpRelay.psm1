function Test-SmtpRelay {
    <#
    .SYNOPSIS
        Tests SMTP connectivity and banner retrieval for common mail relays.

    .DESCRIPTION
        Tests a target hostname against common SMTP ports (25, 587, 465, 2525).
        Includes intelligent alias mapping (e.g., typing "microsoft" resolves to "smtp.office365.com")
        and automatically detects active Tailscale exit nodes to prevent false negatives on Port 25.
        Supports pipeline input for bulk testing and performs implicit TLS banner grabbing on Port 465.

    .PARAMETER HOSTNAME
        The target SMTP server FQDN or a known alias (e.g., microsoft, gmail, proofpoint, mimecast).
        If omitted and no pipeline input is provided, the script enters interactive mode.

    .PARAMETER PortList
        An array of specific ports to test. Defaults to 25, 587, 465, 2525.

    .PARAMETER Timeout
        The connection and read timeout in milliseconds. Defaults to 3000ms.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$HOSTNAME,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateRange(1, 65535)]
        [int[]]$PortList,

        [Parameter(Mandatory = $false)]
        [ValidateRange(500, 30000)]
        [int]$Timeout = 3000
    )

    begin {
        if (-not $PSBoundParameters.ContainsKey('PortList')) {
            $PortList = @(25, 587, 465, 2525)
        }

        # Determine if we should drop into interactive mode (no arg passed & no pipeline input detected)
        $InteractiveMode = (-not $PSBoundParameters.ContainsKey('HOSTNAME')) -and (-not $MyInvocation.ExpectingInput)

        $RunCheck = {
            param($TargetHost, $Ports, $TimeoutMs)

            switch -Regex ($TargetHost) {
                "^(gmail|google|gsuite|workspace)$"                                { $TargetHost = "smtp.gmail.com"; break }
                "^(office|o365|outlook|hotmail|live|msn|microsoft|m365|exchange)$" { $TargetHost = "smtp.office365.com"; break }
                "^(yahoo|ymail|rocketmail|sbcglobal|att\.net)$"                    { $TargetHost = "smtp.mail.yahoo.com"; break }
                "^(icloud|me\.com|mac\.com|apple)$"                                { $TargetHost = "smtp.mail.me.com"; break }
                "^(aws|ses|amazonses)$"                                            { $TargetHost = "email-smtp.us-east-1.amazonaws.com"; break }
                "^(proofpoint|pp)$"                                                { $TargetHost = "relay.proofpoint.com"; break }
                "^mimecast$"                                                       { $TargetHost = "us-smtp-1.mimecast.com"; break }
                "^(cisco|ironport)$"                                               { $TargetHost = "res.cisco.com"; break }
                "^sendgrid$"                                                       { $TargetHost = "smtp.sendgrid.net"; break }
                "^mailgun$"                                                        { $TargetHost = "smtp.mailgun.org"; break }
                "^postmark$"                                                       { $TargetHost = "smtp.postmarkapp.com"; break }
                "^smtp2go$"                                                        { $TargetHost = "mail.smtp2go.com"; break }
                "^(mandrill|mailchimp)$"                                           { $TargetHost = "smtp.mandrillapp.com"; break }
                "^(brevo|sendinblue)$"                                             { $TargetHost = "smtp-relay.brevo.com"; break }
                "^mailjet$"                                                        { $TargetHost = "in-v3.mailjet.com"; break }
                "^sparkpost$"                                                      { $TargetHost = "smtp.sparkpostmail.com"; break }
                "^fastmail$"                                                       { $TargetHost = "smtp.fastmail.com"; break }
                "^hubspot$"                                                        { $TargetHost = "smtp.hubspot.com"; break }
                "^(comcast|xfinity)$"                                              { $TargetHost = "smtp.comcast.net"; break }
                "^verizon$"                                                        { $TargetHost = "smtp.verizon.net"; break }
                "^(spectrum|charter)$"                                             { $TargetHost = "mobile.charter.net"; break }
                "^cox$"                                                            { $TargetHost = "smtp.cox.net"; break }
                "^zoho$"                                                           { $TargetHost = "smtp.zoho.com"; break }
                "^godaddy$"                                                        { $TargetHost = "smtpout.secureserver.net"; break }
                "^rackspace$"                                                      { $TargetHost = "secure.emailsrvr.com"; break }
                "^(ionos|1and1)$"                                                  { $TargetHost = "smtp.ionos.com"; break }
                Default {
                    # Keep custom/unmapped domains as is
                }
            }

            Write-Host "`n--- Testing SMTP Connectivity for $TargetHost ---" -ForegroundColor Yellow

            Write-Host "Resolving DNS for '$TargetHost'..." -NoNewline -ForegroundColor Cyan
            try {
                $IPAddresses = [System.Net.Dns]::GetHostAddresses($TargetHost)

                if ($IPAddresses.Count -gt 0) {
                    Write-Host " [OK]" -ForegroundColor Green
                    Write-Host "   -> $($IPAddresses.Count) address(es):" -ForegroundColor DarkGray

                    # Print each IP on its own line indented relative to the header
                    foreach ($IP in $IPAddresses) {
                        Write-Host "      $($IP.IPAddressToString)" -ForegroundColor DarkGray
                    }

                    # Empty newline after IP list
                    Write-Host ""
                }
            }
            catch {
                Write-Host " [FAILED]" -ForegroundColor Red
                Write-Host "   ! TIP: Check if the system has valid DNS Servers (e.g., 8.8.8.8) and Gateway.`n" -ForegroundColor DarkRed
                return
            }

            $SkipPort25 = $false
            $ExitNodeName = ""
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
                    }
                } catch {}
            }

            # Heading matching 'Resolving DNS...' styling
            Write-Host "Testing Ports..." -ForegroundColor Cyan

            $BatchResults = @()

            foreach ($PORT in $Ports) {
                $ResultObject = [ordered]@{
                    Port   = $PORT
                    Status = "FAILED"
                    Banner = ""
                }

                Write-Host "   Checking TCP Port $PORT... " -NoNewline -ForegroundColor Gray

                if ($PORT -eq 25 -and $SkipPort25) {
                    $SkipLabel = if ($ExitNodeName) { "[SKIPPED - Tailscale Exit Node ($ExitNodeName) Active]" } else { "[SKIPPED - Tailscale Exit Node Active]" }
                    Write-Host $SkipLabel -ForegroundColor Yellow
                    $ResultObject.Status = "SKIPPED"
                    $ResultObject.Banner = "Blocked by Tailscale Policy"
                    $BatchResults += [PSCustomObject]$ResultObject
                    continue
                }

                $tcpClient = $null
                $Stream = $null
                $SslStream = $null
                $Reader = $null

                try {
                    $tcpClient = New-Object System.Net.Sockets.TcpClient

                    $connectAsync = $tcpClient.BeginConnect($TargetHost, $PORT, $null, $null)
                    if (-not $connectAsync.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
                        throw "Connection timed out"
                    }
                    $tcpClient.EndConnect($connectAsync)

                    if ($tcpClient.Connected) {
                        $ResultObject.Status = "OPEN"

                        try {
                            $Stream = $tcpClient.GetStream()
                            $Stream.ReadTimeout = $TimeoutMs

                            # Handle implicit TLS on Port 465 to retrieve the encrypted banner
                            if ($PORT -eq 465) {
                                # Bypass cert validation so self-signed or untrusted relay certs don't block banner reading
                                $SslCallback = { param($sender, $cert, $chain, $errors) return $true }
                                $SslStream = [System.Net.Security.SslStream]::new($Stream, $false, $SslCallback)
                                $SslStream.AuthenticateAsClient($TargetHost)
                                $Reader = [System.IO.StreamReader]::new($SslStream)
                            } else {
                                $Reader = [System.IO.StreamReader]::new($Stream)
                            }

                            $ServerBanner = $Reader.ReadLine()

                            if (-not [string]::IsNullOrWhiteSpace($ServerBanner)) {
                                $ResultObject.Banner = $Prefix + $ServerBanner.Trim()
                            } else {
                                $ResultObject.Banner = if ($PORT -eq 465) { "[TLS] (No Banner)" } else { "(No Banner)" }
                            }
                        }
                        catch {
                            if ($PORT -eq 465) {
                                $ResultObject.Banner = "Encrypted (TLS Handshake Failed)"
                            } else {
                                $ResultObject.Banner = "(Timeout reading banner)"
                            }
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
                    # Explicitly dispose of all stream and socket objects to prevent handle leaks
                    if ($Reader) { $Reader.Dispose() }
                    if ($SslStream) { $SslStream.Dispose() }
                    if ($Stream) { $Stream.Dispose() }
                    if ($tcpClient) { $tcpClient.Close(); $tcpClient.Dispose() }
                }

                $BatchResults += [PSCustomObject]$ResultObject
            }

            # Directly pipe to Format-Table without extra Write-Host calls to maintain clean 1-line spacing
            $BatchResults | Format-Table -AutoSize
        }
    }

    process {
        if ($InteractiveMode) {
            Write-Host "Entering Interactive SMTP Test Mode. Type 'exit' to quit." -ForegroundColor Gray
            while ($true) {
                Write-Host -NoNewline "> " -ForegroundColor Green
                $InputHost = Read-Host
                $InputHost = $InputHost.Trim()

                if ([string]::IsNullOrWhiteSpace($InputHost)) { continue }
                if ($InputHost -match '^(exit|quit)$') { break }

                & $RunCheck -TargetHost $InputHost -Ports $PortList -TimeoutMs $Timeout
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($HOSTNAME)) {
            & $RunCheck -TargetHost $HOSTNAME -Ports $PortList -TimeoutMs $Timeout
        }
    }
}

# Export only the public function to the user's session
Export-ModuleMember -Function 'Test-SmtpRelay'
