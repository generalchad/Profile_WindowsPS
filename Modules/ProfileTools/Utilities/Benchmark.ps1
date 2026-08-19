# -----------------------------------------------------------------------------
# Utilities/Benchmark.ps1 - Profile load-time measurement
# -----------------------------------------------------------------------------

function Measure-ProfileLoad {
    <#
    .SYNOPSIS
        Measures cold-start pwsh launch time with and without the user profile.

    .DESCRIPTION
        Spawns N pwsh processes that start and immediately exit, and reports the
        wall-clock cost of each.

        Two numbers matter:
          Baseline  - 'pwsh -NoProfile', the irreducible engine startup cost.
          Profile   - 'pwsh', the full startup a new terminal actually pays.
          Overhead  - the difference, i.e. what this repo is responsible for.

        Measurements run in a real console (not redirected), because a redirected
        host takes different code paths in PSReadLine and oh-my-posh and will
        under-report the true cost.

    .PARAMETER Iterations
        Number of launches per configuration. Default 10.

    .PARAMETER Trace
        Also collect the per-stage breakdown emitted by $env:PROFILE_TRACE and
        print the mean of each stage.

    .EXAMPLE
        Measure-ProfileLoad

    .EXAMPLE
        Measure-ProfileLoad -Iterations 20 -Trace
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 200)]
        [int]$Iterations = 10,

        [switch]$Trace
    )

    $pwshPath = (Get-Process -Id $PID).Path
    if (-not $pwshPath) { $pwshPath = 'pwsh' }

    function Invoke-Run {
        param([string[]]$ArgList)
        # Start-Process gives the child its own console, so output is NOT redirected
        # and PSReadLine / oh-my-posh take their normal interactive code paths.
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $p = Start-Process -FilePath $pwshPath -ArgumentList $ArgList `
             -WindowStyle Hidden -PassThru
        $p.WaitForExit()
        $sw.Stop()
        return $sw.Elapsed.TotalMilliseconds
    }

    $configs = [ordered]@{
        'Baseline (-NoProfile)' = @('-NoLogo', '-NoProfile', '-Command', 'exit')
        'With profile'          = @('-NoLogo', '-Command', 'exit')
    }

    # Discard a warm-up run per config; the very first launch pays disk/page-cache costs.
    foreach ($argList in $configs.Values) { $null = Invoke-Run $argList }

    $results = foreach ($name in $configs.Keys) {
        $samples = 1..$Iterations | ForEach-Object { Invoke-Run $configs[$name] }
        $stats = $samples | Measure-Object -Average -Minimum -Maximum
        [pscustomobject]@{
            Configuration = $name
            MeanMs        = [math]::Round($stats.Average, 1)
            MinMs         = [math]::Round($stats.Minimum, 1)
            MaxMs         = [math]::Round($stats.Maximum, 1)
        }
    }

    $results | Format-Table -AutoSize | Out-String | Write-Host

    $base = ($results | Where-Object Configuration -like 'Baseline*').MeanMs
    $full = ($results | Where-Object Configuration -like 'With profile*').MeanMs
    Write-Host ("Profile overhead: {0} ms  ({1} ms total - {2} ms engine baseline)" -f `
        [math]::Round($full - $base, 1), $full, $base) -ForegroundColor Yellow

    if ($Trace) {
        Write-Host "`nPer-stage breakdown (mean of $Iterations runs):" -ForegroundColor Cyan
        $log = Join-Path $env:TEMP 'pwsh-profile-trace.log'
        Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue

        $old = $env:PROFILE_TRACE
        $env:PROFILE_TRACE = '1'
        try {
            1..$Iterations | ForEach-Object { $null = Invoke-Run @('-NoLogo', '-Command', 'exit') }
        } finally {
            if ($null -eq $old) { Remove-Item Env:\PROFILE_TRACE -ErrorAction SilentlyContinue }
            else { $env:PROFILE_TRACE = $old }
        }

        if (Test-Path $log) {
            Get-Content $log |
                Where-Object { $_ -match '^\s*(\S[\w+\-]*)\s+([\d.]+)\s+([\d.]+)\s*$' } |
                ForEach-Object {
                    if ($_ -match '^\s*(\S[\w+\-]*)\s+([\d.]+)\s+([\d.]+)\s*$') {
                        [pscustomobject]@{ Stage = $Matches[1]; Ms = [double]$Matches[2] }
                    }
                } |
                Group-Object Stage |
                ForEach-Object {
                    [pscustomobject]@{
                        Stage  = $_.Name
                        MeanMs = [math]::Round(($_.Group.Ms | Measure-Object -Average).Average, 1)
                        Runs   = $_.Count
                    }
                } |
                Sort-Object MeanMs -Descending |
                Format-Table -AutoSize | Out-String | Write-Host
        } else {
            Write-Warning "No trace log produced at $log"
        }
    }
}
