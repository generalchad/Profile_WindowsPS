function Initialize-OpsxLog {
    <#
    .SYNOPSIS
        Sets the module-wide logging state for a single Optimize-PSX run.
    .DESCRIPTION
        Establishes $script:OpsxLogFile and $script:OpsxVerbosity, creating the
        log directory and truncating any previous log. Failure to create the
        log is non-fatal: the run continues with console output only, because
        refusing to convert anything over a logging problem would be absurd.
    .PARAMETER LogFile
        Destination log path. Omit for console-only output.
    .PARAMETER Verbosity
        Console verbosity for this run.
    .PARAMETER Version
        Module version, recorded in the log header.
    .OUTPUTS
        None. Sets script scope state.
    #>
    [CmdletBinding()]
    param (
        [AllowEmptyString()]
        [string]$LogFile,

        [ValidateSet('Minimal', 'Normal', 'Detailed')]
        [string]$Verbosity = 'Normal',

        [string]$Version = '2.0.0'
    )

    $script:OpsxVerbosity = $Verbosity
    $script:OpsxLogFile = $null

    if ([string]::IsNullOrWhiteSpace($LogFile)) { return }

    try {
        # Resolve to an absolute path before touching anything: a relative log
        # path would otherwise land wherever the process happens to be, and the
        # conversion phase deliberately changes the working directory.
        $resolved = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::Combine($PWD.ProviderPath, $LogFile)
        )

        $folder = [System.IO.Path]::GetDirectoryName($resolved)
        if ($folder -and -not [System.IO.Directory]::Exists($folder)) {
            $null = New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop
        }

        $stamp = [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
        Set-Content -LiteralPath $resolved -Value "[$stamp] Optimize-PSX v$Version log started" -Force -ErrorAction Stop

        $script:OpsxLogFile = $resolved
    } catch {
        Write-Warning "Could not initialise log file '$LogFile': $($_.Exception.Message). Continuing without a log."
        $script:OpsxLogFile = $null
    }
}
