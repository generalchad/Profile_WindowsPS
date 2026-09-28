function Invoke-Elevation {
    <#
    .SYNOPSIS
        Relaunches the current Windows Terminal session elevated or unelevated, or
        runs a script block in a new elevated/unelevated session.

    .DESCRIPTION
        Without a script block, opens a new window for the current shell. By default
        the window is elevated; with -Unelevate it is a normal, non-elevated session.
        When running inside Windows Terminal the same profile and working directory
        are reused so the new window drops you back where you were.

        With a -ScriptBlock, serializes the block to text and re-runs it inside the
        new session instead of opening a bare interactive shell. Because a PowerShell
        pipeline cannot cross a process boundary, the block is passed as an
        -EncodedCommand (base64) on the target's command line.

        Elevation uses the RunAs verb (UAC prompt) and always opens a NEW window: an
        elevated process cannot attach to a non-elevated Windows Terminal window,
        because the lower-integrity window is blocked by UIPI. De-elevation launches
        through the session's filtered (non-elevated) token, so the new window is a
        normal non-elevated shell that can itself elevate again later.

        The current session is left untouched unless -CloseCurrent is given.

    .PARAMETER ScriptBlock
        A command to run in the new session. The block carries literal text only:
        variables and $PWD are re-evaluated in the new process, so use literal
        values. The new window stays open after the block finishes.

    .PARAMETER Unelevate
        Open (or run the block in) a non-elevated session instead of an elevated
        one. Only meaningful from an elevated session; from a normal session it
        reports that the session is already unelevated. Alias: -u. Also accepted as
        the bare positional token u.

    .PARAMETER CloseCurrent
        Exit the current session after the new window has been launched. Inside
        Windows Terminal this closes the tab. Alias: -x.

    .PARAMETER Flag
        First positional shorthand token: pass u, x or both literals
        (Invoke-Elevation u, Invoke-Elevation u x, Invoke-Elevation x) to select
        -Unelevate and/or -CloseCurrent. -Close is kept as an alias for -Flag.

    .PARAMETER Flag2
        Second positional shorthand token; combined with -Flag. Same values.

    .EXAMPLE
        Invoke-Elevation

        Opens a new elevated Windows Terminal window in the same profile and
        directory. The current tab stays open.

    .EXAMPLE
        Invoke-Elevation u

        De-elevates: opens a new non-elevated Windows Terminal window. Requires an
        elevated session.

    .EXAMPLE
        Invoke-Elevation u x

        De-elevates into a new window and then closes the current (elevated) tab.

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

    .EXAMPLE
        Invoke-Elevation -Unelevate { Set-ExecutionPolicy -Scope CurrentUser RemoteSigned }

        Runs the block in a new non-elevated session.

    .NOTES
        Author  : Timothy W. Brown
        Requires: Windows. No-op (with a message) when the session is already at the
        requested elevation level. Cancelling the UAC prompt reports a warning
        instead of throwing.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Elevate')]
    [Alias('el', 'isudo', 'elevate')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Run')]
        [scriptblock] $ScriptBlock,

        [Parameter(Position = 0, ParameterSetName = 'Elevate')]
        [ValidateSet('x', 'u')]
        [Alias('Close')]
        [string] $Flag,

        [Parameter(Position = 1, ParameterSetName = 'Elevate')]
        [ValidateSet('x', 'u')]
        [string] $Flag2,

        [Alias('x')]
        [Parameter(ParameterSetName = 'Elevate')]
        [Parameter(ParameterSetName = 'Run')]
        [switch] $CloseCurrent,

        [Alias('u')]
        [Parameter(ParameterSetName = 'Elevate')]
        [Parameter(ParameterSetName = 'Run')]
        [switch] $Unelevate
    )

    $flags = @($Flag, $Flag2) | Where-Object { $_ }
    $unelevate = $Unelevate -or ($flags -contains 'u')
    $closeCurrent = $CloseCurrent -or ($flags -contains 'x')

    if ($unelevate) {
        if (-not (Test-Elevation)) {
            Write-Host 'Already running unelevated.' -ForegroundColor DarkGray
            return
        }
    }
    elseif (Test-Elevation) {
        Write-Host 'Already running elevated.' -ForegroundColor DarkGray
        return
    }

    $inTerminal = [bool] $env:WT_SESSION
    $cwd = if ($PWD.ProviderPath) { $PWD.ProviderPath } else { $null }
    $hostExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    $hostPath = Join-Path $PSHOME ($hostExe + '.exe')

    $launchArgs = ''
    if ($PSCmdlet.ParameterSetName -eq 'Run') {
        # Encode the block as base64 UTF-16LE for -EncodedCommand: base64 holds no
        # spaces or quotes, so it survives the process chain untouched. The new
        # session must load the profile (no -NoProfile) so $env:PSModulePath includes
        # Modules/, otherwise repo modules like New-ScanShare would not autoload there.
        $command = $ScriptBlock.ToString().Trim()
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
        $launchArgs = "-NoLogo -NoExit -EncodedCommand $encoded"
    }

    if ($inTerminal) {
        # wt.exe is a 0-byte app-execution alias under WindowsApps; resolve it so
        # the full path is passed to the launcher (the alias is not always honoured).
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
    }

    try {
        if ($unelevate) {
            # De-elevate through a filtered (non-elevated) token: it is a genuine
            # non-elevated token, so the child can elevate again. runas /trustlevel
            # builds a SAFER restricted token that cannot re-elevate, so it is only
            # kept as a fallback when no filtered token can be obtained (UAC off).
            $target = if ($inTerminal) { '"' + $wtExe + '" ' + $wtArgs } else { $hostExe + ' ' + $launchArgs }
            $target = $target.Trim()
            $filePath = if ($inTerminal) { $wtExe } else { $hostPath }

            $launchedPid = Start-LimitedProcess -FilePath $filePath -CommandLine $target -WorkingDirectory $cwd

            if ($null -eq $launchedPid) {
                # Inner quotes in the target command must be escaped as \" so the
                # whole command survives as a single runas argument; -WindowStyle
                # Hidden hides runas itself, not the session it launches.
                $runasArgs = '/trustlevel:0x20000 "' + ($target -replace '"', '\"') + '"'

                $startParams = @{
                    FilePath     = 'runas.exe'
                    ArgumentList = $runasArgs
                    WindowStyle  = 'Hidden'
                    PassThru     = $true
                    ErrorAction  = 'Stop'
                }
                if ($cwd) { $startParams['WorkingDirectory'] = $cwd }

                $launchedPid = (Start-Process @startParams).Id
            }
        }
        elseif ($inTerminal) {
            $launchedPid = (Start-Process -FilePath $wtExe -Verb RunAs -ArgumentList $wtArgs -PassThru -ErrorAction Stop).Id
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

            $launchedPid = (Start-Process @startParams).Id
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

    $mode = if ($unelevate) { 'Unelevated' } else { 'Elevated' }
    Write-Host "$mode window launched (PID $launchedPid)." -ForegroundColor Green

    if ($closeCurrent) {
        exit
    }
}
