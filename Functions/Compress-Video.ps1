<#
.SYNOPSIS
    Compresses video files using FFmpeg with configurable quality and output settings.

.DESCRIPTION
    Wrapper for FFmpeg to batch compress videos. Includes validation, logging, 
    and safe file handling. optimized for x265 compression.

.EXAMPLE
    .\Compress-Video.ps1 -InputFilePath "C:\Videos" -Recurse
#>

#region Configuration
$script:Config = @{
    DefaultExtensions = @(".avi", ".flv", ".mp4", ".mov", ".mkv", ".wmv", ".ts", ".m4v")
    # Changed preset to 'medium' for better speed/size balance. 
    # Changed audio to AAC to ensure container compatibility.
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
    LogDirectory = Join-Path $PSScriptRoot "logs"
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
                Write-Error "Parent directory does not exist: $parentDir"
                return $false
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

        # Get all files and filter by extension in memory to handle multiple extensions cleanly
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
        [string]$CustomPath
    )
    
    process {
        if ($CustomPath) {
            # If CustomPath is a directory, append filename
            if (Test-Path $CustomPath -PathType Container) {
                return Join-Path $CustomPath ($File.BaseName + "_compressed.mp4")
            }
            # If CustomPath looks like a file (ends in mp4), use it
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
            # Dynamic Argument Replacement
            # We clone the array to avoid modifying the global config reference
            $cmdArgs = $FFmpegArgs.Clone()

            if ($cmdArgs -contains '{INPUT}') {
                $idx = $cmdArgs.IndexOf('{INPUT}')
                $cmdArgs[$idx] = $InputFile.FullName
            }
            # Fallback for old default config or custom args without placeholder
            elseif ($cmdArgs[1] -match 'input\.') { 
                 $cmdArgs[1] = $InputFile.FullName
            }

            if ($cmdArgs -contains '{OUTPUT}') {
                $idx = $cmdArgs.IndexOf('{OUTPUT}')
                $cmdArgs[$idx] = $OutputPath
            }
            # Fallback for old default config
            elseif ($cmdArgs[-1] -match 'output\.') {
                $cmdArgs[-1] = $OutputPath
            }

            Write-Verbose "Executing: ffmpeg $cmdArgs"
            
            # Using Start-Process to hide the console window or capture streams if needed later
            # For now, running directly allows user to see FFmpeg progress bar
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
        if (-not $Result.Success) { return $null }

        $orig = $Result.InputFile.Length
        $new  = $Result.OutputFile.Length
        
        [PSCustomObject]@{
            FileName       = $Result.InputFile.Name
            OriginalSizeMB = [Math]::Round($orig / 1MB, 2)
            NewSizeMB      = [Math]::Round($new / 1MB, 2)
            SavingsPercent = [Math]::Round(($orig - $new) / $orig * 100, 2)
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
        $resolvedInput = $InputFilePath
        if (Test-Path $InputFilePath) {
            $resolvedInput = (Resolve-Path $InputFilePath).Path
        }

        # 1. Gather Files
        Write-Host "Scanning for videos..." -ForegroundColor Cyan
        $videosToProcess = Get-VideoFiles -Path $resolvedInput -Recurse:$Recurse -Extensions $Extensions

        if ($videosToProcess.Count -eq 0) {
            Write-Warning "No video files found in $resolvedInput"
            Stop-Transcript
            return
        }

        # 2. List and Confirm
        Write-Host "`nFound $($videosToProcess.Count) files:" -ForegroundColor Yellow
        $videosToProcess | Select-Object -First 10 | ForEach-Object { Write-Host " - $($_.Name)" }
        if ($videosToProcess.Count -gt 10) { Write-Host " ... and $($videosToProcess.Count - 10) more." }

        # Use $PSCmdlet.ShouldProcess to handle -WhatIf and Confirmation
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

                # Skip if already compressed
                if (Test-AlreadyCompressed -File $video) {
                    Write-Verbose "Skipping $($video.Name) (Already compressed)"
                    continue
                }

                # Calculate Output Path
                try {
                    $destPath = New-CompressedPath -File $video -CustomPath $OutputFilePath
                    
                    if (Test-Path $destPath) {
                        Write-Warning "Output file already exists: $destPath. Skipping."
                        continue
                    }

                    if (-not (Test-OutputPath -Path $destPath)) { continue }

                    Write-Host "`nConverting: $($video.Name)" -ForegroundColor Cyan
                    
                    # Run Compression
                    $result = Invoke-FFmpeg -InputFile $video -OutputPath $destPath -FFmpegArgs $FFmpegArgs -DeleteSource:$DeleteSource

                    # Calculate Stats
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
            Write-Host "`n--- Summary ---" -ForegroundColor Cyan
            $stats | Format-Table -AutoSize
            
            if ($stats.Count -gt 0) {
                $totalSaved = ($stats | Measure-Object -Property SavingsPercent -Average).Average
                Write-Host "Average Space Saved: $([Math]::Round($totalSaved, 2))%" -ForegroundColor Green
            }
        } else {
            Write-Warning "Operation Cancelled."
        }

        Stop-Transcript
    }
}
#endregion