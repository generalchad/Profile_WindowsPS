function Invoke-Elevation {
    <#
    .SYNOPSIS
        Relaunches the current Windows Terminal session as Administrator, or runs a
        script block in a new elevated session.

    .DESCRIPTION
        Without a script block, opens an elevated window for the current shell and,
        when running inside Windows Terminal, reuses the same profile and working
        directory so the new window drops you back where you were - just elevated.

        With a -ScriptBlock, serializes the block to text and re-runs it inside the
        elevated session instead of opening a bare interactive shell. Because a
        PowerShell pipeline cannot cross a process boundary, the block is passed as
        an -EncodedCommand (base64) on the target's command line.

        Inside Windows Terminal the current profile (WT_PROFILE_ID) and directory
        are passed to wt.exe, which is relaunched with the RunAs verb to trigger
        the UAC prompt. Outside Windows Terminal it falls back to relaunching the
        current PowerShell host (pwsh or powershell) elevated in the same directory.

        Elevation always opens a NEW window: an elevated process cannot attach to a
        non-elevated Windows Terminal window, because the lower-integrity window is
        blocked by UIPI. The current session is left untouched unless -CloseCurrent
        is given.

    .PARAMETER ScriptBlock
        A command to run in the elevated session. The block carries literal text
        only: variables and $PWD are re-evaluated in the new process, so use literal
        values. The elevated tab stays open after the block finishes.

    .PARAMETER CloseCurrent
        Exit the current (non-elevated) session after the elevated window has been
        launched. Inside Windows Terminal this closes the tab. Alias: -x.

    .PARAMETER Close
        Shorthand for -CloseCurrent as a positional value: pass the literal x
        (e.g. Invoke-Elevation x) to close the current tab after launching.

    .EXAMPLE
        Invoke-Elevation

        Opens a new elevated Windows Terminal window in the same profile and
        directory. The current tab stays open.

    .EXAMPLE
        Invoke-Elevation -CloseCurrent

        Opens the elevated window and then closes the current tab.

    .EXAMPLE
        Invoke-Elevation x

        Same as -CloseCurrent, using the bare positional shorthand.

    .EXAMPLE
        Invoke-Elevation { New-ScanShare -Path C:\Scans -ShareName Scans }

        Runs New-ScanShare in a new elevated Windows Terminal tab, which stays open
        so its prompts and output are usable.

    .NOTES
        Author  : GenChadt
        Requires: Windows. No-op (with a message) if the session is already elevated.
        Cancelling the UAC prompt reports a warning instead of throwing.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Elevate')]
    [Alias('el', 'isudo', 'elevate')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Run')]
        [scriptblock] $ScriptBlock,

        [Parameter(Position = 0, ParameterSetName = 'Elevate')]
        [ValidateSet('x')]
        [string] $Close,

        [Alias('x')]
        [Parameter(ParameterSetName = 'Elevate')]
        [Parameter(ParameterSetName = 'Run')]
        [switch] $CloseCurrent
    )

    if (Test-Elevation) {
        Write-Host 'Already running elevated.' -ForegroundColor DarkGray
        return
    }

    $inTerminal = [bool] $env:WT_SESSION
    $cwd = if ($PWD.ProviderPath) { $PWD.ProviderPath } else { $null }
    $hostExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }

    $launchArgs = ''
    if ($PSCmdlet.ParameterSetName -eq 'Run') {
        # Encode the block as base64 UTF-16LE for -EncodedCommand: base64 holds no
        # spaces or quotes, so it survives the Start-Process -> wt.exe -> shell chain
        # untouched. The elevated session must load the profile (no -NoProfile) so
        # $env:PSModulePath includes Modules/, otherwise repo modules like
        # New-ScanShare would not autoload there.
        $command = $ScriptBlock.ToString().Trim()
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
        $launchArgs = "-NoLogo -NoExit -EncodedCommand $encoded"
    }

    try {
        if ($inTerminal) {
            # wt.exe is a 0-byte app-execution alias under WindowsApps; resolve it so
            # the full path is passed to Start-Process (the alias is not always honoured).
            $wtCmd = Get-Command 'wt.exe' -ErrorAction SilentlyContinue
            $wtExe = if ($wtCmd) { $wtCmd.Source } else { 'wt.exe' }

            # Build the argument string with embedded quotes: Start-Process joins an
            # argument array with spaces without quoting, so -d/-p values containing
            # spaces would be split unless the quotes travel inside the string.
            $wtArgs = ''
            if ($env:WT_PROFILE_ID) {
                $wtArgs += '-p "' + $env:WT_PROFILE_ID + '" '
            }
            if ($cwd) {
                $wtArgs += '-d "' + $cwd + '"'
            }
            if ($launchArgs) {
                # "--" ends wt's own option parsing so -NoLogo/-NoExit/-EncodedCommand
                # are handed to pwsh as the tab's commandline rather than wt's options.
                $wtArgs += " -- $hostExe $launchArgs"
            }

            $process = Start-Process -FilePath $wtExe -Verb RunAs -ArgumentList $wtArgs -PassThru -ErrorAction Stop
        }
        else {
            $startParams = @{
                FilePath    = $hostExe
                Verb        = 'RunAs'
                PassThru    = $true
                ErrorAction = 'Stop'
            }
            if ($cwd) { $startParams['WorkingDirectory'] = $cwd }
            if ($launchArgs) { $startParams['ArgumentList'] = $launchArgs }

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

    if ($CloseCurrent -or $Close -eq 'x') {
        exit
    }
}
