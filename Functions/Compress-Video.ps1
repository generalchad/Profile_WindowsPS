<#
.SYNOPSIS
    Compresses video files using FFmpeg with configurable quality and output settings.

.DESCRIPTION
    Wrapper for FFmpeg to batch compress videos. Includes validation, logging,
    and safe file handling. Optimized for x265 compression.

.EXAMPLE
    .\Compress-Video.ps1 -InputFilePath "C:\Videos" -Recurse
#>

#region Configuration
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

$script:Config = @{
    DefaultExtensions = @(".avi", ".flv", ".mp4", ".mov", ".mkv", ".wmv", ".ts", ".m4v")
    DefaultFFmpegArgs = @(
        '-i', '{INPUT}',
        '-c:v', 'libx265',
        '-crf', '28',
        '-preset', 'medium',
        '-c:a', 'aac',
        '-b:a', '128k',
        '{OUTPUT}'
    )
    MaxPathLength = 260
    MaxFileNameLength = 255
    LogDirectory = Join-Path $scriptDir "logs"
}
#endregion

#region Validation Functions
function Test-FFmpeg {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    process {
        if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
            return $true
        }
        Write-Error "FFmpeg is not installed or not in the system's PATH."
        return $false
    }
}

function Test-OutputPath {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path
    )

    begin {
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    }

    process {
        try {
            if ($Path.Length -gt 260) {
                Write-Error "Path exceeds maximum length (260 characters): $Path"
                return $false
            }

            $parentDir = Split-Path -Path $Path -Parent
            if (-not (Test-Path -Path $parentDir -PathType Container)) {
                # Attempt to create the parent directory if it doesn't exist
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }

            $fileName = Split-Path -Path $Path -Leaf
            if ($fileName.IndexOfAny($invalidChars) -ge 0) {
                Write-Error "Filename contains invalid characters: $fileName"
                return $false
            }

            return $true
        }
        catch {
            Write-Error "Error testing path: $_"
            return $false
        }
    }
}

function Test-AlreadyCompressed {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File
    )

    process {
        return $File.BaseName -match '_compressed$'
    }
}
#endregion

#region Path Management
function Get-VideoFiles {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string[]]$Extensions = $script:Config.DefaultExtensions,

        [Parameter()]
        [switch]$Recurse
    )

    process {
        if (Test-Path $Path -PathType Leaf) {
            return (Get-Item -Force $Path)
        }

        $searchParams = @{
            Path        = $Path
            File        = $true
            Force       = $true
            Recurse     = $Recurse
            ErrorAction = 'SilentlyContinue'
        }

        Get-ChildItem @searchParams |
            Where-Object { $Extensions -contains $_.Extension.ToLower() }
    }
}

function New-CompressedPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter()]
        [string]$CustomPath,

        [Parameter()]
        [switch]$IsBatchMode
    )

    process {
        if ($CustomPath) {
            # If processing multiple files, treat CustomPath strictly as a directory
            if ($IsBatchMode) {
                return Join-Path $CustomPath ($File.BaseName + "_compressed.mp4")
            }

            if (Test-Path $CustomPath -PathType Container) {
                return Join-Path $CustomPath ($File.BaseName + "_compressed.mp4")
            }
            if ($CustomPath -match '\.mp4$') {
                return $CustomPath
            }
            return Join-Path $CustomPath ($File.BaseName + "_compressed.mp4")
        }

        $baseName = $File.BaseName
        if (-not (Test-AlreadyCompressed -File $File)) {
            $baseName += "_compressed"
        }

        return Join-Path $File.DirectoryName "${baseName}.mp4"
    }
}
#endregion

#region FFmpeg Operations
function Invoke-FFmpeg {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$InputFile,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [string[]]$FFmpegArgs = $script:Config.DefaultFFmpegArgs,

        [switch]$DeleteSource
    )

    process {
        try {
            # Safely replace placeholders without using Array.IndexOf
            $cmdArgs = foreach ($arg in $FFmpegArgs) {
                if ($arg -eq '{INPUT}') {
                    $InputFile.FullName
                } elseif ($arg -eq '{OUTPUT}') {
                    $OutputPath
                } else {
                    $arg
                }
            }

            Write-Verbose "Executing: ffmpeg $cmdArgs"

            # Execute FFmpeg natively
            & ffmpeg $cmdArgs

            if ($LASTEXITCODE -eq 0) {
                $outputItem = Get-Item $OutputPath -ErrorAction SilentlyContinue

                if ($DeleteSource -and $outputItem) {
                    Remove-Item $InputFile.FullName -Force
                    Write-Verbose "Deleted source: $($InputFile.FullName)"
                }

                return [PSCustomObject]@{
                    Success    = $true
                    InputFile  = $InputFile
                    OutputFile = $outputItem
                }
            } else {
                throw "FFmpeg exited with code $LASTEXITCODE"
            }
        }
        catch {
            Write-Error "FFmpeg failed: $_"
            return [PSCustomObject]@{
                Success   = $false
                InputFile = $InputFile
                Error     = $_
            }
        }
    }
}

