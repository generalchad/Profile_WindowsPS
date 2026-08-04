function Optimize-PSX {
    <#
    .SYNOPSIS
        Extracts disc image archives and compresses the images into CHD files.
    .DESCRIPTION
        Processes a folder of disc images in three phases:

          1. Extraction  archives are expanded into sibling folders
          2. Conversion   images are compressed to CHD with chdman
          3. Cleanup      sources of verified conversions are removed on request

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
        Folder to process. Defaults to the current location.
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
        [string]$Path = $PWD.ProviderPath,

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
                throw "Unknown compression codec(s): $($invalid -join ', '). Valid codecs: $($script:ValidCodecs -join ', ')"
            }
        }

        $chdman = $null
        if (-not $SkipConversion) {
            $chdman = Resolve-ChdmanBinary -Path $ChdmanPath
            if (-not $chdman.Found) {
                throw "$($chdman.Error) Install the MAME tools and add chdman to PATH, or pass -ChdmanPath."
            }

            $versionText = if ($chdman.Version) { "v$($chdman.Version)" } else { 'version unknown' }
            Write-OpsxLog "Using chdman $versionText at $($chdman.Path)" -Level Detail
        }
    }

    process {
        $startTime = [datetime]::Now

        try {
            $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
        } catch {
            throw "Path not found: '$Path'."
        }

        if (-not [System.IO.Directory]::Exists($resolved)) {
            throw "Path is not a directory: '$resolved'."
        }

        Write-OpsxLog "Optimize-PSX v$moduleVersion" -Level Info -Phase
        Write-OpsxLog "Target: $resolved" -Level Info

        $index = Get-OpsxFileIndex -Path $resolved
        $initialBytes = $index.TotalBytes
        Write-OpsxLog "Indexed $($index.Count) file(s), $(Format-OpsxSize $initialBytes)" -Level Info

        # --- Extraction -------------------------------------------------
        $extractions = @()
        if (-not $SkipExtraction) {
            $extractions = @(Expand-OpsxArchive -Index $index -Force:$Force -Cmdlet $PSCmdlet)

            # Extraction adds files the conversion phase must see, so the index
            # is rebuilt rather than patched.
            if (@($extractions | Where-Object { $_.Status -eq 'Extracted' }).Count -gt 0) {
                $index = Get-OpsxFileIndex -Path $resolved
                Write-OpsxLog "Re-indexed after extraction: $($index.Count) file(s)" -Level Detail
            }
        }

        # --- Conversion -------------------------------------------------
        $jobs = @()
        if (-not $SkipConversion) {
            $plan = Get-OpsxConversionPlan -Index $index -ChdmanInfo $chdman -Force:$Force `
                                           -RepairCueSheets:$RepairCueSheets -Cmdlet $PSCmdlet

            $concurrency = Get-OpsxConcurrencyPlan -CpuBudget $CpuBudget -MaxConcurrency $MaxConcurrency `
                                                   -ThreadsPerJob $ThreadsPerJob -TargetPath $resolved `
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
        $finalIndex = Get-OpsxFileIndex -Path $resolved
        $result = Write-OpsxSummary -Jobs $jobs -Extractions $extractions -Cleanup $cleanup `
                                    -InitialBytes $initialBytes -FinalBytes $finalIndex.TotalBytes `
                                    -Duration ([datetime]::Now - $startTime) `
                                    -WhatIfMode:$WhatIfPreference


        if ($PassThru) { Write-Output $result }
    }
}
