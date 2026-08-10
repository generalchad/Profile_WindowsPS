function Rename-MediaFile {
    <#
    .SYNOPSIS
        Renames media files, subtitle sidecars and parent folders to adhere to Plex and Jellyfin naming conventions.
    .DESCRIPTION
        Analyzes file names and folder structures to extract Show, Season, Episode, Episode Title, Movie Title,
        Release Year, and Bonus feature information.

        Naming conventions enforced:
            Movies    : Movie Title (Release Year)\Movie Title (Release Year).ext
            TV Shows  : Show Title\Season #\Show Title - S##E## - Episode Title.ext
            Subtitles : <Video Base Name>.<lang>[.sdh|.forced][.n].srt

        Files that do not carry an explicit episode marker are classified as either Movie or TV content using a
        weighted heuristic scoring engine that considers sibling file counts, parent folder context, absolute
        numbering, and the presence of a standalone release year.

        Subtitle language is resolved with a three tier cascade: filename and folder tokens first, then
        encoding-aware content analysis (Unicode script detection plus weighted stop word scoring), then an
        optional interactive prompt that shows a sample of the dialogue. Detection failure never blocks a
        rename; the sidecar simply stays untagged.

        Features a safe preview mode. If run without -Force, it aggregates all changes, checks for conflicts,
        displays a full-width preview, and asks for confirmation (with an interactive per-item approval option).
    .PARAMETER TargetDirectory
        One or more directories to process. Defaults to the current location.
    .PARAMETER MediaExtensions
        Video extensions considered media files.
    .PARAMETER SubtitleExtensions
        Extensions treated as subtitle sidecars.
    .PARAMETER SkipDirectoryRename
        Leave folder names untouched.
    .PARAMETER SkipSubtitles
        Ignore subtitle files entirely.
    .PARAMETER SubtitleLanguageOnly
        Only normalise subtitle language codes. Video names, folder names and junk removal are all skipped,
        and each subtitle keeps its existing base name - just the language tag is corrected (en -> eng,
        cn -> zho, and so on). Intended for libraries that have already been organised.
    .PARAMETER NoFlattenSubtitleFolders
        Leave subtitles inside Subs\ instead of moving them beside the video.
    .PARAMETER LanguageDetection
        Auto          filename tokens, then file contents (default)
        FilenameOnly  filename tokens only, never reads file contents
        Prompt        as Auto, but asks when confidence is low or detection fails
        None          no language detection at all
    .PARAMETER DefaultSubtitleLanguage
        Language applied when detection fails. Unset by default, which leaves the sidecar untagged.
    .PARAMETER RemoveJunkFiles
        Queue known scene litter (RARBG.txt, "Downloaded from...", sample files) for removal.
        .nfo files are never treated as junk because Jellyfin and Kodi read them as metadata.
    .PARAMETER PermanentDelete
        Delete junk outright instead of sending it to the Recycle Bin.
    .PARAMETER NoPager
        Force console output mode instead of Out-GridView. When in console mode, also disables
        pagination if the output fits on screen. Useful for automation, scripting, or SSH sessions.
    .PARAMETER Force
        Apply every change without confirmation.
    .PARAMETER PassThru
        Emit an audit object per operation.
    .EXAMPLE
        Rename-MediaFile -TargetDirectory "D:\Media\TV Shows"
    .EXAMPLE
        Rename-MediaFile -TargetDirectory "D:\Media\Movies" -WhatIf
    .EXAMPLE
        Rename-MediaFile -TargetDirectory "D:\Media\Movies" -SubtitleLanguageOnly
        Corrects 2 letter and malformed subtitle language codes across an already organised library.
    .EXAMPLE
        Rename-MediaFile -TargetDirectory "D:\Media\Movies" -RemoveJunkFiles -LanguageDetection Prompt
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'Path')]
        [string[]]$TargetDirectory = $PWD.Path,

        [Parameter(Mandatory = $false)]
        [string[]]$MediaExtensions = @('.mp4', '.avi', '.mkv', '.mov', '.m4v'),

        [Parameter(Mandatory = $false)]
        [string[]]$SubtitleExtensions = @('.srt', '.ass', '.ssa', '.sub', '.idx', '.vtt', '.sup'),

        [Parameter(Mandatory = $false)]
        [switch]$SkipDirectoryRename,

        [Parameter(Mandatory = $false)]
        [switch]$SkipSubtitles,

        [Parameter(Mandatory = $false)]
        [switch]$SubtitleLanguageOnly,

        [Parameter(Mandatory = $false)]
        [switch]$NoFlattenSubtitleFolders,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Auto', 'FilenameOnly', 'Prompt', 'None')]
        [string]$LanguageDetection = 'Auto',

        [Parameter(Mandatory = $false)]
        [string]$DefaultSubtitleLanguage,

        [Parameter(Mandatory = $false)]
        [switch]$RemoveJunkFiles,

        [Parameter(Mandatory = $false)]
        [switch]$PermanentDelete,

        [Parameter(Mandatory = $false)]
        [switch]$NoPager,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    begin {
        $PendingRenames = [System.Collections.Generic.List[PSCustomObject]]::new()
        $OrphanSubtitles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

        $Stats = [ordered]@{
            FilesFound = 0; DirsFound = 0; SubsFound = 0; JunkFound = 0
            Processed = 0; Skipped = 0; Errors = 0; Deleted = 0
        }

        # -SubtitleLanguageOnly narrows the run to subtitle tags alone.
        if ($SubtitleLanguageOnly) {
            $SkipDirectoryRename = $true
            $SkipSubtitles = $false
            $RemoveJunkFiles = $false
        }

        # Normalise the requested default language up front so a bad value fails fast.
        $ResolvedDefaultLanguage = $null
        if ($DefaultSubtitleLanguage) {
            $Key = $DefaultSubtitleLanguage.ToLower()
            if ($script:LanguageMap.ContainsKey($Key)) {
                $ResolvedDefaultLanguage = $script:LanguageMap[$Key]
            } else {
                Write-Warning "Unrecognised -DefaultSubtitleLanguage '$DefaultSubtitleLanguage'. Falling back to no tag."
            }
        }

        $DetectionMode = switch ($LanguageDetection) {
            'Prompt'       { 'Auto' }
            'FilenameOnly' { 'FilenameOnly' }
            'None'         { 'None' }
            default        { 'Auto' }
        }
        $ShouldPrompt = ($LanguageDetection -eq 'Prompt')
    }

    process {
        foreach ($Dir in $TargetDirectory) {
            if (-not (Test-Path -Path $Dir)) {
                Write-Warning "Target directory not found: $Dir"
                continue
            }

            # =========================================================
            # PHASE 1: VIDEO FILES
            # =========================================================
            $Files = @(Get-ChildItem -Path $Dir -Recurse -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.Extension -in $MediaExtensions })
            $Stats.FilesFound += $Files.Count

            # Pre-compute media counts per directory: needed by the classifier.
            $SiblingCounts = @{}
            $VideosByDir   = @{}
            foreach ($F in $Files) {
                $Key = $F.DirectoryName
                if ($SiblingCounts.ContainsKey($Key)) { $SiblingCounts[$Key]++ } else { $SiblingCounts[$Key] = 1 }
                if (-not $VideosByDir.ContainsKey($Key)) { $VideosByDir[$Key] = [System.Collections.Generic.List[System.IO.FileInfo]]::new() }
                $VideosByDir[$Key].Add($F)
            }

            # Tracks each video's final base name so subtitles can follow it.
            $VideoFinalName = @{}

            if (-not $SubtitleLanguageOnly) {
                $Counter = 0
                foreach ($File in $Files) {
                    $Counter++
                    $Percent = if ($Files.Count -gt 0) { ($Counter / $Files.Count) * 100 } else { 100 }
                    Write-Progress -Activity "Scanning Files in $Dir" -Status "[$Counter/$($Files.Count)] $($File.Name)" -PercentComplete $Percent

                    $OldName        = $File.BaseName
                    $Extension      = $File.Extension
                    $ParentDir      = $File.Directory.Name
                    $GrandParentDir = if ($File.Directory.Parent) { $File.Directory.Parent.Name } else { $null }

                    $NewFileName = $null

                    # --- TV episode ---
                    $Episode = Resolve-EpisodeName -BaseName $OldName -ParentDirectory $ParentDir -GrandParentDirectory $GrandParentDir
                    if ($Episode) {
                        $NewFileName = Format-EpisodeFileName -Episode $Episode -Extension $Extension
                    }

                    # --- Movie (classifier driven) ---
                    # Runs before Extras so movies in "...DVDRIP..." folders are not mistaken for bonus content.
                    if (-not $NewFileName) {
                        $Score = Get-MediaScore -File $File -SiblingMediaCount $SiblingCounts[$File.DirectoryName]
                        if ($Score -le 0) {
                            # Prefer the parent folder's "Title (Year)" shape so file and folder stay in sync.
                            $Movie = Resolve-MovieName -Raw $ParentDir
                            if (-not $Movie) { $Movie = Resolve-MovieName -Raw $OldName }
                            if ($Movie) { $NewFileName = "$($Movie.Display)$Extension" }
                        }
                    }

                    # --- Bonus / extras ---
                    if (-not $NewFileName) {
                        $NewFileName = Resolve-ExtraName -BaseName $OldName -Extension $Extension `
                                                         -ParentDirectory $ParentDir -GrandParentDirectory $GrandParentDir
                    }

                    if ($NewFileName) {
                        $VideoFinalName[$File.FullName] = [System.IO.Path]::GetFileNameWithoutExtension($NewFileName)

                        if ($File.Name -ne $NewFileName) {
                            $PendingRenames.Add([PSCustomObject]@{
                                Type    = 'File'
                                Depth   = ($File.FullName -split '[\\/]').Count
                                Item    = $File
                                OldName = $File.Name
                                NewName = $NewFileName
                                OldPath = $File.FullName
                                NewPath = Join-Path -Path $File.DirectoryName -ChildPath $NewFileName
                                Moved   = $false
                                Detail  = $null
                            })
                        }
                    }
                }
            }

            # =========================================================
            # PHASE 1.5: SUBTITLES
            # =========================================================
            if (-not $SkipSubtitles) {
                $DirsWithVideo = @($VideosByDir.Keys)
                $SubCounter = 0

                foreach ($VideoDir in $DirsWithVideo) {
                    $SubCounter++
                    Write-Progress -Activity "Scanning Subtitles in $Dir" `
                                   -Status "[$SubCounter/$($DirsWithVideo.Count)] $VideoDir" `
                                   -PercentComplete (($SubCounter / [Math]::Max($DirsWithVideo.Count, 1)) * 100)

                    $Groups = @(Get-SubtitleFile -Directory $VideoDir -Videos $VideosByDir[$VideoDir].ToArray() -SubtitleExtensions $SubtitleExtensions)
                    if ($Groups.Count -eq 0) { continue }

                    $Stats.SubsFound += @($Groups | ForEach-Object { $_.Files }).Count

                    # Track language usage per video so duplicates get an ordinal.
                    $LanguageUse = @{}

                    foreach ($Group in $Groups) {
                        if (-not $Group.Video) {
                            $OrphanSubtitles.Add($Group.Primary)
                            continue
                        }

                        $Primary = $Group.Primary

                        # The video's post-rename base name, or its current one if unchanged.
                        $TargetBase = if ($VideoFinalName.ContainsKey($Group.Video.FullName)) {
                            $VideoFinalName[$Group.Video.FullName]
                        } else {
                            $Group.Video.BaseName
                        }

                        $Detection = Get-SubtitleLanguage -File $Primary -VideoBaseName $Group.Video.BaseName -Mode $DetectionMode
                        $Language = $Detection.Code
                        $Detail = $null

                        if ($ShouldPrompt -and ($null -eq $Language -or $Detection.Confidence -eq 'Low')) {
                            $Language = Read-SubtitleLanguageChoice -File $Primary -Suggestion $Detection.Code
                            if ($Language) { $Detail = 'language set interactively' }
                        }

                        if (-not $Language -and $ResolvedDefaultLanguage) {
                            $Language = $ResolvedDefaultLanguage
                            $Detail = 'default language applied'
                        }

                        if (-not $Detail -and $Language -and $Detection.Source -eq 'Content') {
                            $Detail = "language inferred from contents ($($Detection.Confidence.ToLower()) confidence)"
                        }

                        # LanguageOnly cannot do anything useful without a language.
                        if ($SubtitleLanguageOnly -and -not $Language) { continue }

                        # Ordinal disambiguation, keyed on language plus flags.
                        $UseKey = "$($Group.Video.FullName)|$Language|$($Detection.Flags -join '+')"
                        if ($LanguageUse.ContainsKey($UseKey)) { $LanguageUse[$UseKey]++ } else { $LanguageUse[$UseKey] = 1 }
                        $Ordinal = $LanguageUse[$UseKey]

                        # Where the sidecar should end up.
                        $DestDir = if ($Group.InSubFolder -and -not $NoFlattenSubtitleFolders) {
                            $VideoDir
                        } else {
                            $Primary.DirectoryName
                        }

                        foreach ($SubFile in $Group.Files) {
                            $NewSubName = if ($SubtitleLanguageOnly) {
                                Format-SubtitleFileName -Language $Language -Flags $Detection.Flags `
                                                        -Extension $SubFile.Extension -Ordinal $Ordinal `
                                                        -LanguageOnly -OriginalBaseName $SubFile.BaseName
                            } else {
                                Format-SubtitleFileName -VideoBaseName $TargetBase -Language $Language `
                                                        -Flags $Detection.Flags -Extension $SubFile.Extension -Ordinal $Ordinal
                            }

                            if (-not $NewSubName) { continue }

                            $NewSubPath = Join-Path -Path $DestDir -ChildPath $NewSubName
                            if ($NewSubPath -eq $SubFile.FullName) { continue }

                            $PendingRenames.Add([PSCustomObject]@{
                                Type    = 'Subtitle'
                                Depth   = ($SubFile.FullName -split '[\\/]').Count
                                Item    = $SubFile
                                OldName = $SubFile.Name
                                NewName = $NewSubName
                                OldPath = $SubFile.FullName
                                NewPath = $NewSubPath
                                Moved   = ($DestDir -ne $SubFile.DirectoryName)
                                Detail  = $Detail
                            })
                        }
                    }
                }
            }

            # =========================================================
            # PHASE 2: DIRECTORIES (bottom-up)
            # =========================================================
            if (-not $SkipDirectoryRename) {
                $SubFolders = @(Get-ChildItem -Path $Dir -Recurse -Directory -ErrorAction SilentlyContinue |
                                Sort-Object -Property { $_.FullName.Length } -Descending)
                $Stats.DirsFound += $SubFolders.Count
                $DirCounter = 0

                foreach ($SubDir in $SubFolders) {
                    $DirCounter++
                    $DirPercent = if ($SubFolders.Count -gt 0) { ($DirCounter / $SubFolders.Count) * 100 } else { 100 }
                    Write-Progress -Activity "Scanning Directories in $Dir" -Status "[$DirCounter/$($SubFolders.Count)] $($SubDir.Name)" -PercentComplete $DirPercent

                    # A Subs\ folder being flattened will be emptied; do not rename it.
                    if (-not $NoFlattenSubtitleFolders -and $script:SubtitleFolderNames -contains $SubDir.Name.ToLower()) {
                        continue
                    }

                    $NewDirName = Resolve-DirectoryName -Directory $SubDir

                    if ($NewDirName -and $SubDir.Name -ne $NewDirName) {
                        $PendingRenames.Add([PSCustomObject]@{
                            Type    = 'Directory'
                            Depth   = ($SubDir.FullName -split '[\\/]').Count
                            Item    = $SubDir
                            OldName = $SubDir.Name
                            NewName = $NewDirName
                            OldPath = $SubDir.FullName
                            NewPath = Join-Path -Path $SubDir.Parent.FullName -ChildPath $NewDirName
                            Moved   = $false
                            Detail  = $null
                        })
                    }
                }
            }

            # =========================================================
            # PHASE 3: JUNK
            # =========================================================
            if ($RemoveJunkFiles) {
                foreach ($JunkFile in @(Get-JunkFile -Directory $Dir)) {
                    $Stats.JunkFound++
                    $PendingRenames.Add([PSCustomObject]@{
                        Type      = 'Delete'
                        Depth     = ($JunkFile.FullName -split '[\\/]').Count
                        Item      = $JunkFile
                        OldName   = $JunkFile.Name
                        NewName   = $null
                        OldPath   = $JunkFile.FullName
                        NewPath   = $null
                        Moved     = $false
                        Detail    = $null
                        Size      = $JunkFile.Length
                        Permanent = [bool]$PermanentDelete
                    })
                }
            }
        }
    }

    end {
        Write-Progress -Activity 'Scanning Files' -Completed
        Write-Progress -Activity 'Scanning Subtitles' -Completed
        Write-Progress -Activity 'Scanning Directories' -Completed

        if ($PendingRenames.Count -eq 0) {
            Write-Host "`n✔ Operation Complete: nothing requires changing." -ForegroundColor Green
            if ($OrphanSubtitles.Count -gt 0) {
                Write-Host " ($($OrphanSubtitles.Count) subtitle file(s) could not be matched to a video and were ignored.)" -ForegroundColor DarkYellow
            }
            return
        }

        # Execution order: videos first (subtitle targets are derived from their new
        # names, not read from disk), then subtitles, then deletes, then directories
        # deepest-first so ancestors never invalidate descendant paths.
        $TypeRank = @{ 'File' = 0; 'Subtitle' = 1; 'Delete' = 2; 'Directory' = 3 }
        $OrderedRenames = @($PendingRenames |
            Sort-Object -Property @{ Expression = { $TypeRank[$_.Type] } },
                                  @{ Expression = 'Depth'; Descending = $true })

        Show-RenamePreview -Operations $OrderedRenames -NoPager:$NoPager

        # --- Orphan report ---
        if ($OrphanSubtitles.Count -gt 0) {
            Write-Host "[!] $($OrphanSubtitles.Count) subtitle file(s) could not be matched to a video and will be left alone:" -ForegroundColor DarkYellow
            foreach ($Orphan in $OrphanSubtitles) {
                Write-Host "    $($Orphan.FullName)" -ForegroundColor DarkGray
            }
            Write-Host ''
        }

        # --- Conflict detection ---
        $Conflicts = $PendingRenames | Where-Object { $_.NewPath } | Group-Object NewPath | Where-Object Count -gt 1
        if ($Conflicts) {
            Write-Host "[!] WARNING: Naming Conflicts Detected!" -ForegroundColor Red
            Write-Host "The following items would be renamed to the same exact path:" -ForegroundColor Red
            foreach ($Conflict in $Conflicts) {
                Write-Host " -> $($Conflict.Name)" -ForegroundColor Yellow
                foreach ($Item in $Conflict.Group) {
                    Write-Host "    Source: $($Item.OldPath)" -ForegroundColor DarkGray
                }
            }
            Write-Host "Recommend using 'Interactive' mode to resolve these manually.`n" -ForegroundColor Red
        }

        $ApplyAll = $false
        $Interactive = $false

        if ($Force) {
            $ApplyAll = $true
        } else {
            $Choices = @(
                [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Apply all changes in bulk.')
                [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Abort operation and make no changes.')
                [System.Management.Automation.Host.ChoiceDescription]::new('&Interactive', 'Prompt for each change individually.')
            )
            $Decision = $Host.UI.PromptForChoice('Confirm Action', "Do you want to apply these $($PendingRenames.Count) changes?", $Choices, 0)

            switch ($Decision) {
                0 { $ApplyAll = $true }
                1 {
                    Write-Host "`nOperation aborted by user. No files were modified." -ForegroundColor Yellow
                    return
                }
                2 { $Interactive = $true }
            }
        }

        Write-Host ''
        $Audit = Invoke-RenamePlan -Operations $OrderedRenames -ApplyAll:$ApplyAll -Interactive:$Interactive `
                                   -PermanentDelete:$PermanentDelete -Cmdlet $PSCmdlet

        foreach ($Record in $Audit) {
            switch ($Record.Status) {
                'Success' { $Stats.Processed++ }
                'Deleted' { $Stats.Deleted++ }
                'Skipped' { $Stats.Skipped++ }
                'Error'   { $Stats.Errors++ }
            }
        }

        # --- Remove folders emptied by subtitle flattening or junk deletion ---
        if (-not $NoFlattenSubtitleFolders -and -not $SkipSubtitles) {
            $EmptiedDirs = @($Audit | Where-Object { $_.Type -eq 'Subtitle' -and $_.Status -eq 'Success' } |
                             ForEach-Object { Split-Path -Path $_.OldPath -Parent } |
                             Sort-Object -Unique)

            foreach ($Candidate in $EmptiedDirs) {
                if (-not (Test-Path -LiteralPath $Candidate)) { continue }

                $Leaf = Split-Path -Path $Candidate -Leaf
                if ($script:SubtitleFolderNames -notcontains $Leaf.ToLower()) { continue }
                if (@(Get-ChildItem -LiteralPath $Candidate -Force -ErrorAction SilentlyContinue).Count -gt 0) { continue }

                if ($PSCmdlet.ShouldProcess($Candidate, 'Remove now-empty subtitle folder')) {
                    try {
                        Remove-Item -LiteralPath $Candidate -Force -ErrorAction Stop
                        Write-Host "[CLEANED] Removed empty folder: $Leaf" -ForegroundColor DarkGray
                    } catch {
                        Write-Verbose "Could not remove empty folder '$Candidate': $_"
                    }
                }
            }
        }

        # --- Also check directories that had junk files deleted ---
        if ($RemoveJunkFiles) {
            $JunkDirs = @($Audit | Where-Object { $_.Type -eq 'Delete' -and $_.Status -eq 'Deleted' } |
                          ForEach-Object { Split-Path -Path $_.OldPath -Parent } |
                          Sort-Object -Unique)

            foreach ($Candidate in $JunkDirs) {
                if (-not (Test-Path -LiteralPath $Candidate)) { continue }

                $Leaf = Split-Path -Path $Candidate -Leaf
                if ($script:SubtitleFolderNames -notcontains $Leaf.ToLower()) { continue }
                if (@(Get-ChildItem -LiteralPath $Candidate -Force -ErrorAction SilentlyContinue).Count -gt 0) { continue }

                if ($PSCmdlet.ShouldProcess($Candidate, 'Remove now-empty subtitle folder')) {
                    try {
                        Remove-Item -LiteralPath $Candidate -Force -ErrorAction Stop
                        Write-Host "[CLEANED] Removed empty folder: $Leaf" -ForegroundColor DarkGray
                    } catch {
                        Write-Verbose "Could not remove empty folder '$Candidate': $_"
                    }
                }
            }
        }

        # --- Dashboard summary ---
        Write-Host "`n--- Execution Summary ---" -ForegroundColor Cyan
        Write-Host " Videos Found          : $($Stats.FilesFound)"
        if ($Stats.SubsFound -gt 0) { Write-Host " Subtitles Found       : $($Stats.SubsFound)" }
        if ($Stats.DirsFound -gt 0) { Write-Host " Directories Scanned   : $($Stats.DirsFound)" }
        Write-Host " Successfully Renamed  : $($Stats.Processed)" -ForegroundColor Green
        if ($Stats.Deleted -gt 0) {
            $Where = if ($PermanentDelete) { 'permanently' } else { 'to Recycle Bin' }
            Write-Host " Junk Files Removed    : $($Stats.Deleted) ($Where)" -ForegroundColor Red
        }
        if ($OrphanSubtitles.Count -gt 0) { Write-Host " Orphaned Subtitles    : $($OrphanSubtitles.Count)" -ForegroundColor DarkYellow }
        if ($Stats.Skipped -gt 0) { Write-Host " Skipped by User       : $($Stats.Skipped)" -ForegroundColor Yellow }
        if ($Stats.Errors -gt 0)  { Write-Host " Errors Encountered    : $($Stats.Errors)" -ForegroundColor Red }

        if ($PassThru) { Write-Output $Audit }
    }
}
