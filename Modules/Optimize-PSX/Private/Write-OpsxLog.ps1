function Write-OpsxLog {
    <#
    .SYNOPSIS
        Console and file logging sink for the module.
    .DESCRIPTION
        Verbosity gating is centralised here, so call sites simply state a
        message and its level.

          Minimal  phase headers, warnings, errors, successes and the summary
          Normal   the above plus per-item informational output
          Detailed the above plus command lines, cue analysis and timings

        The log path and verbosity are read from script scope, established once
        per run by Initialize-OpsxLog.

        The file sink records every message regardless of console verbosity. If
        writing fails the sink is disabled and the run continues, since losing
        the log is preferable to aborting a long conversion batch.
    .PARAMETER Message
        Text to emit.
    .PARAMETER Level
        Severity, controlling colour and gating.
    .PARAMETER ForegroundColor
        Overrides the default colour for Info messages.
    .PARAMETER Phase
        Marks the message as a phase header so it survives -Verbosity Minimal.
    .PARAMETER NoConsole
        Write to the log file only.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Detail')]
        [string]$Level = 'Info',

        [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::Gray,

        [switch]$Phase,

        [switch]$NoConsole
    )

    $verbosity = if ($script:OpsxVerbosity) { $script:OpsxVerbosity } else { 'Normal' }

    $showOnConsole = -not $NoConsole
    if ($showOnConsole) {
        switch ($Level) {
            'Detail' { $showOnConsole = ($verbosity -eq 'Detailed') }
            'Info'   { $showOnConsole = ($verbosity -ne 'Minimal') -or $Phase }
            default  { $showOnConsole = $true }
        }
    }

    if ($showOnConsole) {
        $colour = switch ($Level) {
            'Warning' { [System.ConsoleColor]::Yellow }
            'Error'   { [System.ConsoleColor]::Red }
            'Success' { [System.ConsoleColor]::Green }
            'Detail'  { [System.ConsoleColor]::DarkGray }
            default   { if ($Phase) { [System.ConsoleColor]::Cyan } else { $ForegroundColor } }
        }
        Write-Host $Message -ForegroundColor $colour
    }

    if ($script:OpsxLogFile) {
        try {
            $stamp = [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
            Add-Content -LiteralPath $script:OpsxLogFile -Value "[$stamp] [$($Level.ToUpper())] $Message" -ErrorAction Stop
        } catch {
            $script:OpsxLogFile = $null
            Write-Host "Logging disabled - could not write to log file: $_" -ForegroundColor Red
        }
    }
}
