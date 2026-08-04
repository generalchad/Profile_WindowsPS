function Start-ChdmanProcess {
    <#
    .SYNOPSIS
        Launches one chdman conversion and returns a worker record.
    .DESCRIPTION
        Builds the argument list, starts the process with both output streams
        redirected, and hands each stream to the compiled pump in _StreamPump.ps1,
        which drains it into a thread-safe queue.

        Draining is mandatory rather than optional: a child process blocks once
        its redirected pipe buffer fills, so an undrained stream stalls the
        conversion permanently.

        The pump is compiled C# rather than a PowerShell script block. A script
        block attached to OutputDataReceived is invoked on a thread-pool thread
        with no runspace, which throws on the first line of output and, being
        unhandled on a non-pipeline thread, terminates the host process. See
        _StreamPump.ps1 for the full account.

        WorkingDirectory is set to the image's own directory. Cue and GDI sheets
        reference their track files by bare filename, and chdman resolves those
        references relative to its working directory rather than to the sheet.
        Setting it per process avoids mutating the session's location, which
        cannot be done safely while several conversions run at once.

        Output is written to a temporary path. Complete-ChdmanProcess promotes it
        to the final name only on success.

        A NOTE ON PROGRESS CADENCE

        Redirecting stderr changes how often chdman speaks. Given a console it
        line-buffers and progress appears continuous; given a pipe its C runtime
        switches to block buffering and holds roughly 4 KB before flushing.
        Progress lines are short, so a great many accumulate inside the child
        before any reach us.

        Measured on a 680 MB CD image (Tests\Buffering.Probe.ps1): 143 progress
        lines over a 67-second conversion, arriving in exactly two bursts, at 43s
        and 67s. Nothing whatsoever before the 43-second mark.

        This is not fixable from this side. There is no flag to disable it, and
        the choice is made by the child's runtime at startup based on what its
        stderr is; only a pseudo-console would change it, at the cost of the
        clean per-slot capture the concurrency design depends on. A progress bar
        that appears frozen for twenty seconds is therefore displaying the newest
        information that exists, and Invoke-ChdmanBatch shows elapsed time
        alongside it so a live job still reads as live.
    .PARAMETER Job
        The job record to execute.
    .PARAMETER ChdmanPath
        Resolved path to the chdman executable.
    .PARAMETER ThreadsPerJob
        Value for --numprocessors.
    .PARAMETER Compression
        Explicit codec chain. Omit to use chdman's defaults.
    .PARAMETER Force
        Pass --force to overwrite an existing output.
    .PARAMETER Slot
        Worker slot index, used for progress bar placement.
    .OUTPUTS
        Hashtable worker record, or $null when the process could not start.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Job,

        [Parameter(Mandatory)]
        [string]$ChdmanPath,

        [int]$ThreadsPerJob = 2,

        [string[]]$Compression,

        [switch]$Force,

        [int]$Slot = 0
    )

    # A leftover temp file from an interrupted run would make chdman refuse to
    # write, so it is cleared before launch.
    Remove-OpsxTempFile -Path $Job.TempPath

    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add($Job.Command)
    $arguments.Add('--input')
    $arguments.Add($Job.SourcePath)
    $arguments.Add('--output')
    $arguments.Add($Job.TempPath)
    $arguments.Add('--numprocessors')
    $arguments.Add([string]$ThreadsPerJob)

    if ($Compression -and $Compression.Count -gt 0) {
        $arguments.Add('--compression')
        $arguments.Add(($Compression -join ','))
    }

    # --force applies to the temp path, which is always freshly removed above,
    # but is passed through so chdman's own overwrite semantics match the
    # caller's intent for the final file.
    if ($Force) { $arguments.Add('--force') }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $ChdmanPath
    $psi.WorkingDirectory = $Job.Directory
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in $arguments) { $psi.ArgumentList.Add($argument) }

    Write-OpsxLog "Executing: $ChdmanPath $($arguments -join ' ')" -Level Detail

    $stdout = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $stderr = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi

    try {
        $null = $process.Start()

        # Started only after a successful Start(), since the stream properties
        # throw before the process exists. The returned tasks complete when
        # their pipe reaches end of stream, which happens when chdman exits or
        # is killed; Complete-ChdmanProcess waits on them so the final lines,
        # including the ratio, are in the queues before they are read.
        $outTask = [Optimize.PSX.StreamPump]::Drain($process.StandardOutput, $stdout)
        $errTask = [Optimize.PSX.StreamPump]::Drain($process.StandardError, $stderr)
    } catch {
        $Job.Status = 'Failed'
        $Job.Error = "Could not start chdman: $($_.Exception.Message)"
        $process.Dispose()
        return $null
    }

    @{
        Job         = $Job
        Process     = $process
        Slot        = $Slot
        StdOut      = $stdout
        StdErr      = $stderr
        OutTask     = $outTask
        ErrTask     = $errTask
        StartTime   = [datetime]::Now
        LastPercent = 0
        LastText    = 'Starting'
        LastRatio   = $null

        # When chdman last reported a percentage. Null until it first does, at
        # which point Update-ChdmanProgress can report how stale a reading is
        # rather than presenting a buffered figure as current.
        LastUpdate  = $null

        Lines       = [System.Collections.Generic.List[string]]::new()
    }
}
