function Update-IPConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # 1. Safety Check for Remote Sessions
    if (-not $Force) {
        Write-Host "WARNING: This will drop network connections temporarily." -ForegroundColor Yellow
        Write-Host "If you are connected via RDP/SSH, you may lose access." -ForegroundColor Yellow
        
        $confirmation = Read-Host "Are you sure you want to proceed? (y/N)"
        
        if ($confirmation -notmatch "^[Yy]$") {
            Write-Host "Aborted." -ForegroundColor Red
            return
        }
    }

    if (-not $PSCmdlet.ShouldProcess("Local network configuration", "Reset")) {
        return
    }

    Write-Host "--- Resetting Network Configuration ---" -ForegroundColor Yellow

    # 2. Flush DNS
    Write-Host "1. Flushing DNS Cache... " -NoNewline -ForegroundColor Cyan
    try {
        $null = ipconfig /flushdns
        Write-Host "[OK]" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAILED]" -ForegroundColor Red
    }

    # 3. Release IP
    Write-Host "2. Releasing current IP addresses... " -NoNewline -ForegroundColor Cyan
    try {
        $null = ipconfig /release 2>&1
        Write-Host "[OK]" -ForegroundColor Green
    }
    catch {
        Write-Host "[Error]" -ForegroundColor Red
    }

    # 4. Renew IP
    Write-Host "3. Renewing IP addresses (this may take a moment)... " -NoNewline -ForegroundColor Cyan
    try {
        $null = ipconfig /renew 2>&1
        Write-Host "[OK]" -ForegroundColor Green
    }
    catch {
        Write-Host "[Timeout/Error]" -ForegroundColor Red
        Write-Host "   Note: If DHCP is down, this takes a while." -ForegroundColor DarkGray
    }

    Write-Host ""

    # 5. Show Current IPv4 Configuration
    Write-Host "--- Current IPv4 Configuration ---" -ForegroundColor Yellow
    
    $NetConfig = Get-NetIPAddress -AddressFamily IPv4 | 
                Where-Object { $_.InterfaceAlias -notmatch "Loopback|vEthernet" } |
                Select-Object InterfaceAlias, IPAddress, PrefixLength

    if ($NetConfig) {
        format-table -InputObject $NetConfig -AutoSize
    }
    else {
        Write-Host "No active IPv4 addresses found." -ForegroundColor Red
    }
}