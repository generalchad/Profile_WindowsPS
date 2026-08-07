function Test-Elevation {
    <#
    .SYNOPSIS
        Returns $true when the current session is running elevated (Administrator).

    .DESCRIPTION
        Uses the Windows principal of the current identity. On non-Windows platforms
        (where this module has nothing useful to do anyway) it returns $false.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
        return $false
    }

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        Write-Verbose "Elevation check failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-ElevationHint {
    <#
    .SYNOPSIS
        Builds a copy/paste-ready command that relaunches the current host elevated.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $hostExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    "Start-Process $hostExe -Verb RunAs"
}

function Test-InteractiveHost {
    <#
    .SYNOPSIS
        Returns $true when the host can support the interactive review screen.

    .DESCRIPTION
        The review screen reads a line at a time from the console and redraws a
        table. That is meaningless in a scheduled task, a remoting runspace or any
        host without a raw UI, and attempting it there would either throw or block
        forever waiting on input nobody can supply.

        Detection is deliberately conservative: anything that cannot be positively
        identified as an interactive console is treated as non-interactive, so the
        caller falls back to the plain consolidated prompt.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # -NonInteractive on the host process, or a redirected stdin, rules it out.
    try {
        if ([Console]::IsInputRedirected) { return $false }
    }
    catch {
        # Some hosts have no Console at all.
        return $false
    }

    if (-not $Host -or -not $Host.UI) { return $false }

    try {
        $null = $Host.UI.RawUI.WindowSize
    }
    catch {
        return $false
    }

    # Environment.UserInteractive is false for services and most scheduled tasks.
    try {
        if (-not [Environment]::UserInteractive) { return $false }
    }
    catch {
        return $false
    }

    return $true
}
