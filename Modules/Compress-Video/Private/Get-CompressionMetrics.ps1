function Get-CompressionMetrics {
    <#
    .SYNOPSIS
        Computes size/savings metrics for a completed compression result.

    .DESCRIPTION
        Internal helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Result
    )

    process {
        if (-not $Result.Success -or -not $Result.OutputFile) { return $null }

        $orig = $Result.InputFile.Length
        $new  = $Result.OutputFile.Length

        # Avoid divide by zero if input file is somehow 0 bytes
        $savings = if ($orig -gt 0) { [Math]::Round(($orig - $new) / $orig * 100, 2) } else { 0 }

        [PSCustomObject]@{
            FileName       = $Result.InputFile.Name
            OriginalSizeMB = [Math]::Round($orig / 1MB, 2)
            NewSizeMB      = [Math]::Round($new / 1MB, 2)
            SavingsPercent = $savings
        }
    }
}

function Write-CompressionSummary {
    <#
    .SYNOPSIS
        Prints the final aggregate compression summary table.

    .DESCRIPTION
        Internal helper. Not exported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[PSCustomObject]]$Stats
    )

    process {
        if ($null -ne $Stats -and $Stats.Count -gt 0) {
            Write-Host "`n--- Overall Compression Summary ---" -ForegroundColor Cyan
            $Stats | Format-Table -AutoSize

            $totalSaved = ($Stats | Measure-Object -Property SavingsPercent -Average).Average
            Write-Host "Average Space Saved: $([Math]::Round($totalSaved, 2))%" -ForegroundColor Green
        } else {
            Write-Host "`nNo files were successfully compressed." -ForegroundColor Yellow
        }
    }
}
