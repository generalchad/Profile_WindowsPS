function Invoke-Elevation {
    <#
    .SYNOPSIS
        Relaunches the current Windows Terminal session as Administrator.

    .DESCRIPTION
        Opens an elevated window for the current shell and, when running inside
        Windows Terminal, reuses the same profile and working directory so the new
        window drops you back where you were - just elevated.

        Inside Windows Terminal the current profile (WT_PROFILE_ID) and directory
        are passed to wt.exe, which is relaunched with the RunAs verb to trigger
        the UAC prompt. Outside Windows Terminal it falls back to relaunching the
        current PowerShell host (pwsh or powershell) elevated in the same directory.

        Elevation always opens a NEW window: an elevated process cannot attach to a
        non-elevated Windows Terminal window, because the lower-integrity window is
        blocked by UIPI. The current session is left untouched unless -CloseCurrent
        is given.

    .PARAMETER CloseCurrent
        Exit the current (non-elevated) session after the elevated window has been
        launched. Inside Windows Terminal this closes the tab.

    .EXAMPLE
        Invoke-Elevation

        Opens a new elevated Windows Terminal window in the same profile and
        directory. The current tab stays open.

    .EXAMPLE
        Invoke-Elevation -CloseCurrent

        Opens the elevated window and then closes the current tab.

    .NOTES
        Author  : GenChadt
        Requires: Windows. No-op (with a message) if the session is already elevated.
        Cancelling the UAC prompt reports a warning instead of throwing.
    #>
    [CmdletBinding()]
    [Alias('el')]
    param(
        [switch] $CloseCurrent
    )

    if (Test-Elevation) {
        Write-Host 'Already running elevated.' -ForegroundColor DarkGray
        return
    }

    $inTerminal = [bool] $env:WT_SESSION
    $cwd = if ($PWD.ProviderPath) { $PWD.ProviderPath } else { $null }

    try {
        if ($inTerminal) {
            # wt.exe is a 0-byte app-execution alias under WindowsApps; resolve it so
            # the full path is passed to Start-Process (the alias is not always honoured).
            $wtCmd = Get-Command 'wt.exe' -ErrorAction SilentlyContinue
            $wtExe = if ($wtCmd) { $wtCmd.Source } else { 'wt.exe' }

            # Build the argument string with embedded quotes: Start-Process joins an
            # argument array with spaces without quoting, so -d/-p values containing
            # spaces would be split unless the quotes travel inside the string.
            $args = ''
            if ($env:WT_PROFILE_ID) {
                $args += '-p "' + $env:WT_PROFILE_ID + '" '
            }
            if ($cwd) {
                $args += '-d "' + $cwd + '"'
            }

            $process = Start-Process -FilePath $wtExe -Verb RunAs -ArgumentList $args -PassThru -ErrorAction Stop
        }
        else {
            $hostExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
            $startParams = @{
                FilePath    = $hostExe
                Verb        = 'RunAs'
                PassThru    = $true
                ErrorAction = 'Stop'
            }
            if ($cwd) { $startParams['WorkingDirectory'] = $cwd }

            $process = Start-Process @startParams
        }
    }
    catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223 -or $_.Exception.Message -match 'cancel') {
            Write-Warning 'Elevation cancelled (UAC prompt declined).'
            return
        }

        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $_.Exception,
            'ElevationLaunchFailed',
            [System.Management.Automation.ErrorCategory]::OpenError,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Write-Host "Elevated window launched (PID $($process.Id))." -ForegroundColor Green

    if ($CloseCurrent) {
        exit
    }
}
