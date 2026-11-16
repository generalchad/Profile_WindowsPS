function Optimize-PSX {
    <#
    .SYNOPSIS
        Extracts disc image archives and compresses the images into CHD files.
    .DESCRIPTION
        Processes folders, archives or individual disc images in three phases:

          1. Extraction  archives are expanded into sibling folders
          2. Conversion   images are compressed to CHD with chdman
          3. Cleanup      sources of verified conversions are removed on request

        Targets may be mixed freely in one run. A folder is walked recursively;
        an archive is expanded and its contents treated as a folder; a disc
        image is converted on its own. Track files are resolved to the sheet
        that describes the disc, since compressing a payload in isolation would
        drop the remaining tracks. A track file with no sheet beside it cannot
        be converted and is reported instead.

        Conversions run as several concurrent chdman processes sized from a CPU
        budget, with each process given its own worker thread count. On
        rotational media concurrency is reduced to one to avoid head contention.

        One directory walk serves all phases. Conversion inputs are the disc
        sheets (.cue/.gdi/.ccd) plus any ISO not already described by a sheet, so
        each disc is converted exactly once and no track file is compressed in
        isolation.

        Each conversion writes to a temporary file that is promoted only after
        chdman exits cleanly with a non-empty result. Cleanup, when requested,
        re-verifies the CHD before removing anything and routes deletions through
        the Recycle Bin unless -PermanentDelete is specified.

        Requires chdman from the MAME tools. 7Zip4PowerShell is required for
        archives other than .zip.
    .PARAMETER Path
        One or more targets: a folder, an archive, or a disc image

          Folder    walked recursively for archives and images
          Archive   expanded into a sibling folder, then converted
          Image     .cue/.gdi/.ccd converted with its tracks, or a stand-alone
                    .iso converted directly

        A track file (.bin/.img and friends) is resolved to the sheet that
        describes it, either by base name or by being referenced by exactly one
        sheet in the same folder. A .chd target is ignored as already converted.
        Defaults to the current location.
    .PARAMETER SkipExtraction
        Do not expand archives; convert existing images only.
    .PARAMETER SkipConversion
        Expand archives but do not convert. Useful for staging a library.
    .PARAMETER RemoveImages
        Delete source images whose CHD was created and verified.
    .PARAMETER RemoveArchives
        Delete archives whose extracted images converted successfully.
    .PARAMETER PermanentDelete
        Bypass the Recycle Bin during cleanup.
    .PARAMETER RepairCueSheets
        Repair unambiguous single-track cue sheets whose data file reference does
        not resolve, and strip byte order marks that chdman rejects. A .bak copy
        is taken before any change. Multi-track sheets are never modified.
    .PARAMETER CpuBudget
        Percentage of logical processors to occupy. Defaults to 50.
    .PARAMETER MaxConcurrency
        Explicit number of simultaneous chdman processes, overriding the budget.
    .PARAMETER ThreadsPerJob
        Explicit --numprocessors value for each chdman process.
    .PARAMETER Sequential
        Run one conversion at a time using the full thread budget.
    .PARAMETER IgnoreDiskType
        Do not reduce concurrency on rotational media.
    .PARAMETER Compression
        Explicit chdman codec chain, for example cdlz,cdzl,cdfl. Omit for
        chdman's own defaults.
    .PARAMETER Force
        Overwrite existing CHD files and re-extract populated archive folders.
    .PARAMETER ChdmanPath
        Path to chdman, or a command name resolved through PATH.
    .PARAMETER LogFile
        Write a full transcript to this path.
    .PARAMETER Verbosity
        Console detail level: Minimal, Normal or Detailed.
    .PARAMETER PassThru
        Emit the result object to the pipeline.
    .EXAMPLE
        Optimize-PSX -Path 'D:\Games\PSX'

        Converts every image under the folder using half the available CPU,
        leaving sources in place.
    .EXAMPLE
        Optimize-PSX -Path 'D:\Games\PSX' -RemoveImages -RemoveArchives -CpuBudget 75

        Extracts, converts at a higher CPU budget, then recycles the sources of
        verified conversions.
    .EXAMPLE
        Optimize-PSX -Path 'D:\Games\Ridge Racer.cue' -RemoveImages

        Converts one disc image, then recycles the sheet and its track files
        once the CHD is verified.
    .EXAMPLE
        Get-ChildItem -Path 'D:\Downloads\*.7z' | Optimize-PSX -RemoveArchives

        Extracts each archive in turn, converts what it contained, then removes
        the archive.
    .EXAMPLE
        Optimize-PSX -Path 'D:\Games\PS2' -Compression cdlz,cdzl,cdfl -ThreadsPerJob 4 -WhatIf

        Shows the plan, including per-image chdman command selection, without
        converting anything.
    .OUTPUTS
        Optimize-PSX.Result when -PassThru is specified.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [string[]]$Path = $PWD.ProviderPath,

        [switch]$SkipExtraction,

        [switch]$SkipConversion,

        [switch]$RemoveImages,

        [switch]$RemoveArchives,

        [switch]$PermanentDelete,

        [switch]$RepairCueSheets,

        [ValidateRange(1, 100)]
        [int]$CpuBudget = 50,

        [ValidateRange(0, 64)]
        [int]$MaxConcurrency = 0,

        [ValidateRange(0, 64)]
        [int]$ThreadsPerJob = 0,

        [switch]$Sequential,

        [switch]$IgnoreDiskType,

        [string[]]$Compression,

        [switch]$Force,

        [string]$ChdmanPath = 'chdman',

        [string]$LogFile,

        [ValidateSet('Minimal', 'Normal', 'Detailed')]
        [string]$Verbosity = 'Normal',

        [switch]$PassThru
    )

    begin {
        $moduleVersion = (Get-Module -Name Optimize-PSX).Version.ToString()
        Initialize-OpsxLog -LogFile $LogFile -Verbosity $Verbosity -Version $moduleVersion

        # Codecs are validated here so a typo fails in milliseconds rather than
        # after the first chdman process rejects the chain.
        if ($Compression) {
            $invalid = @($Compression | Where-Object { $_ -notin $script:ValidCodecs })
            if ($invalid.Count -gt 0) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new("Unknown compression codec(s): $($invalid -join ', '). Valid codecs: $($script:ValidCodecs -join ', ')"),
                    'InvalidCompressionCodec',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $null
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }

        $chdman = $null
        if (-not $SkipConversion) {
            $chdman = Resolve-ChdmanBinary -Path $ChdmanPath
            if (-not $chdman.Found) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.FileNotFoundException]::new("$($chdman.Error) Install the MAME tools and add chdman to PATH, or pass -ChdmanPath."),
                    'ChdmanNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $null
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            $versionText = if ($chdman.Version) { "v$($chdman.Version)" } else { 'version unknown' }
            Write-OpsxLog "Using chdman $versionText at $($chdman.Path)" -Level Detail
        }

        $startTime = [datetime]::Now
        $targets = [System.Collections.Generic.List[pscustomobject]]::new()
    }

    process {
        foreach ($item in $Path) {
            $target = Resolve-OpsxTarget -Path $item

            if ($target.Status -eq 'NotFound') {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Management.Automation.ItemNotFoundException]::new($target.Message),
                    'PathNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $item
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
                return
            }

            # Targets are collected across the whole pipeline so that a batch of
            # files shares one plan, one progress bar and one summary.
            $targets.Add($target)
        }
    }

    end {
        if ($targets.Count -eq 0) { return }

        Write-OpsxLog "Optimize-PSX v$moduleVersion" -Level Info -Phase

        $directories = [System.Collections.Generic.List[string]]::new()
        $includeFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $folderTargets = 0
        $fileTargets = 0

        foreach ($target in $targets) {
            switch ($target.Status) {
                'Directory' {
                    $directories.Add($target.Path)
                    $folderTargets++
                    Write-OpsxLog "Target folder: $($target.Path)" -Level Info
                }
                'Archive' {
                    $includeFiles.AddRange($target.Files)
                    $fileTargets++
                    Write-OpsxLog "Target archive: $($target.Path)" -Level Info
                }
                'DiscImage' {
                    $includeFiles.AddRange($target.Files)
                    $fileTargets++
                    Write-OpsxLog "Target image: $($target.Path)" -Level Info
                    if ($target.Message) { Write-OpsxLog $target.Message -Level Detail }
                }
                default {
                    Write-OpsxLog "Ignoring '$($target.Path)': $($target.Message)" -Level Warning
                }
            }
        }

        if ($directories.Count -eq 0 -and $includeFiles.Count -eq 0) {
            Write-OpsxLog 'No usable target was supplied; nothing to do.' -Level Warning
            return
        }

        if ($SkipExtraction) {
            foreach ($target in @($targets | Where-Object { $_.Status -eq 'Archive' })) {
                Write-OpsxLog "Extraction is skipped, so '$([System.IO.Path]::GetFileName($target.Path))' will not be converted." -Level Warning
            }
        }

        $index = Get-OpsxFileIndex -Path $directories -IncludeFile $includeFiles
        $initialBytes = $index.TotalBytes
        Write-OpsxLog "Indexed $($index.Count) file(s), $(Format-OpsxSize $initialBytes)" -Level Info

        # --- Extraction -------------------------------------------------
        $extractions = @()
        if (-not $SkipExtraction) {
            $extractions = @(Expand-OpsxArchive -Index $index -Force:$Force -Cmdlet $PSCmdlet)

            # Extraction adds files the conversion phase must see. A folder
            # target already covers its own archives' output; an archive target
            # needs its extraction folder walked explicitly.
            $rootsBefore = $directories.Count
            foreach ($extraction in $extractions) {
                if ($extraction.Status -eq 'Failed') { continue }
                if (-not [System.IO.Directory]::Exists($extraction.Target)) { continue }
                if (-not ($directories -contains $extraction.Target)) { $directories.Add($extraction.Target) }
            }

            if ($directories.Count -gt $rootsBefore -or
                @($extractions | Where-Object { $_.Status -eq 'Extracted' }).Count -gt 0) {
                $index = Get-OpsxFileIndex -Path $directories -IncludeFile $includeFiles
                Write-OpsxLog "Re-indexed after extraction: $($index.Count) file(s)" -Level Detail
            }
        }

        # --- Conversion -------------------------------------------------
        $jobs = @()
        if (-not $SkipConversion) {
            $plan = Get-OpsxConversionPlan -Index $index -ChdmanInfo $chdman -Force:$Force `
                                           -RepairCueSheets:$RepairCueSheets -Cmdlet $PSCmdlet

            # Media detection needs a representative path on the volume holding
            # the images; a folder target is preferred when one is present.
            $mediaProbe = if ($directories.Count -gt 0) { $directories[0] } else { $includeFiles[0].DirectoryName }

            $concurrency = Get-OpsxConcurrencyPlan -CpuBudget $CpuBudget -MaxConcurrency $MaxConcurrency `
                                                   -ThreadsPerJob $ThreadsPerJob -TargetPath $mediaProbe `
                                                   -IgnoreDiskType:$IgnoreDiskType -Sequential:$Sequential

            Show-OpsxPlan -Plan $plan -Concurrency $concurrency -Compression $Compression

            if ($plan.Jobs.Count -gt 0) {
                $jobs = @(Invoke-ChdmanBatch -Jobs $plan.Jobs -ChdmanPath $chdman.Path `
                                             -Concurrency $concurrency.Concurrency `
                                             -ThreadsPerJob $concurrency.ThreadsPerJob `
                                             -Compression $Compression -Force:$Force -Cmdlet $PSCmdlet)
            }

            # Skipped jobs are reported alongside executed ones so the summary
            # accounts for every disc that was considered.
            $jobs = @($jobs) + @($plan.Skipped)
        }

        # --- Cleanup ----------------------------------------------------
        $cleanup = $null
        if (($RemoveImages -or $RemoveArchives) -and $jobs.Count -gt 0) {
            $cleanup = Remove-OpsxSource -Jobs $jobs -Extractions $extractions `
                                         -RemoveImages:$RemoveImages -RemoveArchives:$RemoveArchives `
                                         -Permanent:$PermanentDelete -Cmdlet $PSCmdlet
        }

        # --- Report -----------------------------------------------------
        # A folder target picks up the CHDs it produced by walking. A file
        # target does not, so they are added explicitly and deduplicated.
        $finalFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $finalFiles.AddRange($includeFiles)
        foreach ($job in $jobs) {
            if ($job.Status -eq 'Converted' -and [System.IO.File]::Exists($job.OutputPath)) {
                $finalFiles.Add([System.IO.FileInfo]::new($job.OutputPath))
            }
        }

        $finalIndex = Get-OpsxFileIndex -Path $directories -IncludeFile $finalFiles

        $scopeLabel = if ($fileTargets -eq 0) {
            'Folder'
        } elseif ($folderTargets -eq 0) {
            'Target'
        } else {
            'Scope'
        }

        $result = Write-OpsxSummary -Jobs $jobs -Extractions $extractions -Cleanup $cleanup `
                                    -InitialBytes $initialBytes -FinalBytes $finalIndex.TotalBytes `
                                    -Duration ([datetime]::Now - $startTime) `
                                    -ScopeLabel $scopeLabel `
                                    -WhatIfMode:$WhatIfPreference

        if ($PassThru) { Write-Output $result }
    }
}
