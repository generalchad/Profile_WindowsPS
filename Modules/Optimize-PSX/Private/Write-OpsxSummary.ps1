function Write-OpsxSummary {
    <#
    .SYNOPSIS
        Writes the end-of-run report and returns a result object.
    .DESCRIPTION
        Reports two distinct measures that are frequently conflated:

          Compression efficiency  output CHD size against the source images that
                                  produced it, which describes how well chdman
                                  performed

          Storage impact          total folder size before and after, which is
                                  only a reduction when sources were removed

        Without cleanup the folder grows, since the CHDs are added alongside
        their sources. Both figures are shown so that outcome reads as expected
        rather than as a fault.

        Failures are listed individually. A batch that reports "3 failed" without
        naming them is not actionable.

        Jobs declined through ShouldProcess are tallied separately from jobs the
        planner rejected. Under -WhatIf every job is declined, and reporting a
        preview run as "converted 0, skipped 3" describes the mechanism rather
        than the outcome. The preview instead states what would have happened.
    .PARAMETER WhatIfMode
        Indicates the run was a preview, so the report describes intent rather
        than results.

    .PARAMETER Jobs
        Job records from Invoke-ChdmanBatch.
    .PARAMETER Extractions
        Extraction records from Expand-OpsxArchive.
    .PARAMETER Cleanup
        Cleanup summary from Remove-OpsxSource.
    .PARAMETER InitialBytes
        Total folder size measured before processing.
    .PARAMETER FinalBytes
        Total folder size measured after processing.
    .PARAMETER Duration
        Total elapsed run time.
    .OUTPUTS
        PSCustomObject summarising the run.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [AllowEmptyCollection()]
        [pscustomobject[]]$Jobs = @(),

        [AllowEmptyCollection()]
        [pscustomobject[]]$Extractions = @(),

        [pscustomobject]$Cleanup,

        [long]$InitialBytes = 0,

        [long]$FinalBytes = 0,

        [timespan]$Duration = [timespan]::Zero,

        [switch]$WhatIfMode
    )


    $converted = @($Jobs | Where-Object { $_.Status -eq 'Converted' })
    $failed = @($Jobs | Where-Object { $_.Status -eq 'Failed' })
    $cancelled = @($Jobs | Where-Object { $_.Status -eq 'Cancelled' })
    $skipped = @($Jobs | Where-Object { $_.Status -eq 'Skipped' })
    $declined = @($Jobs | Where-Object { $_.Status -eq 'Declined' })


    [long]$sourceBytes = 0
    [long]$outputBytes = 0
    foreach ($job in $converted) {
        $sourceBytes += $job.SourceBytes
        $outputBytes += $job.OutputBytes
    }

    $ratio = if ($sourceBytes -gt 0) { [Math]::Round(($outputBytes / $sourceBytes) * 100, 2) } else { $null }
    $savedBytes = $sourceBytes - $outputBytes
    $storageDelta = $FinalBytes - $InitialBytes

    Write-OpsxLog '' -Level Info
    Write-OpsxLog 'Optimization Summary' -Level Info -Phase
    Write-OpsxLog ('=' * 60) -Level Info

    if ($Extractions.Count -gt 0) {
        $extracted = @($Extractions | Where-Object { $_.Status -eq 'Extracted' }).Count
        $extractFailed = @($Extractions | Where-Object { $_.Status -eq 'Failed' }).Count
        Write-OpsxLog "Archives:" -Level Info -ForegroundColor Yellow
        Write-OpsxLog "  Extracted        : $extracted of $($Extractions.Count)" -Level Info
        if ($extractFailed -gt 0) { Write-OpsxLog "  Failed           : $extractFailed" -Level Warning }
    }

    Write-OpsxLog 'Conversions:' -Level Info -ForegroundColor Yellow
    if ($WhatIfMode) {
        Write-OpsxLog "  Would convert    : $($declined.Count)" -Level Info
    } else {
        Write-OpsxLog "  Converted        : $($converted.Count)" -Level Info
        if ($declined.Count -gt 0) { Write-OpsxLog "  Declined         : $($declined.Count)" -Level Info }
    }
    if ($skipped.Count -gt 0)   { Write-OpsxLog "  Skipped          : $($skipped.Count)" -Level Info }

    if ($failed.Count -gt 0)    { Write-OpsxLog "  Failed           : $($failed.Count)" -Level Warning }
    if ($cancelled.Count -gt 0) { Write-OpsxLog "  Cancelled        : $($cancelled.Count)" -Level Warning }

    if ($converted.Count -gt 0) {
        Write-OpsxLog 'Compression:' -Level Info -ForegroundColor Yellow
        Write-OpsxLog "  Source images    : $(Format-OpsxSize $sourceBytes)" -Level Info
        Write-OpsxLog "  Resulting CHDs   : $(Format-OpsxSize $outputBytes)" -Level Info

        if ($null -ne $ratio) {
            Write-OpsxLog "  Ratio            : $ratio% of original" -Level Info
            if ($savedBytes -gt 0) {
                Write-OpsxLog "  Compressed away  : $(Format-OpsxSize $savedBytes) ($([Math]::Round(100 - $ratio, 2))%)" -Level Success
            } else {
                Write-OpsxLog "  Size increase    : $(Format-OpsxSize ([Math]::Abs($savedBytes)))" -Level Warning
            }
        }
    }

    if ($Cleanup -and $Cleanup.Deleted -gt 0) {
        Write-OpsxLog 'Cleanup:' -Level Info -ForegroundColor Yellow
        Write-OpsxLog "  Files removed    : $($Cleanup.Deleted)" -Level Info
        Write-OpsxLog "  Reclaimed        : $(Format-OpsxSize $Cleanup.Bytes)" -Level Info
        if ($Cleanup.Failed -gt 0) { Write-OpsxLog "  Removal failures : $($Cleanup.Failed)" -Level Warning }
    }

    Write-OpsxLog 'Storage:' -Level Info -ForegroundColor Yellow
    Write-OpsxLog "  Folder before    : $(Format-OpsxSize $InitialBytes)" -Level Info
    Write-OpsxLog "  Folder after     : $(Format-OpsxSize $FinalBytes)" -Level Info

    if ($storageDelta -lt 0) {
        Write-OpsxLog "  Net change       : $(Format-OpsxSize $storageDelta) reclaimed" -Level Success
    } elseif ($storageDelta -gt 0) {
        Write-OpsxLog "  Net change       : +$(Format-OpsxSize $storageDelta) (sources retained)" -Level Info
    } else {
        Write-OpsxLog '  Net change       : none' -Level Info
    }

    Write-OpsxLog "Elapsed            : $($Duration.ToString('hh\:mm\:ss'))" -Level Info
    Write-OpsxLog ('=' * 60) -Level Info

    if ($failed.Count -gt 0) {
        Write-OpsxLog '' -Level Info
        Write-OpsxLog 'Failures:' -Level Warning
        foreach ($job in $failed) {
            Write-OpsxLog "  $($job.Name): $($job.Error)" -Level Error
        }
    }

    [pscustomobject]@{
        PSTypeName       = 'Optimize-PSX.Result'
        ArchivesFound    = $Extractions.Count
        ArchivesExpanded = @($Extractions | Where-Object { $_.Status -eq 'Extracted' }).Count
        Converted        = $converted.Count
        Failed           = $failed.Count
        Skipped          = $skipped.Count
        Declined         = $declined.Count
        Cancelled        = $cancelled.Count
        WhatIf           = [bool]$WhatIfMode

        SourceBytes      = $sourceBytes
        OutputBytes      = $outputBytes
        CompressionRatio = $ratio
        BytesSaved       = $savedBytes
        FilesRemoved     = if ($Cleanup) { $Cleanup.Deleted } else { 0 }
        BytesReclaimed   = if ($Cleanup) { $Cleanup.Bytes } else { [long]0 }
        InitialBytes     = $InitialBytes
        FinalBytes       = $FinalBytes
        StorageDelta     = $storageDelta
        Duration         = $Duration
        Jobs             = $Jobs
        Extractions      = $Extractions
    }
}
