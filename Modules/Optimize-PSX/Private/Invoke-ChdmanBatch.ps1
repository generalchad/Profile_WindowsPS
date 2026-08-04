function Invoke-ChdmanBatch {
    <#
    .SYNOPSIS
        Runs a set of chdman conversions with bounded concurrency.
    .DESCRIPTION
        Maintains a fixed pool of worker slots, each holding one chdman process.
        A finished slot is refilled from the queue immediately, so the pool stays
        saturated until the queue drains.

        Processes are started with System.Diagnostics.Process rather than
        Start-Job or ForEach-Object -Parallel. There is no PowerShell runspace
        per job, so per-job overhead is a process handle and two stream readers,
        and progress can be read live from each process's stderr.

        Output streams are drained on background threads into thread-safe queues,
        which this pump polls. Reading synchronously here would block on whichever
        process happened to be quietest, and letting the streams fill without
        draining deadlocks the child once its pipe buffer is full.

        Each conversion writes to <output>.chd.tmp and is moved into place only
        after a zero exit code and a non-empty result. An interrupted or failed
        run therefore leaves no file that could be mistaken for a complete CHD.

        Progress is reported as one parent bar for the batch and one child bar
        per active slot, driven by the percentage chdman prints to stderr.

        The parent bar counts partially finished work, not just finished work:
        a single image at 60% reads as 60%, where counting completions alone
        would read as 0% for the whole run and then vanish.

        Each child bar carries elapsed time next to the percentage. chdman
        block-buffers stderr when it is redirected, so a percentage can be the
        newest one in existence and still be half a minute old; without a moving
        counter beside it, a healthy job is indistinguishable from a hung one.
        Start-ChdmanProcess documents the buffering in full.

        Ctrl+C is handled: the pump kills every live process, removes partial
        temporary files, and rethrows so the caller's own handling still runs.
    .PARAMETER Jobs
        Job records from Get-OpsxConversionPlan.
    .PARAMETER ChdmanPath
        Resolved path to the chdman executable.
    .PARAMETER Concurrency
        Maximum simultaneous chdman processes.
    .PARAMETER ThreadsPerJob
        Value passed to --numprocessors for each process.
    .PARAMETER Compression
        Explicit codec chain. Omit to use chdman's defaults.
    .PARAMETER Force
        Pass --force so chdman overwrites an existing output.
    .PARAMETER Cmdlet
        Calling $PSCmdlet, so ShouldProcess honours -WhatIf and -Confirm.
    .OUTPUTS
        The same job objects, with execution fields populated.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [pscustomobject[]]$Jobs,

        [Parameter(Mandatory)]
        [string]$ChdmanPath,

        [ValidateRange(1, 64)]
        [int]$Concurrency = 1,

        [ValidateRange(1, 64)]
        [int]$ThreadsPerJob = 2,

        [string[]]$Compression,

        [switch]$Force,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    if ($Jobs.Count -eq 0) { return }

    $queue = [System.Collections.Generic.Queue[pscustomobject]]::new()
    foreach ($job in $Jobs) {
        if ($Cmdlet.ShouldProcess($job.SourcePath, "Convert to CHD ($($job.Command))")) {
            $queue.Enqueue($job)
        } else {
            # Distinct from 'Skipped', which the planner assigns to images it
            # refused to queue. This job was viable; the caller said no, which
            # is also what -WhatIf looks like from here.
            $job.Status = 'Declined'
            $job.Reason = 'Declined by ShouldProcess.'

        }
    }

    if ($queue.Count -eq 0) { return $Jobs }

    $total = $queue.Count
    $completed = 0
    $active = [System.Collections.Generic.List[hashtable]]::new()
    $batchStart = [datetime]::Now

    try {
        while ($queue.Count -gt 0 -or $active.Count -gt 0) {

            # --- Fill idle slots ----------------------------------------
            while ($active.Count -lt $Concurrency -and $queue.Count -gt 0) {
                $job = $queue.Dequeue()

                # Slot indices are reused, so a finished slot's progress bar is
                # replaced rather than accumulating one bar per job.
                $slot = 0
                while ($active.Where({ $_.Slot -eq $slot }, 'First').Count -gt 0) { $slot++ }

                $worker = Start-ChdmanProcess -Job $job -ChdmanPath $ChdmanPath `
                                              -ThreadsPerJob $ThreadsPerJob -Compression $Compression `
                                              -Force:$Force -Slot $slot

                if ($worker) {
                    $active.Add($worker)
                    Write-OpsxLog "[slot $slot] Started $($job.Name)" -Level Detail
                } else {
                    $completed++
                }
            }

            if ($active.Count -eq 0) { continue }

            Start-Sleep -Milliseconds $script:PumpIntervalMs

            # --- Service active slots -----------------------------------
            for ($i = $active.Count - 1; $i -ge 0; $i--) {
                $worker = $active[$i]

                $status = Update-ChdmanProgress -Worker $worker

                if ($worker.Process.HasExited) {
                    Complete-ChdmanProcess -Worker $worker
                    Write-Progress -Id ($script:ChildProgressBase + $worker.Slot) -Activity 'chdman' -Completed

                    $job = $worker.Job
                    if ($job.Status -eq 'Converted') {
                        $ratioText = if ($null -ne $job.Ratio) { " ($($job.Ratio)% of source)" } else { '' }
                        Write-OpsxLog "Created $($job.Name -replace '\.[^.]+$', '.chd')$ratioText in $($job.Duration.ToString('mm\:ss'))" -Level Success
                    } else {
                        Write-OpsxLog "Failed $($job.Name): $($job.Error)" -Level Error
                    }

                    $active.RemoveAt($i)
                    $completed++
                } else {
                    # Elapsed time comes from the worker, not from the progress
                    # reading, so it advances on every poll even while chdman is
                    # silent. That movement is what distinguishes a working job
                    # from a stuck one, since the percentage cannot.
                    $jobElapsed = ([datetime]::Now - $worker.StartTime).ToString('mm\:ss')

                    if ($status) {
                        $statusText = "$($status.Text) [$jobElapsed]"

                        # chdman's own percentage is the only basis for a
                        # remaining-time figure, and it is only worth offering
                        # once there is enough of the job behind us for the rate
                        # to mean anything.
                        $secondsRemaining = -1
                        if ($status.Percent -ge 5 -and $status.Percent -lt 100) {
                            $rate = ([datetime]::Now - $worker.StartTime).TotalSeconds / $status.Percent
                            $secondsRemaining = [int][Math]::Round($rate * (100 - $status.Percent))
                        }

                        Write-Progress -Id ($script:ChildProgressBase + $worker.Slot) `
                                       -ParentId $script:ParentProgressId `
                                       -Activity "[$($worker.Slot)] $($worker.Job.Name)" `
                                       -Status $statusText `
                                       -PercentComplete $status.Percent `
                                       -SecondsRemaining $secondsRemaining
                    } else {
                        # Launched but not yet heard from. On a large image this
                        # silence lasts tens of seconds, so the slot is shown as
                        # occupied rather than left blank.
                        Write-Progress -Id ($script:ChildProgressBase + $worker.Slot) `
                                       -ParentId $script:ParentProgressId `
                                       -Activity "[$($worker.Slot)] $($worker.Job.Name)" `
                                       -Status "Starting [$jobElapsed]" `
                                       -PercentComplete 0
                    }
                }
            }

            # --- Parent bar ---------------------------------------------
            #
            # Fractional credit for work in flight. Without it a single-image
            # batch sits at 0% from start to finish, which is the common case and
            # the one where the bar is most useful.
            $inFlight = 0.0
            foreach ($worker in $active) { $inFlight += ($worker.LastPercent / 100.0) }
            $overall = [Math]::Min(100, (($completed + $inFlight) / $total) * 100)

            # ETA from completions once any exist, since a measured conversion
            # time is a far better predictor than extrapolating a partial one.
            # Before then the in-flight fraction is all there is to go on.
            $elapsed = [datetime]::Now - $batchStart
            $eta = if ($completed -gt 0) {
                $per = $elapsed.TotalSeconds / $completed
                [timespan]::FromSeconds($per * ($total - $completed)).ToString('hh\:mm\:ss')
            } elseif ($inFlight -gt 0.05) {
                $projected = $elapsed.TotalSeconds / $inFlight
                [timespan]::FromSeconds([Math]::Max(0, $projected * ($total - $inFlight))).ToString('hh\:mm\:ss')
            } else {
                'estimating'
            }

            Write-Progress -Id $script:ParentProgressId -Activity 'Converting images to CHD' `
                           -Status "$completed of $total complete, $($active.Count) running, ETA $eta" `
                           -PercentComplete $overall
        }
    } finally {
        # Runs on Ctrl+C as well as normal completion, so no orphaned chdman
        # process survives the pipeline and no partial .chd.tmp is left behind.
        #
        # Every step is guarded individually: this is the teardown path, and one
        # worker that refuses to die must not prevent the rest from being cleaned
        # up. Killing the process closes its pipes, which ends the stream pumps
        # on their own, so they need no separate cancellation.
        foreach ($worker in $active) {
            try {
                if (-not $worker.Process.HasExited) {
                    $worker.Process.Kill($true)
                    $worker.Job.Status = 'Cancelled'
                    $worker.Job.Error = 'Cancelled before completion.'
                }
            } catch {
                Write-OpsxLog "Could not terminate chdman for '$($worker.Job.Name)': $($_.Exception.Message)" -Level Detail
            }

            # Complete-ChdmanProcess disposes the processes it finalises; these
            # workers never reached it, so their handles are released here.
            try { $worker.Process.Dispose() } catch { }

            Remove-OpsxTempFile -Path $worker.Job.TempPath
            Write-Progress -Id ($script:ChildProgressBase + $worker.Slot) -Activity 'chdman' -Completed
        }

        Write-Progress -Id $script:ParentProgressId -Activity 'Converting images to CHD' -Completed
    }

    return $Jobs
}
