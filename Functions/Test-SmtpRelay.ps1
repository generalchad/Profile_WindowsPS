function Test-SmtpRelay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$HOSTNAME,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateRange(1, 65535)]
        [int[]]$PortList
    )

    # 1. Default Ports
    if (-not $PSBoundParameters.ContainsKey('PortList')) {
        $PortList = @(25, 587, 465, 2525)
    }

    # 2. Hostnames and Aliases
    switch -Regex ($HOSTNAME) {
        "gmail|google|gsuite" { $HOSTNAME = "smtp.gmail.com"; break }
        "office|o365|outlook|hotmail|live|msn" { $HOSTNAME = "smtp.office365.com"; break }
        "yahoo|ymail|rocketmail|sbcglobal|att\.net" { $HOSTNAME = "smtp.mail.yahoo.com"; break }
        "icloud|me\.com|mac\.com" { $HOSTNAME = "smtp.mail.me.com"; break }
        "sendgrid" { $HOSTNAME = "smtp.sendgrid.net"; break }
        "mailgun"  { $HOSTNAME = "smtp.mailgun.org"; break }
        "postmark" { $HOSTNAME = "smtp.postmarkapp.com"; break }
        "smtp2go"  { $HOSTNAME = "mail.smtp2go.com"; break }
        "mandrill" { $HOSTNAME = "smtp.mandrillapp.com"; break }
        "comcast|xfinity" { $HOSTNAME = "smtp.comcast.net"; break }
        "verizon"         { $HOSTNAME = "smtp.verizon.net"; break }
        "spectrum|charter" { $HOSTNAME = "mobile.charter.net"; break }
        "cox"             { $HOSTNAME = "smtp.cox.net"; break }
        "zoho"      { $HOSTNAME = "smtp.zoho.com"; break }
        "godaddy"   { $HOSTNAME = "smtpout.secureserver.net"; break }
        "rackspace" { $HOSTNAME = "secure.emailsrvr.com"; break }
        "ionos|1and1" { $HOSTNAME = "smtp.ionos.com"; break }
        Default { 
            # Use the string exactly as typed 
        }
    }

    Write-Host "--- Testing SMTP Connectivity for $HOSTNAME ---" -ForegroundColor Yellow

    # 3. DNS Resolution Check
    Write-Host "Resolving DNS for '$HOSTNAME'..." -ForegroundColor Cyan
    try {
        $IPAddresses = [System.Net.Dns]::GetHostAddresses($HOSTNAME)
        
        if ($IPAddresses.Count -gt 0) {
            Write-Host "   [OK] DNS Resolved successfully. Found $($IPAddresses.Count) address(es):" -ForegroundColor Green
            
            foreach ($ip in $IPAddresses) {
                $Type = if ($ip.AddressFamily -eq 'InterNetwork') { "IPv4" } else { "IPv6" }
                Write-Host "    -> $Type : $($ip.IPAddressToString)" -ForegroundColor Green
            }
            Write-Host ""
        }
        else {
            throw "DNS returned 0 records."
        }
    }
    catch {
        Write-Host "   [FAILED] Could not resolve hostname." -ForegroundColor Red
        Write-Host "   ! TIP: Check if the printer has valid DNS Servers (e.g., 8.8.8.8) and Gateway." -ForegroundColor DarkRed
        Write-Host "   ! Aborting port checks." -ForegroundColor DarkRed
        return # Stop processing if DNS fails
    }

    # 4. Iterate through ports
    foreach ($PORT in $PortList) {
        $ResultObject = [PSCustomObject]@{
            Hostname = $HOSTNAME
            Port     = $PORT
            Status   = "FAILED"
            Banner   = $null
            Details  = ""
        }

        Write-Host "Checking Port $PORT... " -NoNewline -ForegroundColor Gray
        
        $tcpClient = $null

        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            
            # Connection Timeout (5 seconds)
            $connectAsync = $tcpClient.BeginConnect($HOSTNAME, $PORT, $null, $null)
            if (-not $connectAsync.AsyncWaitHandle.WaitOne(5000, $false)) {
                throw "Connection timed out"
            }
            $tcpClient.EndConnect($connectAsync)

            if ($tcpClient.Connected) {
                $ResultObject.Status = "OPEN"
                $BannerText = "Connection Established"

                # 5. Handshake / Banner Check
                if ($PORT -ne 465) {
                    try {
                        $Stream = $tcpClient.GetStream()
                        $Stream.ReadTimeout = 2000 
                        $Reader = New-Object System.IO.StreamReader($Stream)
                        
                        $ServerBanner = $Reader.ReadLine()
                        
                        if (-not [string]::IsNullOrWhiteSpace($ServerBanner)) {
                            $ResultObject.Banner = $ServerBanner
                            $BannerText = "Banner: $ServerBanner"
                        }
                    }
                    catch {
                        $BannerText = "Open, but timed out reading banner"
                    }
                } else {
                    $ResultObject.Banner = "Encrypted (SSL)"
                    $BannerText = "Open (Implicit SSL)"
                }

                # Success Output
                Write-Host "[OPEN]" -ForegroundColor Green
                Write-Host "   Info: $BannerText" -ForegroundColor DarkGray
                $ResultObject.Details = $BannerText
            }
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            if ($ErrorMessage -match "refused") { $ErrorMessage = "Refused" }
            if ($ErrorMessage -match "timed out") { $ErrorMessage = "Timed Out" }
            
            $ResultObject.Details = $ErrorMessage
            
            Write-Host "[FAILED]" -ForegroundColor Red
            Write-Host "   Error: $ErrorMessage" -ForegroundColor DarkRed
        }
        finally {
            if ($tcpClient) { $tcpClient.Close(); $tcpClient.Dispose() }
        }
        
        Write-Host ""
        Write-Output $ResultObject
    }
}