function Format-ScanShareResult {
    <#
    .SYNOPSIS
        Renders a New-ScanShare result object into display text and a copier summary.

    .DESCRIPTION
        The GUI cannot surface New-ScanShare's Write-Host output, so this formats the
        structured result into an aligned Step/Status/Detail table and, on a
        successful real run, builds the "Enter on the copier" block. It returns both
        the console-style text and the copier summary so the dialog can display one
        and copy the other to the clipboard.

    .PARAMETER Result
        The object returned by New-ScanShare. May be $null when the command bailed out
        early (e.g. not elevated).

    .PARAMETER DryRun
        Whether the result came from -WhatIf. Preview results never show copier
        settings.

    .PARAMETER ShareName
        Share name as entered in the dialog, for the copier summary.

    .PARAMETER UserName
        Account name as entered in the dialog, for the copier summary.

    .OUTPUTS
        PSCustomObject with Text (display) and Summary (clipboard/copier settings) strings.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][object]$Result,
        [Parameter()][switch]$DryRun,
        [Parameter()][string]$ShareName,
        [Parameter()][string]$UserName
    )

    $text = [System.Text.StringBuilder]::new()

    if ($null -eq $Result) {
        $null = $text.AppendLine('No result was returned.')
        $null = $text.AppendLine('The command did not run - a change was probably not permitted (elevation required).')
        return [pscustomobject]@{ Text = $text.ToString(); Summary = '' }
    }

    $steps = @()
    if ($Result.PSObject.Properties['Steps'] -and $Result.Steps) { $steps = @($Result.Steps) }

    $null = $text.AppendLine(('{0,-10} {1,-12} {2}' -f 'STATUS', 'STEP', 'DETAIL'))
    $null = $text.AppendLine(('-' * 80))
    foreach ($step in $steps) {
        $null = $text.AppendLine(('{0,-10} {1,-12} {2}' -f $step.Status, $step.Step, $step.Detail))
    }
    $null = $text.AppendLine('')

    $summary = ''
    $failed = @($steps | Where-Object Status -eq 'Failed').Count

    if ($DryRun) {
        $null = $text.AppendLine('Preview only - no changes were made.')
    }
    elseif ($failed -gt 0) {
        $null = $text.AppendLine("$failed step(s) failed. Review the table above.")
    }
    elseif ($Result.PSObject.Properties['UncPath'] -and $Result.UncPath) {
        $ip = Get-PrimaryIPv4Address
        $hostLine = $env:COMPUTERNAME
        if ($ip) { $hostLine = "$env:COMPUTERNAME  (or $ip)" }

        $lines = @(
            'Enter on the copier:'
            "  Host / server : $hostLine"
            "  Share / path  : $ShareName"
            "  Full path     : $($Result.UncPath)"
            "  User name     : $UserName   (some models need $($Result.Account))"
            '  Protocol      : SMB, port 445'
        )
        foreach ($line in $lines) { $null = $text.AppendLine($line) }
        $summary = ($lines -join [Environment]::NewLine)
    }

    [pscustomobject]@{ Text = $text.ToString(); Summary = $summary }
}
