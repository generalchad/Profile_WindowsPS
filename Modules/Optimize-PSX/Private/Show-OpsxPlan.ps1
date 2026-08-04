function Show-OpsxPlan {
    <#
    .SYNOPSIS
        Displays the conversion plan before any work begins.
    .DESCRIPTION
        Reports what will be converted, what was skipped and why, and the
        concurrency settings that will be applied, so a mis-targeted run can be
        abandoned before a long batch starts.

        Skipped items are listed with their reason. An unreadable sheet or a
        missing track file is far more useful surfaced here than discovered as a
        failure an hour into a batch.
    .PARAMETER Plan
        Conversion plan from Get-OpsxConversionPlan.
    .PARAMETER Concurrency
        Concurrency plan from Get-OpsxConcurrencyPlan.
    .PARAMETER Compression
        Codec chain in use, or $null for chdman defaults.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [pscustomobject]$Plan,

        [Parameter(Mandatory)]
        [pscustomobject]$Concurrency,

        [string[]]$Compression
    )

    Write-OpsxLog '' -Level Info
    Write-OpsxLog 'Conversion Plan' -Level Info -Phase
    Write-OpsxLog ('-' * 60) -Level Info

    if ($Plan.Jobs.Count -eq 0) {
        Write-OpsxLog 'No images require conversion.' -Level Warning
    } else {
        Write-OpsxLog "  Images queued  : $($Plan.Jobs.Count)" -Level Info
        Write-OpsxLog "  Source size    : $(Format-OpsxSize $Plan.TotalBytes)" -Level Info

        $byCommand = $Plan.Jobs | Group-Object -Property Command
        foreach ($group in $byCommand) {
            Write-OpsxLog "  $($group.Name.PadRight(15)): $($group.Count) image(s)" -Level Info
        }

        $codecText = if ($Compression -and $Compression.Count -gt 0) {
            $Compression -join ','
        } else {
            'chdman defaults'
        }
        Write-OpsxLog "  Compression    : $codecText" -Level Info
        Write-OpsxLog "  Concurrency    : $($Concurrency.Concurrency) job(s) x $($Concurrency.ThreadsPerJob) thread(s)" -Level Info
        Write-OpsxLog "  Storage        : $($Concurrency.MediaType)" -Level Info
        Write-OpsxLog "  $($Concurrency.Rationale)" -Level Detail
    }

    if ($Plan.Skipped.Count -gt 0) {
        Write-OpsxLog '' -Level Info
        Write-OpsxLog "Skipped ($($Plan.Skipped.Count)):" -Level Warning
        foreach ($job in $Plan.Skipped) {
            Write-OpsxLog "  $($job.Name) - $($job.Reason)" -Level Warning
        }
    }

    Write-OpsxLog ('-' * 60) -Level Info
    Write-OpsxLog '' -Level Info
}
