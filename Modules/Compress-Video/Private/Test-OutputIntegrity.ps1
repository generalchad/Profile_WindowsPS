function Test-OutputIntegrity {
    <#
    .SYNOPSIS
        Verifies a media file decodes cleanly end-to-end with no errors.

    .DESCRIPTION
        Internal helper. Not exported. Runs ffmpeg in null-mux decode mode
        with -xerror so that any decode error (corrupt/truncated stream)
        causes a non-zero exit. This is a full decode pass - no encoding, no
        disk writes - and is the strongest automated "is this output actually
        intact" check available. Launched at BelowNormal priority to match
        the module's never-saturate design goal.

    .OUTPUTS
        bool - $true only when the whole file decodes with zero errors.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    process {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }

        $stdErrPath = [System.IO.Path]::GetTempFileName()
        $stdOutPath = [System.IO.Path]::GetTempFileName()

        try {
            $startInfo = @{
                FilePath               = 'ffmpeg'
                ArgumentList           = @('-v', 'error', '-xerror', '-i', $Path, '-f', 'null', '-')
                NoNewWindow            = $true
                PassThru               = $true
                RedirectStandardError  = $stdErrPath
                RedirectStandardOutput = $stdOutPath
                Wait                   = $false
            }

            $proc = Start-Process @startInfo

            try {
                $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
            } catch {
                Write-Verbose "Could not set verify process priority: $_"
            }

            $proc.WaitForExit()
            return ($proc.ExitCode -eq 0)
        } catch {
            Write-Verbose "Integrity verification failed: $_"
            return $false
        } finally {
            foreach ($tmp in @($stdErrPath, $stdOutPath)) {
                if ($tmp -and (Test-Path -LiteralPath $tmp)) {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
