function Complete-ChdmanProcess {
    <#
    .SYNOPSIS
        Finalises an exited chdman process and records the outcome on its job.
    .DESCRIPTION
        Waits for the process to exit and for its stream pumps to reach end of
        stream, drains any remaining output, then decides success from three
        conditions taken together: a zero exit code, an existing temporary
        output, and a non-zero output length.

        Exit code alone is insufficient, as an aborted write can still exit
        cleanly. A zero-length output is treated as failure.

        On success the temporary file is moved onto the final path, replacing an
        existing CHD only at that point. The move is the last operation, so the
        final name never exists in a partial state.

        On failure the temporary file is removed and the tail of chdman's output
        is recorded as the error.
    .PARAMETER Worker
        Worker record from Start-ChdmanProcess.
    .OUTPUTS
        None. Mutates the job record held by the worker.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [hashtable]$Worker
    )

    $job = $Worker.Job
    $process = $Worker.Process

    try { $process.WaitForExit() } catch { }

    # Process exit and pipe drain are separate events: the last lines written
    # can still be in flight inside the pump when the process object reports
    # exited. Waiting for both tasks guarantees the closing summary, and with it
    # the compression ratio, is in the queue before it is read.
    #
    # Bounded, because a pump blocked on a pipe that never closes must not hang
    # the batch. Losing the tail of the log is a far smaller cost than a stall.
    try {
        $pumps = @($Worker.OutTask, $Worker.ErrTask) | Where-Object { $null -ne $_ }
        if ($pumps.Count -gt 0) {
            $null = [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$pumps, 5000)
        }
    } catch {
        Write-OpsxLog "Output readers for '$($job.Name)' did not finish cleanly: $($_.Exception.Message)" -Level Detail
    }

    $null = Update-ChdmanProgress -Worker $Worker

    $job.ExitCode = $process.ExitCode
    $job.Duration = [datetime]::Now - $Worker.StartTime
    $job.Slot = $Worker.Slot

    $tempExists = [System.IO.File]::Exists($job.TempPath)
    $tempLength = if ($tempExists) { [System.IO.FileInfo]::new($job.TempPath).Length } else { 0 }

    try {
        if ($process.ExitCode -eq 0 -and $tempExists -and $tempLength -gt 0) {
            [System.IO.File]::Move($job.TempPath, $job.OutputPath, $true)

            $job.OutputBytes = [System.IO.FileInfo]::new($job.OutputPath).Length
            $job.Status = 'Converted'

            $job.Ratio = if ($null -ne $Worker.LastRatio) {
                [Math]::Round($Worker.LastRatio, 2)
            } elseif ($job.SourceBytes -gt 0) {
                [Math]::Round(($job.OutputBytes / $job.SourceBytes) * 100, 2)
            } else {
                $null
            }
        } else {
            $job.Status = 'Failed'

            $tail = ($Worker.Lines | Select-Object -Last 4) -join ' | '
            $job.Error = if ($process.ExitCode -ne 0) {
                "chdman exited with code $($process.ExitCode). $tail".Trim()
            } elseif (-not $tempExists) {
                "chdman reported success but produced no output file. $tail".Trim()
            } else {
                "chdman produced a zero-length output file. $tail".Trim()
            }

            Remove-OpsxTempFile -Path $job.TempPath
        }
    } catch {
        $job.Status = 'Failed'
        $job.Error = "Could not finalise output: $($_.Exception.Message)"
        Remove-OpsxTempFile -Path $job.TempPath
    } finally {
        $process.Dispose()
    }
}
