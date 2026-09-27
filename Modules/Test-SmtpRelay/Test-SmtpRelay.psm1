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
        If omitted and no pipeline input is provided, the script enters interactive mode. There,
        Ctrl+C or Esc cancels a running (e.g. hung) test and returns to the prompt; Ctrl+C at
        the prompt itself, or typing 'exit', leaves interactive mode.

    .PARAMETER PortList
        An array of specific ports to test. Defaults to 25, 587, 465, 2525.

    .PARAMETER Timeout
        The connection and read timeout in milliseconds. Defaults to 3000ms.

    .OUTPUTS
        PSCustomObject with TargetHost, IPAddress, Port, Status and Banner, one per
        port. Interactive mode renders them as a table per host instead.

    .EXAMPLE
        Test-SmtpRelay microsoft

    .EXAMPLE
        'smtp.office365.com', 'gmail' | Test-SmtpRelay -PortList 587 | Where-Object Status -eq 'OPEN'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
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
            # $Cancel is only supplied by interactive mode (see Invoke-CancellableCheck):
            # a synchronized table whose Client entry lets another thread close the
            # socket of the port currently being tested.
            param($TargetHost, $Ports, $TimeoutMs, $Cancel)

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
                foreach ($PORT in $Ports) {
                    [PSCustomObject]@{
                        TargetHost = $TargetHost
                        IPAddress  = 'N/A'
                        Port       = $PORT
                        Status     = 'DNS_FAILED'
                        Banner     = 'Error: Could not resolve hostname'
                    }
                }
                return
            }
            $PrimaryIP = $IPAddresses[0].IPAddressToString

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

            foreach ($PORT in $Ports) {
                if ($Cancel -and $Cancel.Cancelled) { break }

                $ResultObject = [ordered]@{
                    TargetHost = $TargetHost
                    IPAddress  = $PrimaryIP
                    Port       = $PORT
                    Status     = "FAILED"
                    Banner     = ""
                }

                Write-Host "   Checking TCP Port $PORT... " -NoNewline -ForegroundColor Gray

                if ($PORT -eq 25 -and $SkipPort25) {
                    $SkipLabel = if ($ExitNodeName) { "[SKIPPED - Tailscale Exit Node ($ExitNodeName) Active]" } else { "[SKIPPED - Tailscale Exit Node Active]" }
                    Write-Host $SkipLabel -ForegroundColor Yellow
                    $ResultObject.Status = "SKIPPED"
                    $ResultObject.Banner = "Blocked by Tailscale Policy"
                    [PSCustomObject]$ResultObject
                    continue
                }

                $tcpClient = $null
                $Stream = $null
                $SslStream = $null
                $Reader = $null

                try {
                    $tcpClient = New-Object System.Net.Sockets.TcpClient
                    if ($Cancel) { $Cancel.Client = $tcpClient }

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
                            $Prefix = if ($PORT -eq 465) { "[TLS] " } else { "" }

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

                [PSCustomObject]$ResultObject
            }
        }
    }

    process {
        if ($InteractiveMode) {
            Write-Host "Entering Interactive SMTP Test Mode. Type 'exit' to quit." -ForegroundColor Gray
            Write-Host "Press Ctrl+C or Esc to cancel a running test." -ForegroundColor DarkGray
            while ($true) {
                Write-Host -NoNewline "> " -ForegroundColor Green
                $InputHost = Read-Host
                $InputHost = $InputHost.Trim()

                if ([string]::IsNullOrWhiteSpace($InputHost)) { continue }
                if ($InputHost -match '^(exit|quit)$') { break }

                $run = Invoke-CancellableCheck -Check $RunCheck -Arguments @{
                    TargetHost = $InputHost
                    Ports      = $PortList
                    TimeoutMs  = $Timeout
                }
                # Rendered per host so each result table appears before the next prompt;
                # a cancelled run still shows the ports that finished.
                if ($run.Results.Count) { $run.Results | Format-Table -AutoSize | Out-Host }
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($HOSTNAME)) {
            & $RunCheck -TargetHost $HOSTNAME -Ports $PortList -TimeoutMs $Timeout
        }
    }
}

