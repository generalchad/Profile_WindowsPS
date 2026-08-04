# =====================================================================
# FullRun.Verify.ps1 - End-to-end verification against a real archive
#
# Runs the public cmdlet over a directory exactly as a user would, then
# asserts on the returned summary and on what was left on disk. This is
# the check that would have caught the runspace crash, the doubled temp
# suffix and any progress regression, all in one pass.
#
#   pwsh -NoProfile -File .\Tests\FullRun.Verify.ps1 -Path 'E:\temp'
# =====================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$ChdmanPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'Optimize-PSX.psd1') -Force

$failures = 0

function Test-Case {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Condition,
        [string]$Detail
    )

    if ($Condition) {
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } else {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor DarkGray }
        $script:failures++
    }
}

$arguments = @{ Path = $Path; PassThru = $true }
if ($ChdmanPath) { $arguments.ChdmanPath = $ChdmanPath }

$result = Optimize-PSX @arguments

Write-Host ''
Write-Host 'End-to-end result' -ForegroundColor Cyan

Test-Case -Name 'the cmdlet returned a summary' -Condition ($null -ne $result)
Test-Case -Name 'at least one image converted' -Condition ($result.Converted -ge 1) `
          -Detail "converted: $($result.Converted)"
Test-Case -Name 'nothing failed' -Condition ($result.Failed -eq 0) `
          -Detail "failed: $($result.Failed)"
Test-Case -Name 'nothing was cancelled' -Condition ($result.Cancelled -eq 0) `
          -Detail "cancelled: $($result.Cancelled)"
Test-Case -Name 'a compression ratio was measured' `
          -Condition ($result.CompressionRatio -gt 0 -and $result.CompressionRatio -lt 100) `
          -Detail "ratio: $($result.CompressionRatio)%"

Write-Host ''
Write-Host 'Artefacts on disk' -ForegroundColor Cyan

$onDisk = @(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue)

$chds = @($onDisk | Where-Object Extension -eq '.chd')
Test-Case -Name 'a .chd was produced' -Condition ($chds.Count -ge 1) `
          -Detail "found $($chds.Count)"

# The whole point of the temp-then-promote scheme is that nothing resembling
# an incomplete CHD survives a successful run.
#
# Names are projected before joining: an empty array has no Name property to
# read, and under Set-StrictMode reading one is an error rather than $null.
$temps = @($onDisk | Where-Object Name -like '*.tmp')
Test-Case -Name 'no temporary files left behind' -Condition ($temps.Count -eq 0) `
          -Detail (($temps | ForEach-Object Name) -join ', ')

$doubled = @($onDisk | Where-Object Name -like '*.chd.chd*')
Test-Case -Name 'no doubled .chd.chd names' -Condition ($doubled.Count -eq 0) `
          -Detail (($doubled | ForEach-Object Name) -join ', ')

foreach ($chd in $chds) {
    Test-Case -Name "'$($chd.Name)' is non-empty" -Condition ($chd.Length -gt 0) `
              -Detail "length: $($chd.Length)"
}

Write-Host ''
Write-Host 'Per-job detail' -ForegroundColor Cyan
foreach ($job in $result.Jobs) {
    Write-Host ("  {0,-12} {1,-10} {2}" -f $job.Status, "$($job.Ratio)%", $job.Name)
}

Write-Host ''
if ($failures -eq 0) {
    Write-Host 'End-to-end run verified.' -ForegroundColor Green
    exit 0
}

Write-Host "$failures check(s) failed." -ForegroundColor Red
exit 1
