function Update-IPConfig {
    <#
    .SYNOPSIS
        Resets the local IPv4 network configuration safely and robustly.
    .DESCRIPTION
        Performs a DNS flush, releases all IPv4 addresses, and attempts to renew them.
        Uses native PowerShell cmdlets where possible and robustly handles native binary exit codes.
    .EXAMPLE
        Update-IPConfig 
        # Prompts for confirmation before disrupting connectivity.
    .EXAMPLE
        Update-IPConfig -Force 
        # Bypasses the confirmation prompt (standard PowerShell practice).
    .EXAMPLE
        Update-IPConfig -y
        # Bypasses the confirmation prompt, using the alias 'y'.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('y', 'yes')] 
        [switch]$Force
    )

    process {
        # THE FIX: We must check $Force manually.
        # Logic: If $Force is TRUE, the first part of the -OR statement is satisfied, 
        # so PowerShell skips the second part (ShouldProcess), avoiding the prompt entirely.
        if ($Force -or $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Reset Local Network Stack (Release/Renew/Flush)")) {
            
            Write-Host "`n--- Resetting Network Configuration ---" -ForegroundColor Yellow

            # 1. Flush DNS
            Write-Host "1. Flushing DNS Cache... " -NoNewline -ForegroundColor Cyan
            try {
                Clear-DnsClientCache -ErrorAction Stop
                Write-Host "[OK]" -ForegroundColor Green
            }
            catch {
                Write-Host "[FAILED]" -ForegroundColor Red
                Write-Warning "DNS Flush failed: $($_.Exception.Message)"
            }

            # 2. Release IP
            Write-Host "2. Releasing current IP addresses... " -NoNewline -ForegroundColor Cyan
            $releaseOut = ipconfig /release 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK]" -ForegroundColor Green
            } else {
                Write-Host "[Error]" -ForegroundColor Red
                Write-Warning "Release failed. Output: $($releaseOut | Out-String)"
            }

            # 3. Renew IP
            Write-Host "3. Renewing IP addresses (may take time)... " -NoNewline -ForegroundColor Cyan
            $renewOut = ipconfig /renew 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK]" -ForegroundColor Green
            } else {
                Write-Host "[FAILED]" -ForegroundColor Red
                Write-Warning "DHCP Renew failed. Output: $($renewOut | Out-String)"
            }

            Write-Host ""

            # 4. Reporting
            Write-Host "--- Current IPv4 Configuration ---" -ForegroundColor Yellow
            $NetConfig = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                Where-Object { 
                    $_.InterfaceAlias -notmatch "Loopback|vEthernet|Pseudo" -and 
                    $_.AddressState -eq "Preferred" 
                } |
                Select-Object InterfaceAlias, IPAddress, PrefixLength, InterfaceIndex

            if ($NetConfig) {
                $NetConfig | Format-Table -AutoSize
            } else {
                Write-Host "No active IPv4 addresses found. You may be disconnected." -ForegroundColor Red
            }
        }
    }
}