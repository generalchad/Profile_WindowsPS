function Invoke-Unelevation {
    <#
    .SYNOPSIS
        Relaunches the current session unelevated, or runs a script block in a new
        non-elevated session.

    .DESCRIPTION
        Convenience wrapper over Invoke-Elevation -Unelevate, for elevating's
        opposite without typing the flag. It only does anything from an elevated
        session: a normal session is already unelevated and is left untouched.

        Inside Windows Terminal the same profile and working directory are reused;
        outside it a new non-elevated PowerShell host is opened. A -ScriptBlock runs
        in the new session instead of opening a bare shell.

    .PARAMETER ScriptBlock
        A command to run in the new non-elevated session. The block carries literal
        text only; variables and $PWD are re-evaluated in the new process.

    .PARAMETER CloseCurrent
        Exit the current (elevated) session after the new window has been launched.
        Alias: -x. The bare positional literal x is also accepted.

    .PARAMETER Close
        Positional shorthand: pass the literal x (Invoke-Unelevation x) to close the
        current session after launching.

    .EXAMPLE
        Invoke-Unelevation

        Opens a new non-elevated Windows Terminal window, dropping out of the
        elevated session.

    .EXAMPLE
        Invoke-Unelevation x

        Opens the non-elevated window and closes the current elevated tab.

    .EXAMPLE
        Invoke-Unelevation { git config --global core.autocrlf true }

        Runs the block in a new non-elevated session.

    .NOTES
        Author  : Timothy W. Brown
        Requires: Windows. Alias: uel.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Session')]
    [Alias('uel')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Run')]
        [scriptblock] $ScriptBlock,

        [Parameter(Position = 0, ParameterSetName = 'Session')]
        [ValidateSet('x')]
        [string] $Close,

        [Alias('x')]
        [Parameter(ParameterSetName = 'Session')]
        [Parameter(ParameterSetName = 'Run')]
        [switch] $CloseCurrent
    )

    $invokeParams = @{ Unelevate = $true }
    if ($PSBoundParameters.ContainsKey('ScriptBlock')) { $invokeParams['ScriptBlock'] = $ScriptBlock }
    if ($CloseCurrent -or $Close -eq 'x') { $invokeParams['CloseCurrent'] = $true }

    Invoke-Elevation @invokeParams
}
