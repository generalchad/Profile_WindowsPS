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
        $proc = $null

        try {
            # .ArgumentList (not Start-Process -ArgumentList) so paths with
            # spaces are quoted per platform rules instead of being split.
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = 'ffmpeg'
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            foreach ($arg in @('-v', 'error', '-xerror', '-i', $Path, '-f', 'null', '-')) {
                $psi.ArgumentList.Add($arg)
            }

            $proc = [System.Diagnostics.Process]::new()
            $proc.StartInfo = $psi
            $null = $proc.Start()

            $errStream = $proc.StandardError.BaseStream
            $outStream = $proc.StandardOutput.BaseStream
            $errFile = [System.IO.File]::Open($stdErrPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            $outFile = [System.IO.File]::Open($stdOutPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            $errTask = $errStream.CopyToAsync($errFile)
            $outTask = $outStream.CopyToAsync($outFile)

            try {
                $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
            } catch {
                Write-Verbose "Could not set verify process priority: $_"
            }

            $proc.WaitForExit()
            $exitCode = $proc.ExitCode
            $null = $errTask.GetAwaiter().GetResult()
            $null = $outTask.GetAwaiter().GetResult()
            $errFile.Dispose()
            $outFile.Dispose()

            return ($exitCode -eq 0)
        } catch {
            Write-Verbose "Integrity verification failed: $_"
            return $false
        } finally {
            if ($proc) { $proc.Dispose() }
            foreach ($tmp in @($stdErrPath, $stdOutPath)) {
                if ($tmp -and (Test-Path -LiteralPath $tmp)) {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
