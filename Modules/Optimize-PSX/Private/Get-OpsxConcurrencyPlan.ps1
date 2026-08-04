function Get-OpsxConcurrencyPlan {
    <#
    .SYNOPSIS
        Derives a concurrency plan from a CPU budget and the storage type.
    .DESCRIPTION
        Converts a percentage of the host's logical processors into a total
        thread budget, then divides that budget between the two available
        dials: threads inside each chdman process (--numprocessors) and the
        number of chdman processes running at once.

            Budget      = ceil(LogicalCores * CpuBudget / 100)
            Concurrency = min(MaxDerived, max(1, floor(Budget / ThreadsPerJob)))

        The product of Concurrency and ThreadsPerJob never exceeds the budget,
        so the remaining logical processors stay available to the rest of the
        system.

        Derived concurrency is capped at MaxDerivedConcurrency. Beyond that
        point every additional process is streaming another multi-gigabyte image
        and the storage queue, not the CPU, becomes the limit. Budget left over
        after the cap is spent on threads-per-job instead, up to the point where
        chdman stops benefiting from them.


        Explicit -MaxConcurrency or -ThreadsPerJob values override the derived
        figures. When both are supplied the budget is not enforced, on the
        basis that an explicit request is deliberate.

        When the target volume reports rotational media, concurrency is clamped
        to one. Concurrent sequential reads on a single spindle cause head
        contention that makes a parallel batch slower than a serial one.
    .PARAMETER CpuBudget
        Percentage of logical processors to occupy, 1-100.
    .PARAMETER MaxConcurrency
        Explicit process count. Zero means derive from the budget.
    .PARAMETER ThreadsPerJob
        Explicit --numprocessors value. Zero means derive from the budget.
    .PARAMETER TargetPath
        A path on the volume holding the images, used for media type detection.
    .PARAMETER IgnoreDiskType
        Skip media type detection and apply the derived concurrency regardless.
    .PARAMETER Sequential
        Force a single process, using the whole budget for its worker threads.
    .OUTPUTS
        PSCustomObject:
          LogicalCores   host logical processor count
          Budget         total worker threads permitted
          Concurrency    simultaneous chdman processes
          ThreadsPerJob  --numprocessors value for each process
          ThreadsUsed    Concurrency * ThreadsPerJob
          CoresFree      LogicalCores - ThreadsUsed
          MediaType      detected media type, or 'Unknown'
          ClampedByDisk  whether rotational media reduced concurrency
          Rationale      human readable explanation for the summary
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [ValidateRange(1, 100)]
        [int]$CpuBudget = 50,

        [ValidateRange(0, 64)]
        [int]$MaxConcurrency = 0,

        [ValidateRange(0, 64)]
        [int]$ThreadsPerJob = 0,

        [string]$TargetPath,

        [switch]$IgnoreDiskType,

        [switch]$Sequential
    )

    $logicalCores = [Environment]::ProcessorCount
    $budget = [Math]::Max(1, [Math]::Ceiling($logicalCores * ($CpuBudget / 100.0)))

    if ($Sequential) {
        $threads = if ($ThreadsPerJob -gt 0) {
            [Math]::Min($ThreadsPerJob, $script:MaxUsefulThreadsPerJob)
        } else {
            [Math]::Min($budget, $script:MaxUsefulThreadsPerJob)
        }

        return [pscustomobject]@{
            PSTypeName    = 'Optimize-PSX.ConcurrencyPlan'
            LogicalCores  = $logicalCores
            Budget        = $budget
            Concurrency   = 1
            ThreadsPerJob = [int]$threads
            ThreadsUsed   = [int]$threads
            CoresFree     = $logicalCores - [int]$threads
            MediaType     = 'NotChecked'
            ClampedByDisk = $false
            Rationale     = "Sequential mode: 1 job x $threads thread(s)."
        }
    }

    # Threads per job are capped because chdman's internal scaling flattens
    # beyond this point; surplus budget is better spent on more processes.
    $threads = if ($ThreadsPerJob -gt 0) {
        [Math]::Min($ThreadsPerJob, $script:MaxUsefulThreadsPerJob)
    } else {
        [Math]::Min([Math]::Max(1, $script:DefaultThreadsPerJob), [Math]::Min($budget, $script:MaxUsefulThreadsPerJob))
    }

    $cappedByPolicy = $false

    if ($MaxConcurrency -gt 0) {
        $concurrency = $MaxConcurrency
    } else {
        $derived = [Math]::Max(1, [Math]::Floor($budget / $threads))
        $concurrency = [Math]::Min($derived, $script:MaxDerivedConcurrency)
        $cappedByPolicy = ($derived -gt $concurrency)

        # Budget freed by the cap goes into worker threads, up to the point
        # where chdman stops making use of them. Anything still left over is
        # deliberately not spent: a batch job has no business occupying the
        # whole machine just because the arithmetic permits it.
        if ($cappedByPolicy -and $ThreadsPerJob -eq 0) {
            $threads = [Math]::Min(
                $script:MaxUsefulThreadsPerJob,
                [Math]::Max($threads, [Math]::Floor($budget / $concurrency))
            )
        }
    }


    # --- Rotational media detection -------------------------------------
    $mediaType = 'Unknown'
    $clamped = $false

    if (-not $IgnoreDiskType -and $TargetPath) {
        $mediaType = Get-OpsxMediaType -Path $TargetPath
        if ($mediaType -eq 'HDD' -and $concurrency -gt 1) {
            $concurrency = 1
            $threads = [Math]::Min($budget, $script:MaxUsefulThreadsPerJob)
            $clamped = $true
        }
    }

    $threadsUsed = $concurrency * $threads

    $rationale = if ($clamped) {
        "Rotational media detected: clamped to 1 job x $threads thread(s) to avoid head contention. Use -IgnoreDiskType to override."
    } else {
        $base = "$CpuBudget% of $logicalCores logical cores = $budget thread budget: $concurrency job(s) x $threads thread(s) = $threadsUsed threads, $($logicalCores - $threadsUsed) left free."
        if ($cappedByPolicy) {
            "$base Concurrency capped at $($script:MaxDerivedConcurrency) to avoid saturating storage; use -MaxConcurrency to override."
        } else {
            $base
        }
    }


    [pscustomobject]@{
        PSTypeName    = 'Optimize-PSX.ConcurrencyPlan'
        LogicalCores  = $logicalCores
        Budget        = [int]$budget
        Concurrency   = [int]$concurrency
        ThreadsPerJob = [int]$threads
        ThreadsUsed   = [int]$threadsUsed
        CoresFree     = [int]($logicalCores - $threadsUsed)
        MediaType     = $mediaType
        ClampedByDisk = $clamped
        Rationale     = $rationale
    }
}