function Get-CompressionMetrics {
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
#endregion

#region Main Process
function Compress-Video {
    <#
    .SYNOPSIS
        Compresses video files using FFmpeg.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias("Path", "p")]
        [ValidateScript({ Test-Path $_ })]
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
        [string[]]$Extensions = $script:Config.DefaultExtensions,

        [Parameter()]
        [string[]]$FFmpegArgs = $script:Config.DefaultFFmpegArgs
    )

    process {
        if (-not (Test-FFmpeg)) { return }

        # Setup Logging
        $logDir = $script:Config.LogDirectory
        if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
        $logFile = Join-Path $logDir "CompressVideo_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

        try {
            Start-Transcript -Path $logFile -Append -IncludeInvocationHeader -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Could not start transcript. Logging disabled."
        }

        # Resolve Input
        $resolvedInput = (Resolve-Path $InputFilePath).Path

        # 1. Gather Files (Forced as array)
        Write-Host "Scanning for videos..." -ForegroundColor Cyan
        $videosToProcess = @(Get-VideoFiles -Path $resolvedInput -Recurse:$Recurse -Extensions $Extensions)

        if ($videosToProcess.Count -eq 0) {
            Write-Warning "No video files found in $resolvedInput"
            Stop-Transcript -ErrorAction SilentlyContinue
            return
        }

        $isBatchMode = $videosToProcess.Count -gt 1

        # 2. List and Confirm
        Write-Host "`nFound $($videosToProcess.Count) files:" -ForegroundColor Yellow
        $videosToProcess | Select-Object -First 10 | ForEach-Object { Write-Host " - $($_.Name)" }
        if ($videosToProcess.Count -gt 10) { Write-Host " ... and $($videosToProcess.Count - 10) more." }

        if ($PSCmdlet.ShouldProcess("Found $($videosToProcess.Count) videos", "Start Compression")) {

            $stats = @()
            $counter = 0

            foreach ($video in $videosToProcess) {
                $counter++
                $progress = @{
                    Activity = "Compressing Video ($counter / $($videosToProcess.Count))"
                    Status   = "Processing: $($video.Name)"
                    PercentComplete = ($counter / $videosToProcess.Count) * 100
                }
                Write-Progress @progress

                if (Test-AlreadyCompressed -File $video) {
                    Write-Verbose "Skipping $($video.Name) (Already compressed)"
                    continue
                }

                try {
                    $destPath = New-CompressedPath -File $video -CustomPath $OutputFilePath -IsBatchMode:$isBatchMode

                    if (Test-Path $destPath) {
                        Write-Warning "Output file already exists: $destPath. Skipping."
                        continue
                    }

                    if (-not (Test-OutputPath -Path $destPath)) { continue }

                    Write-Host "`nConverting: $($video.Name)" -ForegroundColor Cyan

                    $result = Invoke-FFmpeg -InputFile $video -OutputPath $destPath -FFmpegArgs $FFmpegArgs -DeleteSource:$DeleteSource

                    $metric = Get-CompressionMetrics -Result $result
                    if ($metric) {
                        $stats += $metric
                        Write-Host " [OK] Saved $($metric.SavingsPercent)%" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Error "Failed to process $($video.Name): $_"
                }
            }

            # Summary
            if ($stats.Count -gt 0) {
                Write-Host "`n--- Summary ---" -ForegroundColor Cyan
                $stats | Format-Table -AutoSize

                $totalSaved = ($stats | Measure-Object -Property SavingsPercent -Average).Average
                Write-Host "Average Space Saved: $([Math]::Round($totalSaved, 2))%" -ForegroundColor Green
            } else {
                Write-Host "`nNo files were successfully compressed." -ForegroundColor Yellow
            }
        } else {
            Write-Warning "Operation Cancelled."
        }

        Stop-Transcript -ErrorAction SilentlyContinue
    }
}
#endregion
