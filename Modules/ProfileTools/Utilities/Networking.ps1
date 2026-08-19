function Test-NetSpeed {
    if (Test-CommandExists librespeed-cli) {
        librespeed-cli $args[0]
    }
    else {
        Write-Error "Test-NetSpeed: librespeed-cli is not installed."
    }
}

function Show-MyIP {
    $interfaces = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
        Where-Object { $_.IPAddress -ne "127.0.0.1" }
    
    Write-Host "Local IP Address(es):" -ForegroundColor Cyan
    
    if ($interfaces.Count -eq 0) {
        Write-Host " - No IPv4 addresses found" -ForegroundColor Yellow
        return
    }
    
    foreach ($interface in $interfaces) {
        $interfaceName = $interface.InterfaceAlias
        $ipAddress = $interface.IPAddress
        Write-Host " - $interfaceName : " -NoNewline -ForegroundColor Green
        Write-Host "$ipAddress" -ForegroundColor Yellow
    }
}