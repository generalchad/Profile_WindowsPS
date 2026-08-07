function Write-PrintStackSummary {
    <#
    .SYNOPSIS
        Prints the end-of-run summary table.

    .DESCRIPTION
        Groups the step results so the common case - everything worked - is a
        single green line, while failures are listed individually with the exact
        command that failed. A technician who has just deleted a dozen objects
        needs to know instantly whether anything was left behind.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Results,

        [string] $BackupPath = ''
    )

    $results = @($Results)

    Write-Host ''
    Write-Host 'Restart-PrintStack - summary' -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor DarkGray

    if ($results.Count -eq 0) {
        Write-Host '  Nothing was done.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    foreach ($group in ($results | Group-Object Step)) {
        $ok = @($group.Group | Where-Object { $_.Status -eq 'Success' }).Count
        $failed = @($group.Group | Where-Object { $_.Status -eq 'Failed' }).Count
        $skipped = @($group.Group | Where-Object { $_.Status -eq 'Skipped' }).Count
        $whatIf = @($group.Group | Where-Object { $_.Status -eq 'WhatIf' }).Count

        $parts = @()
        if ($ok) { $parts += "$ok succeeded" }
        if ($failed) { $parts += "$failed failed" }
        if ($skipped) { $parts += "$skipped skipped" }
        if ($whatIf) { $parts += "$whatIf simulated" }

        $color = if ($failed) { 'Yellow' } elseif ($ok) { 'Green' } else { 'DarkGray' }
        Write-Host ('  {0,-22} {1}' -f $group.Name, ($parts -join ', ')) -ForegroundColor $color
    }

    $failures = @($results | Where-Object { $_.Status -eq 'Failed' })
    if ($failures.Count) {
        Write-Host ''
        Write-Host '  Failures' -ForegroundColor Yellow
        foreach ($f in $failures) {
            Write-Host "    $($f.Step): $($f.Target)" -ForegroundColor Yellow
            if ($f.Message) { Write-Host "      $($f.Message)" -ForegroundColor DarkGray }
            if ($f.Command) { Write-Host "      $($f.Command)" -ForegroundColor DarkGray }
        }
    }

    if ($BackupPath) {
        Write-Host ''
        Write-Host "  A snapshot of the previous configuration was saved to:" -ForegroundColor DarkGray
        Write-Host "    $BackupPath" -ForegroundColor DarkGray
    }

    Write-Host ''
}
