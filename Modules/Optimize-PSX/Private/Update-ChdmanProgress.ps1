function Update-ChdmanProgress {
    <#
    .SYNOPSIS
        Drains a worker's output queues and returns its current progress.
    .DESCRIPTION
        Dequeues whatever the stream pumps have collected since the last call,
        retains the lines for diagnostics, and extracts the most recent percentage
        and compression ratio.

        chdman reports progress on stderr, so both streams are read and treated
        as one logical output. Lines are also kept for the failure path, where the
        tail of output is the only useful description of what went wrong.

        The last known percentage is retained between calls so the progress bar
        holds its position during the quiet stretches between updates. Those
        stretches are long and unavoidable: chdman block-buffers stderr when it is
        a pipe rather than a console, so a minute-long conversion delivers its
        progress in two or three bursts rather than continuously. See the note in
        Start-ChdmanProcess.

        Because of that, the age of the reading is reported alongside it. A caller
        that knows a percentage is thirty seconds old can say so, instead of
        presenting stale information as current. Nothing here estimates or
        interpolates: every figure returned is one chdman actually printed.
    .PARAMETER Worker
        Worker record from Start-ChdmanProcess.
    .OUTPUTS
        Hashtable { Percent, Text, Ratio, Age, IsFresh }, or $null when nothing
        has been reported yet.

        Age     TimeSpan since chdman last reported a percentage.
        IsFresh $true when that happened during this call.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [hashtable]$Worker
    )

    $line = $null
    $sawOutput = $false
    $sawPercent = $false

    foreach ($queue in @($Worker.StdErr, $Worker.StdOut)) {
        while ($queue.TryDequeue([ref]$line)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $sawOutput = $true

            # Bounded so a pathological progress stream cannot grow without
            # limit over a long conversion. The tail is what matters on failure.
            $Worker.Lines.Add($line)
            if ($Worker.Lines.Count -gt 200) { $Worker.Lines.RemoveAt(0) }

            $progressMatch = [regex]::Match($line, $script:RegexChdmanProgress)
            if ($progressMatch.Success) {
                $percent = [double]$progressMatch.Groups['Percent'].Value

                # Clamped and monotonic. chdman's percentage restarts from zero
                # between its own phases, and a bar that jumps backwards reads as
                # a fault even when nothing is wrong.
                $rounded = [Math]::Min(100, [Math]::Max(0, [Math]::Round($percent)))
                if ($rounded -ge $Worker.LastPercent) {
                    $Worker.LastPercent = $rounded
                }

                $Worker.LastText = $line.Trim()
                $Worker.LastUpdate = [datetime]::Now
                $sawPercent = $true
            }

            $ratioMatch = [regex]::Match($line, $script:RegexChdmanRatio)
            if ($ratioMatch.Success) {
                $Worker.LastRatio = [double]$ratioMatch.Groups['Ratio'].Value
            }
        }
    }

    if (-not $sawOutput -and $Worker.LastPercent -eq 0) { return $null }

    # Before the first percentage arrives, age is measured from launch, which is
    # exactly the interval the caller wants to describe: how long this job has
    # been running without saying anything.
    $since = if ($Worker.LastUpdate) { $Worker.LastUpdate } else { $Worker.StartTime }

    @{
        Percent = [int]$Worker.LastPercent
        Text    = $Worker.LastText
        Ratio   = $Worker.LastRatio
        Age     = ([datetime]::Now - $since)
        IsFresh = $sawPercent
    }
}
