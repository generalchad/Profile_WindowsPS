# =====================================================================
# Buffering.Probe.ps1 - Shows how chdman's output actually arrives
#
# Progress.Probe.ps1 established that the module parses every percentage
# it is given. This script asks the prior question: how often is it given
# one? It timestamps each line as the pump delivers it, so a stream that
# arrives in a few large bursts is immediately distinguishable from one
# that trickles steadily.
#
# The distinction matters because a bursty stream cannot be fixed by any
# change to the progress bar. chdman writes progress to stderr, and when
# stderr is a pipe rather than a console the C runtime switches from
# line-buffered to block-buffered, holding roughly 4 KB before flushing.
# Progress lines are short, so hundreds accumulate in the child's own
# buffer before any of them reach us, all at once and all already stale.
#
#   pwsh -NoProfile -File .\Tests\Buffering.Probe.ps1 -Source '<path to .cue>'
# =====================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Source,

    [string]$ChdmanPath = 'chdman'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'Optimize-PSX.psd1') -Force
$module = Get-Module -Name Optimize-PSX

$sourceInfo = [System.IO.FileInfo]::new((Resolve-Path -LiteralPath $Source).ProviderPath)
$outputPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'opsx-buffering-probe.chd')

Write-Host "Source : $($sourceInfo.FullName)"
Write-Host ''

$arrivals = & $module {
    param($SourceInfo, $OutputPath, $ChdmanPath)

    $resolved = Resolve-ChdmanBinary -Path $ChdmanPath
    if (-not $resolved.Found) { throw $resolved.Error }

    $job = New-OpsxJob -Source $SourceInfo -OutputPath $OutputPath -Command 'createcd' `
                       -Dependencies @() -SourceBytes $SourceInfo.Length

    $worker = Start-ChdmanProcess -Job $job -ChdmanPath $resolved.Path -ThreadsPerJob 4 -Force
    if (-not $worker) { throw "Could not start chdman: $($job.Error)" }

    $events = [System.Collections.Generic.List[pscustomobject]]::new()
    $start = [datetime]::Now

    try {
        # The queues are read directly rather than through
        # Update-ChdmanProgress, so the count of lines per poll is visible.
        while (-not $worker.Process.HasExited) {
            Start-Sleep -Milliseconds $script:PumpIntervalMs

            $batch = 0
            $line = $null
            foreach ($queue in @($worker.StdErr, $worker.StdOut)) {
                while ($queue.TryDequeue([ref]$line)) {
                    if (-not [string]::IsNullOrWhiteSpace($line)) { $batch++ }
                }
            }

            if ($batch -gt 0) {
                $events.Add([pscustomobject]@{
                    Elapsed = ([datetime]::Now - $start)
                    Lines   = $batch
                })
            }
        }

        $worker.Process.WaitForExit()
        $events
    } finally {
        if (-not $worker.Process.HasExited) {
            try { $worker.Process.Kill($true) } catch { }
        }
        try { $worker.Process.Dispose() } catch { }
        Remove-OpsxTempFile -Path $job.TempPath
        if (Test-Path -LiteralPath $job.OutputPath) {
            Remove-Item -LiteralPath $job.OutputPath -Force
        }
    }
} $sourceInfo $outputPath $ChdmanPath

$arrivals = @($arrivals)

Write-Host 'Output arrivals (one row per poll that saw anything)' -ForegroundColor Cyan
foreach ($arrival in $arrivals) {
    Write-Host ("  {0,8}  {1,4} line(s)" -f $arrival.Elapsed.ToString('mm\:ss\.f'), $arrival.Lines)
}

$totalLines = ($arrivals | Measure-Object -Property Lines -Sum).Sum

Write-Host ''
Write-Host 'Analysis' -ForegroundColor Cyan
Write-Host "  polls that saw output : $($arrivals.Count)"
Write-Host "  total lines           : $totalLines"

if ($arrivals.Count -gt 0) {
    $largest = ($arrivals | Measure-Object -Property Lines -Maximum).Maximum
    Write-Host "  largest single burst  : $largest line(s)"

    Write-Host ''
    if ($arrivals.Count -le 5 -and $totalLines -gt 20) {
        Write-Host 'chdman is block-buffering its progress output: many lines arrive' -ForegroundColor Yellow
        Write-Host 'in very few bursts. The progress bar cannot be made smooth from' -ForegroundColor Yellow
        Write-Host 'this side, because the updates do not exist yet when they would' -ForegroundColor Yellow
        Write-Host 'be needed. They are already stale on arrival.' -ForegroundColor Yellow
    } else {
        Write-Host 'Output arrives spread over time, so progress can be displayed smoothly.' -ForegroundColor Green
    }
}
