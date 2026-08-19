function Restart-Explorer {
<#
.SYNOPSIS
Restart-Explorer - Stops and restarts the Windows Explorer process.

.DESCRIPTION
Restart the Windows Explorer process, which is necessary after certain system
settings have been changed.
#>
    [CmdletBinding()]
    param ()

    Write-Verbose "Restarting Explorer.exe..."

    try {
        Write-Debug "Stopping process Explorer.exe"
        Stop-Process -Name explorer -Force
        Start-Sleep -Milliseconds 500
        Write-Debug "Explorer.exe stopped successfully"
    } catch {
        Write-Warning "Failed to stop Explorer.exe: $_"
    }

    Write-Verbose "Starting Explorer.exe..."
}