# Background checks that were cancelled but hadn't finished stopping yet (e.g.
# blocked in DNS resolution, which can't be interrupted). Disposed once done.
$script:PendingChecks = [System.Collections.Generic.List[object]]::new()

function Invoke-CancellableCheck {
    <#
    .SYNOPSIS
        Runs one interactive-mode host check so it can be cancelled with Ctrl+C/Esc.
    .DESCRIPTION
        Ctrl+C normally stops the whole pipeline, and PowerShell cannot resume a loop
        after that, so it would end interactive mode rather than just the hung test.
        Instead the check runs in a background runspace (sharing the host, so its
        Write-Host output still appears) while this thread reads Ctrl+C/Esc as keys.

        On cancel the current socket is closed, which makes a pending connect, TLS
        handshake or banner read fail immediately instead of waiting out -Timeout.
    .PARAMETER CancelRequested
        Returns $true when the user asked to cancel. Defaults to reading the console;
        overridable so cancellation can be exercised without a keyboard.
    .OUTPUTS
        PSCustomObject with Cancelled (bool) and Results (the objects the check
        emitted before it finished or was cancelled).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock]$Check,
        [Parameter(Mandatory)] [hashtable]$Arguments,
        [scriptblock]$CancelRequested = {
            if ([Console]::IsInputRedirected) { return $false }
            while ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'Escape') { return $true }
                if ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control)) { return $true }
            }
            $false
        }
    )

    foreach ($done in @($script:PendingChecks | Where-Object { $_.Handle.IsCompleted })) {
        $done.PowerShell.Dispose()
        $done.Runspace.Dispose()
        $null = $script:PendingChecks.Remove($done)
    }

    $cancel = [hashtable]::Synchronized(@{ Cancelled = $false; Client = $null })
    $runspace = [runspacefactory]::CreateRunspace($Host)
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    $null = $ps.AddScript($Check.ToString()).AddParameters($Arguments).AddParameter('Cancel', $cancel)
    $output = [System.Management.Automation.PSDataCollection[psobject]]::new()
    $handle = $ps.BeginInvoke([System.Management.Automation.PSDataCollection[psobject]]::new(), $output)

    # Without this the console turns Ctrl+C into a pipeline stop before we can read it.
    $restoreCtrlC = $null
    try {
        $restoreCtrlC = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true
    }
    catch { }

    $cancelled = $false
    try {
        while (-not $handle.IsCompleted) {
            if (& $CancelRequested) { $cancelled = $true; break }
            $null = $handle.AsyncWaitHandle.WaitOne(50)
        }
    }
    finally {
        if ($null -ne $restoreCtrlC) { [Console]::TreatControlCAsInput = $restoreCtrlC }
    }

    if ($cancelled) {
        $cancel.Cancelled = $true
        # Stop before closing the socket: the stop takes effect at the check's next
        # command, so the failure the socket close triggers never gets printed as a
        # misleading [FAILED], and a late DNS reply can't write over the next prompt.
        $null = $ps.BeginStop($null, $null)
        $client = $cancel.Client
        if ($client) { $client.Dispose() }
        Write-Host ''
        Write-Host '   [CANCELLED]' -ForegroundColor Yellow

        if ($handle.AsyncWaitHandle.WaitOne(2000)) {
            $ps.Dispose()
            $runspace.Dispose()
        }
        else {
            $script:PendingChecks.Add([pscustomobject]@{ PowerShell = $ps; Runspace = $runspace; Handle = $handle })
        }
    }
    else {
        try { $null = $ps.EndInvoke($handle) }
        catch { Write-Warning "SMTP check failed: $($_.Exception.Message)" }
        $ps.Dispose()
        $runspace.Dispose()
    }

    [pscustomobject]@{ Cancelled = $cancelled; Results = @($output) }
}

# Export only the public function to the user's session
Export-ModuleMember -Function 'Test-SmtpRelay'
