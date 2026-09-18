function Invoke-FFmpegJob {
    <#
    .SYNOPSIS
        Runs a single ffmpeg encode as a child process with a controlled
        priority class, waits for completion, and returns a result object.

    .DESCRIPTION
        Internal helper. Not exported. Uses System.Diagnostics.Process
        with ProcessStartInfo.ArgumentList rather than Start-Process: the
        ArgumentList collection quotes each argument per the platform
        rules, so paths with spaces survive intact (Start-Process joins an
        array with unquoted spaces, truncating them at the first space).
        PriorityClass is set right after launch - this keeps compression
        from starving the interactive session's CPU/GPU scheduling, per the
        module's "never saturate the PC" design goal.

    .PARAMETER Priority
        One of Idle, BelowNormal, Normal. Applied via
        System.Diagnostics.Process.PriorityClass.

    .PARAMETER Tolerance
        Fractional duration tolerance passed to the pre-delete verification.

    .PARAMETER FullVerify
        In addition to the duration check, require a full error-free decode
        of the output before the source is deleted. Only consulted when
        -DeleteSource is set.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$InputFile,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string[]]$FFmpegArgs,

        [Parameter()]
        [ValidateSet('Idle', 'BelowNormal', 'Normal')]
        [string]$Priority = 'BelowNormal',

        [Parameter()]
        [double]$Tolerance = 0.01,

        [Parameter()]
        [switch]$FullVerify,

        [switch]$DeleteSource
    )

    process {
        $stdErrPath = [System.IO.Path]::GetTempFileName()
        $proc = $null
        $errFile = $null

        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = 'ffmpeg'
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardError = $true
            foreach ($arg in $FFmpegArgs) { $psi.ArgumentList.Add($arg) }

            $proc = [System.Diagnostics.Process]::new()
            $proc.StartInfo = $psi
            $null = $proc.Start()

            # Drain stderr to the temp file asynchronously. A redirected pipe
            # fills and blocks the child once its buffer is full, so the stream
            # must be consumed while the process runs rather than after.
            $errStream = $proc.StandardError.BaseStream
            $errFile = [System.IO.File]::Open($stdErrPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            $errTask = $errStream.CopyToAsync($errFile)

            try {
                $priorityMap = @{
                    'Idle'        = [System.Diagnostics.ProcessPriorityClass]::Idle
                    'BelowNormal' = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
                    'Normal'      = [System.Diagnostics.ProcessPriorityClass]::Normal
                }
                $proc.PriorityClass = $priorityMap[$Priority]
            } catch {
                Write-Verbose "Could not set process priority: $_"
            }

            $proc.WaitForExit()
            $exitCode = $proc.ExitCode
            # GetResult() on a Task<VoidTaskResult> emits the result struct to
            # the pipeline, so it must be discarded or it corrupts the return.
            $null = $errTask.GetAwaiter().GetResult()
            $errFile.Dispose()
            $errFile = $null

            if ($exitCode -eq 0) {
                $outputItem = Get-Item $OutputPath -ErrorAction SilentlyContinue

                $deletedSource = $false
                $verifyReason  = $null

                if ($DeleteSource) {
                    if ($outputItem -and $outputItem.Length -gt 0) {
                        $durationCheck = Test-CompressedOutput -InputPath $InputFile.FullName -OutputPath $OutputPath -Tolerance $Tolerance -Strict

                        if ($durationCheck.Status -ne 'Complete') {
                            $verifyReason = $durationCheck.Reason
                        } elseif ($FullVerify -and -not (Test-OutputIntegrity -Path $OutputPath)) {
                            $verifyReason = 'Full decode verification failed: output decodes with errors'
                        } else {
                            Remove-Item $InputFile.FullName -Force
                            $deletedSource = $true
                            Write-Verbose "Deleted source: $($InputFile.FullName)"
                        }
                    } else {
                        $verifyReason = 'Output file is missing or empty'
                    }
                }

                return [PSCustomObject]@{
                    Success       = $true
                    InputFile     = $InputFile
                    OutputFile    = $outputItem
                    DeletedSource = $deletedSource
                    VerifyReason  = $verifyReason
                    Error         = $null
                }
            } else {
                # Only the tail matters: the banner/version/config preamble is
                # noise. The last lines carry the actual failure reason.
                $stderrLines = if (Test-Path $stdErrPath) { Get-Content $stdErrPath -ErrorAction SilentlyContinue } else { @() }
                $stderrTail = ($stderrLines | Select-Object -Last 30) -join "`n"
                throw "FFmpeg exited with code $exitCode. $stderrTail"
            }
        }
        catch {
            return [PSCustomObject]@{
                Success       = $false
                InputFile     = $InputFile
                OutputFile    = $null
                DeletedSource = $false
                VerifyReason  = $null
                Error         = $_
            }
        }
        finally {
            if ($errFile) { $errFile.Dispose() }
            if ($proc) { $proc.Dispose() }
            if ($stdErrPath -and (Test-Path $stdErrPath)) {
                Remove-Item $stdErrPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
