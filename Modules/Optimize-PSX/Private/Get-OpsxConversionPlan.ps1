function Get-OpsxConversionPlan {
    <#
    .SYNOPSIS
        Builds the list of conversion jobs from a file index.
    .DESCRIPTION
        Selects one input per disc and records the chdman subcommand, output
        path and dependency set for each.

        Selection rules:

          Sheets (.cue/.gdi/.ccd) are always preferred. A sheet describes the
          complete disc including audio tracks and subchannel data.

          An .iso is a job only when no sheet in the same directory shares its
          base name. A sheet's payload must never also be queued as its own job,
          which would produce a duplicate CHD missing every other track.

          Track files (.bin/.img/.raw/.sub and friends) are never jobs. They are
          recorded as dependencies of the sheet that references them.

        ISOs at or above the DVD size threshold use createdvd when the detected
        chdman build supports it, otherwise createcd.

        Cue sheets are parsed during planning so unresolved references surface
        before any process is launched. Jobs whose sheet cannot be satisfied are
        marked Skip with a reason and never reach the batch runner.

        Jobs are ordered largest first. With several workers this keeps every
        slot busy to the end of the batch, rather than finishing with one long
        job running alone.
    .PARAMETER Index
        A file index from Get-OpsxFileIndex.
    .PARAMETER ChdmanInfo
        Binary information from Resolve-ChdmanBinary, used for DVD support.
    .PARAMETER Force
        Queue jobs whose output CHD already exists, overwriting it.
    .PARAMETER RepairCueSheets
        Attempt repair of unresolved single-track cue sheets during planning.
    .PARAMETER Cmdlet
        Calling $PSCmdlet, required when RepairCueSheets is set.
    .OUTPUTS
        PSCustomObject:
          Jobs      List of job objects with Action 'Convert'
          Skipped   List of job objects with Action 'Skip' and a Reason
          TotalBytes  combined source size of queued jobs
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [pscustomobject]$Index,

        [Parameter(Mandatory)]
        [pscustomobject]$ChdmanInfo,

        [switch]$Force,

        [switch]$RepairCueSheets,

        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $jobs = [System.Collections.Generic.List[pscustomobject]]::new()
    $skipped = [System.Collections.Generic.List[pscustomobject]]::new()

    # Directory + base name of every sheet, so an ISO that a sheet already
    # describes can be excluded in constant time.
    $sheetKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $sheetFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

    foreach ($ext in $script:SheetExtensions) {
        if ($Index.ByExtension.ContainsKey($ext)) {
            foreach ($file in $Index.ByExtension[$ext]) {
                $sheetFiles.Add($file)
                $null = $sheetKeys.Add([System.IO.Path]::Combine($file.DirectoryName, $file.BaseName))
            }
        }
    }

    # --- Sheet-based jobs -----------------------------------------------
    foreach ($sheet in $sheetFiles) {
        $outputPath = [System.IO.Path]::Combine($sheet.DirectoryName, "$($sheet.BaseName).chd")
        $dependencies = [System.Collections.Generic.List[string]]::new()
        $sourceBytes = [long]$sheet.Length
        $skipReason = $null

        if ($sheet.Extension -eq '.cue') {
            $cue = Read-CueSheet -Path $sheet.FullName

            if ($cue.ParseError) {
                $skipReason = $cue.ParseError
            } elseif (-not $cue.IsValid -or $cue.HasBom) {
                if ($RepairCueSheets -and $Cmdlet) {
                    $repair = Repair-CueSheet -CueSheet $cue -Cmdlet $Cmdlet
                    if ($repair.Repaired) {
                        Write-OpsxLog "Repaired $($sheet.Name): $($repair.Reason)" -Level Warning
                        $cue = Read-CueSheet -Path $sheet.FullName
                    }
                    if (-not $cue.IsValid) {
                        $skipReason = "Unresolved track reference(s): $($repair.Reason)"
                    }
                } elseif (-not $cue.IsValid) {
                    $missing = ($cue.MissingFiles.Leaf -join ', ')
                    $skipReason = "Missing track file(s): $missing. Use -RepairCueSheets to attempt a fix."
                }
            }

            foreach ($reference in $cue.FileReferences) {
                if ($reference.Exists) {
                    $dependencies.Add($reference.ResolvedPath)
                    $sourceBytes += [System.IO.FileInfo]::new($reference.ResolvedPath).Length
                }
            }
        } elseif ($sheet.Extension -eq '.gdi') {
            $gdi = Read-GdiSheet -Path $sheet.FullName
            if ($gdi.ParseError) {
                $skipReason = $gdi.ParseError
            } elseif ($gdi.MissingFiles.Count -gt 0) {
                $skipReason = "Missing track file(s): $($gdi.MissingFiles -join ', ')"
            }
            foreach ($track in $gdi.Tracks) {
                if ($track.Exists) {
                    $dependencies.Add($track.ResolvedPath)
                    $sourceBytes += [System.IO.FileInfo]::new($track.ResolvedPath).Length
                }
            }
        } else {
            # CloneCD set: the .ccd references its .img and optional .sub by
            # base name rather than by an internal FILE directive.
            foreach ($ext in $script:CcdSidecarExtensions) {
                $sidecar = [System.IO.Path]::Combine($sheet.DirectoryName, "$($sheet.BaseName)$ext")
                if ([System.IO.File]::Exists($sidecar)) {
                    $dependencies.Add($sidecar)
                    $sourceBytes += [System.IO.FileInfo]::new($sidecar).Length
                }
            }
            if ($dependencies.Count -eq 0) {
                $skipReason = 'No .img data file found beside the .ccd sheet.'
            }
        }

        $job = New-OpsxJob -Source $sheet -OutputPath $outputPath -Command $script:ChdmanCommandForSheets `
                           -Dependencies $dependencies -SourceBytes $sourceBytes

        if ($skipReason) {
            $job.Action = 'Skip'
            $job.Reason = $skipReason
            $skipped.Add($job)
            continue
        }

        if (-not $Force -and [System.IO.File]::Exists($outputPath)) {
            $job.Action = 'Skip'
            $job.Reason = 'Output CHD already exists. Use -Force to overwrite.'
            $skipped.Add($job)
            continue
        }

        $jobs.Add($job)
    }

    # --- Standalone ISO jobs --------------------------------------------
    if ($Index.ByExtension.ContainsKey('.iso')) {
        foreach ($iso in $Index.ByExtension['.iso']) {
            $key = [System.IO.Path]::Combine($iso.DirectoryName, $iso.BaseName)
            if ($sheetKeys.Contains($key)) {
                Write-OpsxLog "Skipping '$($iso.Name)': described by a sheet of the same name." -Level Detail
                continue
            }

            $isDvd = $iso.Length -ge $script:DvdSizeThreshold
            $command = if ($isDvd -and $ChdmanInfo.SupportsDvd) { 'createdvd' } else { 'createcd' }

            if ($isDvd -and -not $ChdmanInfo.SupportsDvd) {
                Write-OpsxLog "'$($iso.Name)' is DVD-sized but this chdman build lacks createdvd; using createcd." -Level Detail
            }

            $outputPath = [System.IO.Path]::Combine($iso.DirectoryName, "$($iso.BaseName).chd")

            $job = New-OpsxJob -Source $iso -OutputPath $outputPath -Command $command `
                               -Dependencies @() -SourceBytes $iso.Length

            if (-not $Force -and [System.IO.File]::Exists($outputPath)) {
                $job.Action = 'Skip'
                $job.Reason = 'Output CHD already exists. Use -Force to overwrite.'
                $skipped.Add($job)
                continue
            }

            $jobs.Add($job)
        }
    }

    # Largest first keeps every worker slot occupied until the end of the batch.
    $ordered = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($job in ($jobs | Sort-Object -Property SourceBytes -Descending)) { $ordered.Add($job) }

    [long]$total = 0
    foreach ($job in $ordered) { $total += $job.SourceBytes }

    [pscustomobject]@{
        PSTypeName = 'Optimize-PSX.ConversionPlan'
        Jobs       = $ordered
        Skipped    = $skipped
        TotalBytes = $total
    }
}
