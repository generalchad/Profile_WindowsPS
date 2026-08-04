function Expand-OpsxArchive {
    <#
    .SYNOPSIS
        Extracts archives found in the file index.
    .DESCRIPTION
        Each archive is extracted into a sibling folder named after the archive,
        keeping multi-disc sets and their sheets together.

        Extraction uses 7Zip4PowerShell when available, falling back to
        Expand-Archive for .zip. Archives in other formats are reported as
        skipped when the module is absent; nothing is installed implicitly, since
        a batch operation is not the place to modify the user's module set.

        An archive whose target folder already exists and is non-empty is skipped
        unless -Force is supplied, so re-running over a partially processed
        library does not repeat completed work.

        Extraction runs sequentially. It is dominated by disk throughput and by
        single-threaded decompression of solid archives, so overlapping several
        extractions on one volume increases total time rather than reducing it.
    .PARAMETER Index
        A file index from Get-OpsxFileIndex.
    .PARAMETER Force
        Re-extract archives whose target folder already contains files.
    .PARAMETER Cmdlet
        Calling $PSCmdlet, so ShouldProcess honours -WhatIf and -Confirm.
    .OUTPUTS
        PSCustomObject records { Name, Path, Target, Status, Reason, Duration }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [pscustomobject]$Index,

        [switch]$Force,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $archives = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($ext in $script:ArchiveExtensions) {
        if ($Index.ByExtension.ContainsKey($ext)) {
            foreach ($file in $Index.ByExtension[$ext]) { $archives.Add($file) }
        }
    }

    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    if ($archives.Count -eq 0) {
        Write-OpsxLog 'No archives found.' -Level Info
        return $results
    }

    Write-OpsxLog "Extracting $($archives.Count) archive(s)..." -Level Info -Phase

    $hasSevenZip = $null -ne (Get-Module -Name 7Zip4PowerShell -ListAvailable -ErrorAction SilentlyContinue)
    if ($hasSevenZip) {
        Import-Module -Name 7Zip4PowerShell -ErrorAction SilentlyContinue
    } else {
        Write-OpsxLog '7Zip4PowerShell is not installed. Only .zip archives can be extracted. Install with: Install-Module 7Zip4PowerShell' -Level Warning
    }

    $processed = 0

    foreach ($archive in $archives) {
        $processed++
        Write-Progress -Id $script:ParentProgressId -Activity 'Extracting archives' `
                       -Status "$processed of $($archives.Count): $($archive.Name)" `
                       -PercentComplete (($processed / $archives.Count) * 100)

        $target = [System.IO.Path]::Combine($archive.DirectoryName, $archive.BaseName)

        $record = [pscustomobject]@{
            PSTypeName = 'Optimize-PSX.Extraction'
            Name       = $archive.Name
            Path       = $archive.FullName
            Target     = $target
            Status     = 'Pending'
            Reason     = $null
            Duration   = [timespan]::Zero
        }
        $results.Add($record)

        if (-not $Force -and [System.IO.Directory]::Exists($target)) {
            $existing = @([System.IO.Directory]::EnumerateFileSystemEntries($target) | Select-Object -First 1)
            if ($existing.Count -gt 0) {
                $record.Status = 'Skipped'
                $record.Reason = 'Target folder already populated. Use -Force to re-extract.'
                Write-OpsxLog "Skipping $($archive.Name): already extracted." -Level Detail
                continue
            }
        }

        $canExtract = $hasSevenZip -or ($archive.Extension -in $script:NativeArchiveExtensions)
        if (-not $canExtract) {
            $record.Status = 'Skipped'
            $record.Reason = "$($archive.Extension) requires the 7Zip4PowerShell module."
            Write-OpsxLog "Skipping $($archive.Name): $($record.Reason)" -Level Warning
            continue
        }

        if (-not $Cmdlet.ShouldProcess($archive.FullName, "Extract to $target")) {
            $record.Status = 'Skipped'
            $record.Reason = 'Declined by ShouldProcess.'
            continue
        }

        $start = [datetime]::Now
        try {
            Write-OpsxLog "Extracting $($archive.Name)..." -Level Info

            if ($hasSevenZip) {
                Expand-7Zip -ArchiveFileName $archive.FullName -TargetPath $target -ErrorAction Stop
            } else {
                Expand-Archive -LiteralPath $archive.FullName -DestinationPath $target -Force -ErrorAction Stop
            }

            $record.Status = 'Extracted'
            $record.Duration = [datetime]::Now - $start
            Write-OpsxLog "Extracted $($archive.Name) in $($record.Duration.ToString('mm\:ss'))" -Level Success
        } catch {
            $record.Status = 'Failed'
            $record.Reason = $_.Exception.Message
            $record.Duration = [datetime]::Now - $start
            Write-OpsxLog "Failed to extract $($archive.Name): $($record.Reason)" -Level Error
        }
    }

    Write-Progress -Id $script:ParentProgressId -Activity 'Extracting archives' -Completed
    return $results
}
