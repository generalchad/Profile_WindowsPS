function Restart-Explorer {
<#
.SYNOPSIS
    Restarts the Windows Explorer shell without opening a File Explorer window.

.DESCRIPTION
    Stops explorer.exe and starts the shell again, for when a change needs the
    shell reloaded (file associations, HKCU registry edits, environment variables).

    Launching explorer.exe while a shell already exists opens a File Explorer
    window instead of restarting the shell, so the shell is only started explicitly
    when Windows has not already relaunched it. When explorer.exe starts with no
    shell running, it hosts the desktop and taskbar without opening a window.
#>
    [CmdletBinding()]
    param ()

    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Write-Verbose 'Explorer.exe is not running; nothing to restart.'
        return
    }

    Write-Verbose 'Stopping Explorer.exe...'
    try {
        Stop-Process -Name explorer -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to stop Explorer.exe: $($_.Exception.Message)"
        return
    }

    # Windows relaunches the shell on its own within a few hundred milliseconds.
    # Give it a chance first: starting explorer.exe ourselves while that relaunch is
    # already in flight would open a File Explorer window instead of just the shell.
    $deadline = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $deadline -and -not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Sleep -Milliseconds 200
    }

    if (Get-Process -Name explorer -ErrorAction SilentlyContinue) {
        Write-Verbose 'Explorer.exe relaunched automatically.'
    }
    else {
        Write-Verbose 'Starting Explorer.exe...'
        Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ErrorAction SilentlyContinue
    }
}
