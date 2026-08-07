function Compress-Video {
    <#
    .SYNOPSIS
        Compresses video files using FFmpeg with configurable quality,
        hardware acceleration, and throttled parallel execution.

    .DESCRIPTION
        Batch compresses videos with:
          - Optional GPU hardware acceleration (NVENC/QSV/AMF), auto-detected
          - Resume/skip detection via ffprobe duration comparison, so a
            re-run after an interruption doesn't redo finished work
          - Throttled parallel execution (PowerShell 7 ForEach-Object
            -Parallel) with a safe, conservative default so compression
            never saturates the machine
          - Reduced process priority for every spawned ffmpeg job
          - Persistent JSON configuration via Get-/Set-CompressVideoConfig

        ThrottleLimit resolution when not explicitly supplied:
          - 1 concurrent job for CPU encoding (libx265)
          - 2 concurrent jobs when a GPU encoder is resolved
        This can always be overridden explicitly with -ThrottleLimit.

    .PARAMETER InputFilePath
        File or directory to process. Defaults to the current location.

    .PARAMETER OutputFilePath
        Custom output file (single input) or directory (batch mode).

    .PARAMETER DeleteSource
        Deletes the source file after a successful, verified compression.

    .PARAMETER Recurse
        Recurse into subdirectories when InputFilePath is a directory.

    .PARAMETER SkipLog
        Disables transcript logging for this run.

    .PARAMETER Extensions
        Video extensions to consider. Defaults to the configured value.

    .PARAMETER HardwareAccel
        'Auto' (default), 'None', 'NVENC', 'QSV', or 'AMF'.

    .PARAMETER ThrottleLimit
        Number of ffmpeg jobs to run simultaneously. See resolution
        rules above. Explicit 0 or omission triggers auto-resolution.

    .PARAMETER Priority
        Process priority for spawned ffmpeg jobs: Idle, BelowNormal
        (default), or Normal.

    .PARAMETER Crf
        Encoder quality value. Lower = higher quality/larger file.

    .PARAMETER Preset
        Encoder speed/quality preset.

    .PARAMETER Force
        Re-encode even if a valid compressed output already exists.

    .EXAMPLE
        Compress-Video -InputFilePath "C:\Videos" -Recurse

    .EXAMPLE
        Compress-Video -InputFilePath "C:\Videos" -HardwareAccel NVENC -ThrottleLimit 2

    .EXAMPLE
        "C:\Videos1", "C:\Videos2" | Compress-Video -Recurse
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias("Path", "p")]
        [string]$InputFilePath = (Get-Location).Path,

        [Parameter(Position = 1)]
        [Alias("Output", "o")]
        [string]$OutputFilePath,

        [Parameter()]
        [Alias("Delete", "del")]
        [switch]$DeleteSource,

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [switch]$SkipLog,

        [Parameter()]
        [string[]]$Extensions,

        [Parameter()]
        [ValidateSet('Auto', 'None', 'NVENC', 'QSV', 'AMF')]
        [string]$HardwareAccel,

        [Parameter()]
        [int]$ThrottleLimit,

        [Parameter()]
        [ValidateSet('Idle', 'BelowNormal', 'Normal')]
        [string]$Priority,

        [Parameter()]
        [int]$Crf,

        [Parameter()]
        [string]$Preset,

        [Parameter()]
        [switch]$Force
    )

    begin {
        $config = Get-CompressVideoConfigInternal

        $effectiveExtensions = if ($PSBoundParameters.ContainsKey('Extensions')) { $Extensions } else { $config['DefaultExtensions'] }
        $effectiveHwAccel    = if ($PSBoundParameters.ContainsKey('HardwareAccel')) { $HardwareAccel } else { $config['HardwareAccel'] }
        $effectivePriority   = if ($PSBoundParameters.ContainsKey('Priority')) { $Priority } else { $config['Priority'] }
        $effectiveCrf        = if ($PSBoundParameters.ContainsKey('Crf')) { $Crf } else { [int]$config['Crf'] }
        $effectivePreset     = if ($PSBoundParameters.ContainsKey('Preset')) { $Preset } else { $config['Preset'] }
        $effectiveAudioCodec   = $config['AudioCodec']
        $effectiveAudioBitrate = $config['AudioBitrate']
        $effectiveSkipLog      = if ($PSBoundParameters.ContainsKey('SkipLog')) { [bool]$SkipLog } else { [bool]$config['SkipLog'] }
        $tolerance             = [double]$config['ResumeDurationTolerance']

        if (-not (Test-FFTools)) { return }

        $encoderInfo = Get-HardwareEncoder -HardwareAccel $effectiveHwAccel
        $encoderLabel = if ($encoderInfo.IsHardware) { "GPU hardware encoder" } else { "CPU software encoder" }
        Write-Host "Encoder selected: $($encoderInfo.Encoder) ($encoderLabel)" -ForegroundColor Magenta
        Write-Verbose "Resolved encoder: $($encoderInfo.Encoder) (hardware: $($encoderInfo.IsHardware))"

        # Resolve ThrottleLimit: explicit param > saved config > auto default.
        if ($PSBoundParameters.ContainsKey('ThrottleLimit') -and $ThrottleLimit -gt 0) {
            $effectiveThrottle = $ThrottleLimit
        } elseif ($config['ThrottleLimit']) {
            $effectiveThrottle = [int]$config['ThrottleLimit']
        } else {
            $effectiveThrottle = if ($encoderInfo.IsHardware) { 2 } else { 1 }
        }
        Write-Verbose "Resolved ThrottleLimit: $effectiveThrottle"

        # Initialize Logging ONCE for the entire pipeline
        $script:LoggingActive = $false
        if (-not $effectiveSkipLog) {
            try {
                $logDir = Join-Path $script:ConfigDirectory "logs"
                if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
                $logFile = Join-Path $logDir "CompressVideo_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

                Start-Transcript -Path $logFile -Append -IncludeInvocationHeader -ErrorAction SilentlyContinue
                $script:LoggingActive = $true
            } catch {
                Write-Warning "Could not start transcript. Logging disabled."
            }
        }

        $pipelineStats = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        try {
            $resolvedInput = (Resolve-Path $InputFilePath -ErrorAction Stop).Path
        } catch {
            Write-Error "Invalid or missing input path: $InputFilePath"
            return
        }

        Write-Host "`nScanning for videos in $resolvedInput..." -ForegroundColor Cyan
        $videosToProcess = @(Get-VideoFiles -Path $resolvedInput -Recurse:$Recurse -Extensions $effectiveExtensions)

        if ($videosToProcess.Count -eq 0) {
            Write-Warning "No video files found in $resolvedInput."
            return
        }

        $isBatchMode = $videosToProcess.Count -gt 1

        Write-Host "Found $($videosToProcess.Count) files:" -ForegroundColor Yellow
        $videosToProcess | Select-Object -First 10 | ForEach-Object { Write-Host " - $($_.Name)" }
        if ($videosToProcess.Count -gt 10) { Write-Host " ... and $($videosToProcess.Count - 10) more." }

        if (-not $PSCmdlet.ShouldProcess("Found $($videosToProcess.Count) videos in $resolvedInput", "Start Compression")) {
            Write-Warning "Operation Cancelled for $resolvedInput."
            return
        }

        # --- Build the work queue up front, applying skip/resume/already-compressed logic sequentially. ---
        $workItems = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($video in $videosToProcess) {
            if (Test-AlreadyCompressed -File $video) {
                Write-Verbose "Skipping $($video.Name) (Already compressed)"
                continue
            }

            $destPath = New-CompressedPath -File $video -CustomPath $OutputFilePath -IsBatchMode:$isBatchMode

            if (-not $Force) {
                $check = Test-CompressedOutput -InputPath $video.FullName -OutputPath $destPath -Tolerance $tolerance
                if ($check.Status -eq 'Complete') {
                    Write-Host "[SKIP] $($video.Name) - $($check.Reason)" -ForegroundColor DarkGray
                    continue
                }
                if ($check.Status -eq 'Invalid') {
                    Write-Warning "Existing output for $($video.Name) is incomplete/corrupt ($($check.Reason)). Re-encoding."
                }
            }

            if (-not (Test-OutputPathInternal -Path $destPath)) { continue }

            $ffArgs = Build-FFmpegArgs -InputPath $video.FullName -OutputPath $destPath -Encoder $encoderInfo.Encoder `
                                        -Crf $effectiveCrf -Preset $effectivePreset `
                                        -AudioCodec $effectiveAudioCodec -AudioBitrate $effectiveAudioBitrate

            $workItems.Add([PSCustomObject]@{
                Video      = $video
                DestPath   = $destPath
                FFmpegArgs = $ffArgs
            })
        }

        if ($workItems.Count -eq 0) {
            Write-Host "Nothing to do - all files already compressed or skipped." -ForegroundColor Green
            return
        }

        Write-Host "`nCompressing $($workItems.Count) file(s) using encoder '$($encoderInfo.Encoder)' with ThrottleLimit=$effectiveThrottle..." -ForegroundColor Cyan

        $total = $workItems.Count
        $completed = 0

        if ($effectiveThrottle -le 1 -or $total -eq 1) {
            # Sequential path: also used for a single file to avoid parallel overhead.
            foreach ($item in $workItems) {
                $completed++
                Write-Progress -Activity "Compressing Video" -Status "[$completed/$total] $($item.Video.Name)" -PercentComplete (($completed / $total) * 100)
                Write-Host "`nConverting: $($item.Video.Name)" -ForegroundColor Cyan

                $result = Invoke-FFmpegJob -InputFile $item.Video -OutputPath $item.DestPath -FFmpegArgs $item.FFmpegArgs `
                                            -Priority $effectivePriority -DeleteSource:$DeleteSource

                if ($result.Success) {
                    $metric = Get-CompressionMetrics -Result $result
                    if ($metric) {
                        $pipelineStats.Add($metric)
                        Write-Host " [OK] Saved $($metric.SavingsPercent)%" -ForegroundColor Green
                    }
                } else {
                    Write-Error "Failed to process $($item.Video.Name): $($result.Error)"
                }
            }
        } else {
            # Parallel path (PS 7+ ForEach-Object -Parallel). Each branch is self
            # contained: it dot-sources nothing shared/mutable, avoiding the
            # classic -Parallel scoping pitfalls, and returns a result object
            # consumed back on the main thread for stats/progress.
            $priorityArg = $effectivePriority
            $deleteArg   = [bool]$DeleteSource

            $results = $workItems | ForEach-Object -ThrottleLimit $effectiveThrottle -Parallel {
                $item = $_
                $modulePath = $using:PSScriptRoot

                # Re-import just the functions this branch needs from the parent
                # module's Private folder, since -Parallel runs in an isolated
                # runspace with a fresh module state.
                . (Join-Path $modulePath '..\Private\Invoke-FFmpegJob.ps1')

                Invoke-FFmpegJob -InputFile $item.Video -OutputPath $item.DestPath -FFmpegArgs $item.FFmpegArgs `
                                  -Priority $using:priorityArg -DeleteSource:$using:deleteArg
            }

            foreach ($result in $results) {
                $completed++
                Write-Progress -Activity "Compressing Video" -Status "[$completed/$total] $($result.InputFile.Name)" -PercentComplete (($completed / $total) * 100)

                if ($result.Success) {
                    $metric = Get-CompressionMetrics -Result $result
                    if ($metric) {
                        $pipelineStats.Add($metric)
                        Write-Host "[OK] $($result.InputFile.Name) - Saved $($metric.SavingsPercent)%" -ForegroundColor Green
                    }
                } else {
                    Write-Error "Failed to process $($result.InputFile.Name): $($result.Error)"
                }
            }
        }
    }

    end {
        Write-CompressionSummary -Stats $pipelineStats

        if ($script:LoggingActive) {
            Stop-Transcript -ErrorAction SilentlyContinue
        }
    }
}
