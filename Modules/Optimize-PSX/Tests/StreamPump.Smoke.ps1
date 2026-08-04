# =====================================================================
# StreamPump.Smoke.ps1 - Verifies the child-process output pump
#
# The bug this guards against was fatal rather than merely wrong: a
# PowerShell script block attached to Process.OutputDataReceived runs on a
# runspace-less thread-pool thread and takes the whole host process down
# with it on the first line of output.
#
# A unit test cannot easily assert "the process did not die", so this
# script exercises the real path instead: start a child, pump both
# streams, and confirm the expected text arrives in the queues. If the
# pump ever regresses to a script-block handler, this script crashes
# rather than failing, which is itself an unmistakable signal.
#
#   pwsh -NoProfile -File .\Tests\StreamPump.Smoke.ps1
# =====================================================================

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'Optimize-PSX.psd1') -Force

$failures = [System.Collections.Generic.List[string]]::new()

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
        $script:failures.Add($Name)
    }
}

function Invoke-PumpedProcess {
    <#
        Runs a command through the same mechanism Start-ChdmanProcess uses and
        returns the collected output.
    #>
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FileName
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $psi.ArgumentList.Add($argument) }

    $stdout = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $stderr = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi

    try {
        $null = $process.Start()
        $outTask = [Optimize.PSX.StreamPump]::Drain($process.StandardOutput, $stdout)
        $errTask = [Optimize.PSX.StreamPump]::Drain($process.StandardError, $stderr)

        $process.WaitForExit()
        $null = [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($outTask, $errTask), 10000)

        [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = @($stdout)
            StdErr   = @($stderr)
        }
    } finally {
        $process.Dispose()
    }
}

Write-Host 'StreamPump smoke test' -ForegroundColor Cyan
Write-Host ''

# --- The type exists at all ------------------------------------------
Write-Host 'Type availability' -ForegroundColor Cyan
Test-Case -Name 'Optimize.PSX.StreamPump is defined after import' `
          -Condition ($null -ne ('Optimize.PSX.StreamPump' -as [type]))

# --- Both streams are captured ---------------------------------------
Write-Host ''
Write-Host 'Stream capture' -ForegroundColor Cyan

$both = Invoke-PumpedProcess -FileName 'cmd.exe' -Arguments @(
    '/c', 'echo alpha-out& echo alpha-err 1>&2'
)

Test-Case -Name 'stdout is captured' `
          -Condition ($both.StdOut -contains 'alpha-out') `
          -Detail "got: $($both.StdOut -join ' | ')"

# cmd.exe's echo keeps the space that precedes the redirection operator, so
# the captured text is 'alpha-err ' rather than 'alpha-err'. The pump is
# deliberately faithful to what the child wrote and does not trim, since a
# trimming pump would be guessing about output it does not own. Callers that
# care, such as Update-ChdmanProgress, trim at the point of use.
Test-Case -Name 'stderr is captured' `
          -Condition (@($both.StdErr | ForEach-Object { $_.Trim() }) -contains 'alpha-err') `
          -Detail "got: $($both.StdErr -join ' | ')"

# --- Many lines arrive intact, none lost or merged --------------------
Write-Host ''
Write-Host 'Volume and line integrity' -ForegroundColor Cyan

$bulk = Invoke-PumpedProcess -FileName 'cmd.exe' -Arguments @(
    '/c', 'for /l %i in (1,1,500) do @echo line-%i'
)

Test-Case -Name '500 lines all arrive' `
          -Condition ($bulk.StdOut.Count -eq 500) `
          -Detail "count: $($bulk.StdOut.Count)"

Test-Case -Name 'first and last lines are intact' `
          -Condition ($bulk.StdOut[0] -eq 'line-1' -and $bulk.StdOut[-1] -eq 'line-500') `
          -Detail "first: '$($bulk.StdOut[0])' last: '$($bulk.StdOut[-1])'"

Test-Case -Name 'no blank entries from CRLF splitting' `
          -Condition (@($bulk.StdOut | Where-Object { [string]::IsNullOrEmpty($_) }).Count -eq 0)

# --- Carriage-return progress, which is how chdman reports ------------
Write-Host ''
Write-Host 'Carriage-return delimited output' -ForegroundColor Cyan

# PowerShell as the child, so a bare CR with no trailing newline can be
# emitted the way chdman emits progress.
$crScript = '[Console]::Out.Write("Compressing, 12.5% complete...`r"); ' +
            '[Console]::Out.Write("Compressing, 99.9% complete... (ratio=38.1%)`r"); ' +
            '[Console]::Out.Write("Compression complete")'

$cr = Invoke-PumpedProcess -FileName 'pwsh' -Arguments @('-NoProfile', '-Command', $crScript)

Test-Case -Name 'CR-delimited updates are split into separate entries' `
          -Condition ($cr.StdOut.Count -eq 3) `
          -Detail "got $($cr.StdOut.Count): $($cr.StdOut -join ' | ')"

Test-Case -Name 'unterminated final line is still emitted' `
          -Condition ($cr.StdOut -contains 'Compression complete') `
          -Detail "got: $($cr.StdOut -join ' | ')"

# --- The parsers in the module agree with what the pump produced ------
Write-Host ''
Write-Host 'Progress parsing against pumped output' -ForegroundColor Cyan

$progressLine = @($cr.StdOut | Where-Object { $_ -match 'complete\.\.\.' })[-1]
$progressMatch = [regex]::Match($progressLine, '(?<Percent>\d{1,3}(?:\.\d+)?)%\s*complete')
$ratioMatch = [regex]::Match($progressLine, 'ratio\s*=\s*(?<Ratio>\d{1,3}(?:\.\d+)?)%')

Test-Case -Name 'percentage is parseable from a pumped progress line' `
          -Condition ($progressMatch.Success -and [double]$progressMatch.Groups['Percent'].Value -eq 99.9) `
          -Detail "line: '$progressLine'"

Test-Case -Name 'ratio is parseable from a pumped progress line' `
          -Condition ($ratioMatch.Success -and [double]$ratioMatch.Groups['Ratio'].Value -eq 38.1) `
          -Detail "line: '$progressLine'"

# --- Killing the child ends the pumps rather than hanging -------------
Write-Host ''
Write-Host 'Teardown on kill' -ForegroundColor Cyan

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = 'pwsh'
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
foreach ($a in @('-NoProfile', '-Command', 'while ($true) { "tick"; Start-Sleep -Milliseconds 50 }')) {
    $psi.ArgumentList.Add($a)
}

$victim = [System.Diagnostics.Process]::new()
$victim.StartInfo = $psi
$null = $victim.Start()

$vOut = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$vErr = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$vOutTask = [Optimize.PSX.StreamPump]::Drain($victim.StandardOutput, $vOut)
$vErrTask = [Optimize.PSX.StreamPump]::Drain($victim.StandardError, $vErr)

Start-Sleep -Milliseconds 600
$victim.Kill($true)
$victim.WaitForExit()

$drained = [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($vOutTask, $vErrTask), 5000)
$victim.Dispose()

Test-Case -Name 'pumps complete after the child is killed' -Condition $drained
Test-Case -Name 'output produced before the kill is retained' `
          -Condition ($vOut.Count -gt 0) `
          -Detail "count: $($vOut.Count)"

# --- Result -----------------------------------------------------------
Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host 'All stream pump checks passed.' -ForegroundColor Green
    exit 0
}

Write-Host "$($failures.Count) check(s) failed:" -ForegroundColor Red
foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
exit 1
