# =====================================================================
# Progress.Probe.ps1 - Diagnoses whether progress reporting is live
#
# After the runspace fix a batch run showed the child bar frozen at a
# single percentage for its whole duration. That has two possible causes
# and they need to be told apart:
#
#   1. The pump is delivering only one line, so the module genuinely has
#      nothing newer to display.
#   2. The pump is delivering many lines and Write-Progress is simply not
#      repainting, which is host behaviour rather than a module defect.
#
# This script answers that by reading a live chdman conversion through
# the module's own Start-ChdmanProcess and Update-ChdmanProgress, and
# printing each distinct percentage it observes as plain text. Plain text
# cannot be suppressed by a non-interactive host, so if the numbers climb
# here the parsing chain is sound and any frozen bar is presentation.
#
#   pwsh -NoProfile -File .\Tests\Progress.Probe.ps1 -Source '<path to .cue>'
# =====================================================================

[CmdletBinding()]
param(
    # A real disc image. Larger is better; a conversion that finishes in
    # under a second cannot demonstrate anything about progress.
    [Parameter(Mandatory)]
    [string]$Source,

    # Where the probe writes its CHD. Removed on completion.
    [string]$OutputPath,

    [string]$ChdmanPath = 'chdman'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'Optimize-PSX.psd1') -Force
$module = Get-Module -Name Optimize-PSX

$sourceInfo = [System.IO.FileInfo]::new((Resolve-Path -LiteralPath $Source).ProviderPath)

if (-not $OutputPath) {
    $OutputPath = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        "opsx-probe-$($sourceInfo.BaseName).chd"
    )
}

Write-Host "Source : $($sourceInfo.FullName)"
Write-Host "Output : $OutputPath"
Write-Host ''

# The whole probe runs inside the module scope so the private functions and
# the script-scoped regexes are all in view.
$observations = & $module {
    param($SourceInfo, $OutputPath, $ChdmanPath)

    $resolved = Resolve-ChdmanBinary -Path $ChdmanPath
    if (-not $resolved.Found) { throw $resolved.Error }

    $job = New-OpsxJob -Source $SourceInfo -OutputPath $OutputPath -Command 'createcd' `
                       -Dependencies @() -SourceBytes $SourceInfo.Length

    $worker = Start-ChdmanProcess -Job $job -ChdmanPath $resolved.Path -ThreadsPerJob 4 -Force
    if (-not $worker) { throw "Could not start chdman: $($job.Error)" }

    $samples = [System.Collections.Generic.List[pscustomobject]]::new()
    $lastPercent = -1
    $start = [datetime]::Now

    try {
        while (-not $worker.Process.HasExited) {
            Start-Sleep -Milliseconds $script:PumpIntervalMs

            $status = Update-ChdmanProgress -Worker $worker
            if ($status -and $status.Percent -ne $lastPercent) {
                $lastPercent = $status.Percent
                $samples.Add([pscustomobject]@{
                    Elapsed = ([datetime]::Now - $start)
                    Percent = $status.Percent
                    Ratio   = $status.Ratio
                    Text    = $status.Text
                })
            }
        }

        Complete-ChdmanProcess -Worker $worker

        [pscustomobject]@{
            Samples    = $samples
            Status     = $job.Status
            ExitCode   = $job.ExitCode
            Error      = $job.Error
            LineCount  = $worker.Lines.Count
            OutputPath = $job.OutputPath
        }
    } finally {
        if (-not $worker.Process.HasExited) {
            try { $worker.Process.Kill($true) } catch { }
        }
        Remove-OpsxTempFile -Path $job.TempPath
    }
} $sourceInfo $OutputPath $ChdmanPath

Write-Host 'Distinct progress readings observed' -ForegroundColor Cyan
foreach ($sample in $observations.Samples) {
    $ratio = if ($null -ne $sample.Ratio) { "ratio $($sample.Ratio)%" } else { 'ratio n/a' }
    Write-Host ("  {0,8}  {1,3}%  {2}" -f $sample.Elapsed.ToString('mm\:ss\.f'), $sample.Percent, $ratio)
}

Write-Host ''
Write-Host 'Result' -ForegroundColor Cyan
Write-Host "  chdman status     : $($observations.Status) (exit $($observations.ExitCode))"
if ($observations.Error) { Write-Host "  error             : $($observations.Error)" -ForegroundColor Red }
Write-Host "  lines retained    : $($observations.LineCount) (capped at 200)"
Write-Host "  distinct readings : $($observations.Samples.Count)"

Write-Host ''
if ($observations.Samples.Count -gt 1) {
    Write-Host 'Progress parsing is live: the module sees the percentage climb.' -ForegroundColor Green
    Write-Host 'A bar that appears frozen is therefore a host rendering matter,' -ForegroundColor Green
    Write-Host 'not a parsing or pump defect.' -ForegroundColor Green
} else {
    Write-Host 'Only one reading was observed. The pump or the progress regex is at fault.' -ForegroundColor Red
}

if (Test-Path -LiteralPath $observations.OutputPath) {
    Remove-Item -LiteralPath $observations.OutputPath -Force
    Write-Host ''
    Write-Host "Removed probe output: $($observations.OutputPath)" -ForegroundColor DarkGray
}
