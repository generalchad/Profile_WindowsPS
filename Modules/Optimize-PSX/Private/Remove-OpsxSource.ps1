function Remove-OpsxSource {
    <#
    .SYNOPSIS
        Removes source images and archives whose CHD was produced successfully.
    .DESCRIPTION
        Deletion is driven by the job records rather than by an extension sweep,
        so only files belonging to a verified conversion are ever candidates. A
        job that failed, was skipped, or was cancelled leaves its source
        untouched.

        For each converted job the source sheet or ISO and every dependency it
        referenced are removed. The output CHD is confirmed present and non-empty
        immediately before deletion, which closes the window between conversion
        and cleanup.

        Archives are removed only when the images extracted from them converted
        successfully. An archive whose contents failed to convert is the only
        remaining copy of that data and is kept.

        Files are sent to the Recycle Bin by default. -Permanent bypasses it. If
        the Recycle Bin is unavailable the deletion is refused rather than
        escalated to a permanent delete.
    .PARAMETER Jobs
        Job records returned by Invoke-ChdmanBatch.
    .PARAMETER Extractions
        Extraction records from Expand-OpsxArchive, required for archive cleanup.
    .PARAMETER RemoveImages
        Delete converted source images and their track files.
    .PARAMETER RemoveArchives
        Delete archives whose extracted contents converted successfully.
    .PARAMETER Permanent
        Bypass the Recycle Bin.
    .PARAMETER Cmdlet
        Calling $PSCmdlet, so ShouldProcess honours -WhatIf and -Confirm.
    .OUTPUTS
        PSCustomObject { Deleted, Failed, Bytes }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [pscustomobject[]]$Jobs,

        [AllowEmptyCollection()]
        [pscustomobject[]]$Extractions = @(),

        [switch]$RemoveImages,

        [switch]$RemoveArchives,

        [switch]$Permanent,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $summary = [pscustomobject]@{
        Deleted = 0
        Failed  = 0
        Bytes   = [long]0
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    $converted = @($Jobs | Where-Object { $_.Status -eq 'Converted' })

    if ($RemoveImages) {
        foreach ($job in $converted) {
            # Re-verify the output rather than trusting the recorded status: the
            # CHD is the only remaining copy once these files are gone.
            if (-not [System.IO.File]::Exists($job.OutputPath)) { continue }
            if ([System.IO.FileInfo]::new($job.OutputPath).Length -le 0) { continue }

            $candidates.Add($job.SourcePath)
            foreach ($dependency in $job.Dependencies) { $candidates.Add($dependency) }
        }
    }

    if ($RemoveArchives -and $Extractions.Count -gt 0) {
        foreach ($extraction in ($Extractions | Where-Object { $_.Status -eq 'Extracted' })) {
            # An archive is only redundant once something extracted from it has
            # been converted. Comparing directory prefixes identifies the jobs
            # that came out of this archive's target folder.
            $prefix = $extraction.Target.TrimEnd('\') + '\'
            $fromThisArchive = @(
                $converted | Where-Object { $_.SourcePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) }
            )

            if ($fromThisArchive.Count -gt 0) {
                $candidates.Add($extraction.Path)
            } else {
                Write-OpsxLog "Keeping $($extraction.Name): no image from it converted successfully." -Level Detail
            }
        }
    }

    if ($candidates.Count -eq 0) {
        Write-OpsxLog 'Nothing eligible for cleanup.' -Level Info
        return $summary
    }

    # A track file shared by two sheets would otherwise be queued twice, and the
    # second delete would fail noisily on a file already gone.
    $unique = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $processed = 0

    Write-OpsxLog "Cleaning up $($candidates.Count) source file(s)..." -Level Info -Phase

    foreach ($path in $candidates) {
        if (-not $unique.Add($path)) { continue }
        if (-not [System.IO.File]::Exists($path)) { continue }

        $processed++
        Write-Progress -Id $script:ParentProgressId -Activity 'Removing source files' `
                       -Status "$processed of $($unique.Count)" `
                       -PercentComplete ([Math]::Min(100, ($processed / $candidates.Count) * 100))

        $size = [System.IO.FileInfo]::new($path).Length
        $action = if ($Permanent) { 'Delete permanently' } else { 'Send to Recycle Bin' }

        if (-not $Cmdlet.ShouldProcess($path, $action)) { continue }

        try {
            if ($Permanent) {
                [System.IO.File]::Delete($path)
            } else {
                Send-OpsxToRecycleBin -Path $path
            }

            $summary.Deleted++
            $summary.Bytes += $size
            Write-OpsxLog "Removed $([System.IO.Path]::GetFileName($path))" -Level Detail
        } catch {
            $summary.Failed++
            Write-OpsxLog "Could not remove '$path': $($_.Exception.Message)" -Level Error
        }
    }

    Write-Progress -Id $script:ParentProgressId -Activity 'Removing source files' -Completed
    return $summary
}
