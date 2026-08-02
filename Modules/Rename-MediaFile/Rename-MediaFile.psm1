# Requires -Version 7.6

function Rename-MediaFile {
    <#
    .SYNOPSIS
        Renames media files and parent season/extras/movie folders to adhere to Plex and Jellyfin naming conventions.
    .DESCRIPTION
        Analyzes file names and folder structures to extract Show, Season, Episode, Episode Title, Movie Title,
        Release Year, and Bonus feature information.

        Naming conventions enforced:
            Movies   : Movie Title (Release Year)\Movie Title (Release Year).ext
            TV Shows : Show Title\Season #\Show Title - S##E## - Episode Title.ext

        Files that do not carry an explicit episode marker are classified as either Movie or TV content using a
        weighted heuristic scoring engine that considers sibling file counts, parent folder context, absolute
        numbering, and the presence of a standalone release year.

        Features a safe preview mode. If run without -Force, it aggregates all changes, checks for conflicts,
        displays a summary table, and asks for confirmation (with an interactive per-item approval option).
    .EXAMPLE
        Rename-MediaFile -TargetDirectory "D:\Media\TV Shows"
    .EXAMPLE
        Rename-MediaFile -TargetDirectory "D:\Media\Movies" -WhatIf
    .EXAMPLE
        Rename-MediaFile -TargetDirectory "D:\Media\TV Shows" -Force
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'Path')]
        [string[]]$TargetDirectory = $PWD.Path,

        [Parameter(Mandatory = $false)]
        [string[]]$MediaExtensions = @('.mp4', '.avi', '.mkv', '.mov', '.m4v'),

        [Parameter(Mandatory = $false)]
        [switch]$SkipDirectoryRename,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    begin {
        # =================================================================
        # REGEX LIBRARY
        # =================================================================

        # Scenario 1: Inline show name (e.g. Show.Name.S01E01.Title)
        $RegexScenario1 = '^(?<Show>.*?)[._\s]+[sS](?<Season>\d+)[eExX](?<Episode>\d+)(?:[._\s-]+(?<Title>.*?))?$|^(?<Show>.*?)[._\s]+(?<Season>\d+)x(?<Episode>\d+)(?:[._\s-]+(?<Title>.*?))?$'

        # Scenario 1.5: Standalone season/episode notation (e.g. S01 E01, 1x01) usually found inside organized folders
        $RegexStandalone = '^[sS]?(?<Season>\d+)[\s._-]*[eExX](?<Episode>\d+)(?:[\s._-]+(?<Title>.*?))?$'

        # Any explicit episode marker anywhere in a name. Used by the classifier as a hard TV signal.
        $RegexEpisodeMarker = '(?i)(?:\bs\d{1,2}[\s._-]*e\d{1,3}\b|\b\d{1,2}x\d{2}\b|\bseason[\s._-]*\d{1,2}[\s._-]*episode[\s._-]*\d{1,3}\b|\b(?:19|20)\d{2}[.\-]\d{2}[.\-]\d{2}\b)'

        # Matches parent directories containing series/season info, extracting the preceeding Show name
        $RegexSeasonDir = '^(?<Show>.*?)[._\s-]*(?:[sS]eason|[sS]taffel|[sS]erie[sn]?|[sS])[\s._-]*0*(?<Season>\d+)(?<Trailer>(?:[._\s-].*)?)$'

        # Detects a box-set / complete-collection folder holding several seasons (e.g. "Complete Series 1 2 3 4 5")
        $RegexBoxSet = '(?i)\b(?:complete|full|all)\b[\s._-]*(?:the[\s._-]*)?(?:series|seasons?|collection|box[\s._-]*set|staffeln)?\b'

        # Two or more bare numbers in a row, e.g. "1 2 3 4 5" -> multi-season compilation
        $RegexMultiSeasonNumbers = '\b\d{1,2}(?:[\s._-]+\d{1,2}){1,}\b'

        # Detects bonus/extra edge cases, including common misspellings (e.g., outake, bloopers)
        $RegexExtrasKeywords = '(?i)\b(?:extra[s]?|bonus(?:es)?|outt?ake[s]?|blooper[s]?|gag[s]?|bts|behind.*?scene[s]?|deleted|interview[s]?|featurette[s]?|special[s]?|trailer[s]?|promo[s]?|doc(?:umentary)?(?:ies)?)\b'

        # Standalone 4 digit release year (1900-2099)
        $RegexYear = '(?<!\d)(?<Year>19\d{2}|20\d{2})(?!\d)'

        # "Part 2", "Vol 3", "Volume 3", "Chapter 4"
        $RegexPartVol = '(?i)\b(?:part|pt|vol(?:ume)?|chapter|cd|disc|disk)[\s._-]*(?:\d{1,2}|[ivx]{1,4})\b'

        # Anime style absolute numbering: "Show Name - 012" / "[Group] Show 012"
        $RegexAbsoluteNumber = '(?i)(?:^|[\s._-])-[\s._-]*\d{1,4}(?:[\s._-]|$)|(?:^|[\s._-])[eE][pP]?[\s._-]*\d{1,4}(?:[\s._-]|$)'

        # -----------------------------------------------------------------
        # Scene junk. Kept as a single alternation so it can be applied with
        # -replace anywhere inside a candidate title.
        # -----------------------------------------------------------------
        $JunkTokens = @(
            # Resolution / picture
            '2160p', '1440p', '1080p', '1080i', '720p', '576p', '540p', '480p', '360p', '4k', 'uhd', 'fhd', 'hd', 'sd'
            'hdr10\+?', 'hdr', 'dolby[\s._-]*vision', 'dovi', '10bit', '8bit', 'hi10p?', 'imax'
            # Source
            'bluray', 'blu[\s._-]*ray', 'bdremux', 'bd[\s._-]*rip', 'bdrip', 'brrip', 'br[\s._-]*rip'
            'dvdrip', 'dvd[\s._-]*rip', 'dvdscr', 'dvd[\s._-]*r', 'dvd\d?', 'ntsc', 'pal'
            'web[\s._-]*dl', 'webdl', 'webrip', 'web[\s._-]*rip', 'web', 'hdtv', 'pdtv', 'dsr', 'hdrip', 'hd[\s._-]*rip'
            'remux', 'camrip', 'cam', 'telesync', 'telecine', 'tvrip', 'satrip', 'workprint', 'r5', 'r6'
            # Codec
            'x264', 'x265', 'h[\s._.-]*264', 'h[\s._.-]*265', 'hevc', 'avc', 'xvid', 'divx', 'mpeg[\s._-]*[24]', 'vp9', 'av1'
            # Audio
            'dts[\s._-]*hd(?:[\s._-]*ma)?', 'dts[\s._-]*x', 'dts', 'truehd', 'atmos', 'ddp?[\s._-]*?[57][\s._.-]1'
            'e?ac[\s._-]*3', 'aac2?(?:[\s._.-]0)?', 'aac', 'mp3', 'flac', 'opus', 'pcm', 'lpcm'
            '[257][\s._.-]1(?:ch)?', '2[\s._.-]0(?:ch)?', 'dual[\s._-]*audio', 'dubbed', 'subbed', 'subs', 'multi[\s._-]*sub'
            # Release / edition markers
            'proper', 'repack', 'rerip', 'internal', 'limited', 'readnfo', 'nfofix', 'multi'
            'unrated', 'uncut', 'uncensored', 'extended', 'remastered', 'restored', 'theatrical', 'directors?[\s._-]*cut'
            'retail', 'custom', 'complete', 'untouched'
        )
        $RegexSceneJunk = '(?i)\b(?:' + ($JunkTokens -join '|') + ')\b'

        # Bracketed groups: non greedy so multiple bracket sets are handled independently.
        $RegexBracketed = '\([^)]*\)|\[[^\]]*\]|\{[^}]*\}'

        $WordMap = @{ 'one'='01'; 'two'='02'; 'three'='03'; 'four'='04'; 'five'='05'; 'six'='06'; 'seven'='07'; 'eight'='08'; 'nine'='09'; 'ten'='10' }

        # Official Plex / Jellyfin Local Extras Folder Mapping Table
        $ExtrasDirMap = [ordered]@{
            '(?i)(?:outt?ake|blooper|gag|bts|behind.*?scene|b-roll)' = 'Behind The Scenes'
            '(?i)(?:delete|cut.*?scene)'                           = 'Deleted Scenes'
            '(?i)(?:interview|cast.*?comment)'                     = 'Interviews'
            '(?i)(?:trailer|promo|teaser)'                         = 'Trailers'
            '(?i)(?:doc|documentary|extra|bonus|feature|misc|special.*feature)' = 'Extras'
        }

        # =================================================================
        # HELPERS
        # =================================================================

        # Normalises separators, strips scene junk, drops trailing release-group tokens and title-cases the result.
        $CleanTitle = {
            param([string]$Raw, [switch]$StripBrackets)

            if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
            $Text = $Raw

            if ($StripBrackets) { $Text = $Text -replace $RegexBracketed, ' ' }

            # Convert scene separators to spaces before junk removal so \b boundaries behave predictably.
            $Text = $Text -replace '[._]+', ' '

            # Remember where the last junk token appeared; everything past it is release-group noise.
            $JunkMatches = [regex]::Matches($Text, $RegexSceneJunk)
            if ($JunkMatches.Count -gt 0) {
                $Last = $JunkMatches[$JunkMatches.Count - 1]
                $Text = $Text.Substring(0, $Last.Index)
            }

            $Text = $Text -replace $RegexSceneJunk, ' '
            $Text = $Text -replace '\s+', ' '
            $Text = $Text.Trim(' ', '-', '_', '.', ',')

            if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

            # ToTitleCase leaves ALL-CAPS words untouched, so lower first for consistent output.
            return (Get-Culture).TextInfo.ToTitleCase($Text.ToLower())
        }

        # Weighted Movie/TV classifier. Positive => TV, zero or negative => Movie.
        $GetMediaScore = {
            param([System.IO.FileInfo]$File, [int]$SiblingMediaCount)

            $Score = 0
            $Name = $File.BaseName
            $Parent = $File.Directory.Name
            $HasEpisodeMarker = $Name -match $RegexEpisodeMarker

            if ($HasEpisodeMarker)                       { $Score += 100 }
            if ($SiblingMediaCount -ge 2)                { $Score += 80 }
            if ($Parent -match $RegexSeasonDir -or
                $Parent -match '(?i)\bspecials?\b')      { $Score += 80 }
            if ($Name -match $RegexPartVol -or
                $Name -match $RegexAbsoluteNumber)       { $Score += 30 }
            if ($SiblingMediaCount -le 1)                { $Score -= 40 }
            if (-not $HasEpisodeMarker -and
                $Name -match $RegexYear)                 { $Score -= 80 }

            return $Score
        }

        # Pulls "Some Title (2007)" out of a folder name, or "Some.Title.2007" out of a file name.
        $ParseMovieName = {
            param([string]$Raw)

            if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }

            # Prefer a parenthesised year, otherwise the last standalone year in the string.
            $Year = $null
            $TitlePart = $Raw

            $ParenYear = [regex]::Match($Raw, '\((?<Year>19\d{2}|20\d{2})\)')
            if ($ParenYear.Success) {
                $Year = $ParenYear.Groups['Year'].Value
                $TitlePart = $Raw.Substring(0, $ParenYear.Index)
            } else {
                $YearMatches = [regex]::Matches($Raw, $RegexYear)
                if ($YearMatches.Count -gt 0) {
                    $Chosen = $YearMatches[$YearMatches.Count - 1]
                    # A leading year ("2007 Movie Name") is part of the title, not a suffix.
                    if ($Chosen.Index -gt 0) {
                        $Year = $Chosen.Groups['Year'].Value
                        $TitlePart = $Raw.Substring(0, $Chosen.Index)
                    }
                }
            }

            if (-not $Year) { return $null }

            $Title = & $CleanTitle $TitlePart -StripBrackets
            if ([string]::IsNullOrWhiteSpace($Title)) { return $null }

            return [PSCustomObject]@{ Title = $Title; Year = $Year; Display = "$Title ($Year)" }
        }

        # Centralized queue for all intended renaming operations (function scoped - must not persist between calls).
        $PendingRenames = [System.Collections.Generic.List[PSCustomObject]]::new()
        $AuditLog = [System.Collections.Generic.List[PSCustomObject]]::new()

        $Stats = [ordered]@{ FilesFound = 0; DirsFound = 0; Processed = 0; Skipped = 0; Errors = 0 }
    }

    process {
        foreach ($Dir in $TargetDirectory) {
            if (-not (Test-Path -Path $Dir)) {
                Write-Warning "Target directory not found: $Dir"
                continue
            }

            # =================================================================
            # PHASE 1: DISCOVER MEDIA FILES (Dry-Run Compilation)
            # =================================================================
            $Files = @(Get-ChildItem -Path $Dir -Recurse -File | Where-Object { $_.Extension -in $MediaExtensions })
            $Stats.FilesFound += $Files.Count
            $Counter = 0

            # Pre-compute how many media files live in each directory: needed by the classifier.
            $SiblingCounts = @{}
            foreach ($F in $Files) {
                $Key = $F.DirectoryName
                if ($SiblingCounts.ContainsKey($Key)) { $SiblingCounts[$Key]++ } else { $SiblingCounts[$Key] = 1 }
            }

            foreach ($File in $Files) {
                $Counter++
                $Percent = if ($Files.Count -gt 0) { ($Counter / $Files.Count) * 100 } else { 100 }
                Write-Progress -Activity "Scanning Files in $Dir" -Status "[$Counter/$($Files.Count)] $($File.Name)" -PercentComplete $Percent

                $OldName = $File.BaseName
                $Extension = $File.Extension
                $ParentDir = $File.Directory.Name
                $GrandParentDir = if ($File.Directory.Parent) { $File.Directory.Parent.Name } else { $null }

                $ShowName = $null; $SeasonStr = $null; $EpisodeStr = $null; $EpisodeTitle = $null
                $NewFileName = $null; $IsExtra = $false

                # --- SCENARIO 1: Standard Inline Filename ---
                if ($OldName -match $RegexScenario1 -and $Matches.Show.Trim()) {
                    $M = @{} + $Matches
                    $ShowName   = $M.Show -replace '[._\s]+', ' '
                    $SeasonStr  = $M.Season
                    $EpisodeStr = $M.Episode
                    if ($M.Title) { $EpisodeTitle = $M.Title }
                }
                # --- SCENARIO 1.5: Standalone SXXEYY format inside a folder ---
                elseif ($OldName -match $RegexStandalone) {
                    $M = @{} + $Matches
                    $SeasonStr  = $M.Season
                    $EpisodeStr = $M.Episode
                    if ($M.Title) { $EpisodeTitle = $M.Title }

                    # Try to extract show name from parent directory, walking upward until a non-season name is found.
                    $ShowName = $null
                    if ($ParentDir -match $RegexSeasonDir) {
                        $PM = @{} + $Matches
                        if (-not [string]::IsNullOrWhiteSpace($PM.Show)) {
                            $ShowName = $PM.Show -replace '[._\s]+', ' '
                        }
                    }

                    if ([string]::IsNullOrWhiteSpace($ShowName) -and $GrandParentDir) {
                        # Grandparent may itself be a box set folder ("Show Complete Series 1 2 3") - strip that down.
                        if ($GrandParentDir -match $RegexSeasonDir -and -not [string]::IsNullOrWhiteSpace($Matches.Show)) {
                            $ShowName = $Matches.Show -replace '[._\s]+', ' '
                        } else {
                            $ShowName = $GrandParentDir
                        }
                    }
                }
                # --- SCENARIO 2: Textual Number Fallback (Episode Three) ---
                elseif ($OldName -match '^(?:Episode|Ep)[\s._-]+(?<Word>\w+)(?:[._\s-]+(?<Title>.*?))?$') {
                    $FM = @{} + $Matches
                    $TargetWord = $FM.Word.ToLower()

                    if ($WordMap.ContainsKey($TargetWord) -and $ParentDir -match $RegexSeasonDir) {
                        $PM = @{} + $Matches
                        $ShowName   = if (-not [string]::IsNullOrWhiteSpace($PM.Show)) { $PM.Show -replace '[._\s]+', ' ' } else { $GrandParentDir }
                        $SeasonStr  = $PM.Season
                        $EpisodeStr = $WordMap[$TargetWord]
                        if ($FM.Title) { $EpisodeTitle = $FM.Title }
                    }
                }

                # --- SCENARIO 4: MOVIE (classifier driven) ---
                # Runs before the Extras branch so movies in "...DVDRIP..." folders are not mistaken for bonus content.
                if (-not ($ShowName -and $SeasonStr -and $EpisodeStr)) {
                    $SiblingCount = $SiblingCounts[$File.DirectoryName]
                    $Score = & $GetMediaScore $File $SiblingCount

                    if ($Score -le 0) {
                        # Option (A): prefer the parent folder's "Title (Year)" shape so file and folder stay in sync.
                        $Movie = & $ParseMovieName $ParentDir
                        if (-not $Movie) { $Movie = & $ParseMovieName $OldName }

                        if ($Movie) { $NewFileName = "$($Movie.Display)$Extension" }
                    }
                }

                # --- SCENARIO 3: EDGE CASE - Bonus / Extras File Cleaner ---
                if (-not $NewFileName -and -not ($ShowName -and $SeasonStr -and $EpisodeStr)) {
                    if ($OldName -match $RegexExtrasKeywords -or $ParentDir -match $RegexExtrasKeywords) {
                        $IsExtra = $true
                        $Clean = & $CleanTitle $OldName

                        if ($Clean) {
                            if ($GrandParentDir -and $GrandParentDir -notmatch $RegexExtrasKeywords -and $Clean -notmatch "^$([regex]::Escape($GrandParentDir))") {
                                $ShowPrefix = & $CleanTitle $GrandParentDir -StripBrackets
                                $NewFileName = if ($ShowPrefix) { "$ShowPrefix - $Clean$Extension" } else { "$Clean$Extension" }
                            } else {
                                $NewFileName = "$Clean$Extension"
                            }
                        }
                    }
                }

                # --- BUILD STANDARD EPISODE FILENAME ---
                if (-not $IsExtra -and $ShowName -and $SeasonStr -and $EpisodeStr) {
                    $ShowName = & $CleanTitle $ShowName -StripBrackets

                    if ($ShowName) {
                        $FinalSeason  = [int]$SeasonStr
                        $FinalEpisode = [int]$EpisodeStr

                        if ($EpisodeTitle) { $EpisodeTitle = & $CleanTitle $EpisodeTitle -StripBrackets }

                        if (![string]::IsNullOrWhiteSpace($EpisodeTitle)) {
                            $NewFileName = "{0} - S{1:D2}E{2:D2} - {3}{4}" -f $ShowName, $FinalSeason, $FinalEpisode, $EpisodeTitle, $Extension
                        } else {
                            $NewFileName = "{0} - S{1:D2}E{2:D2}{3}" -f $ShowName, $FinalSeason, $FinalEpisode, $Extension
                        }
                    }
                }

                # Queue the rename logic
                if ($NewFileName -and $File.Name -ne $NewFileName) {
                    $PendingRenames.Add([PSCustomObject]@{
                        Type    = 'File'
                        Depth   = ($File.FullName -split '[\\/]').Count
                        Item    = $File
                        OldName = $File.Name
                        NewName = $NewFileName
                        OldPath = $File.FullName
                        NewPath = Join-Path -Path $File.DirectoryName -ChildPath $NewFileName
                    })
                }
            }

            # =================================================================
            # PHASE 2: DISCOVER DIRECTORIES (Bottom-Up)
            # =================================================================
            if (-not $SkipDirectoryRename) {
                $SubFolders = @(Get-ChildItem -Path $Dir -Recurse -Directory | Sort-Object -Property { $_.FullName.Length } -Descending)
                $Stats.DirsFound += $SubFolders.Count
                $DirCounter = 0

                foreach ($SubDir in $SubFolders) {
                    $DirCounter++
                    $DirPercent = if ($SubFolders.Count -gt 0) { ($DirCounter / $SubFolders.Count) * 100 } else { 100 }
                    Write-Progress -Activity "Scanning Directories in $Dir" -Status "[$DirCounter/$($SubFolders.Count)] $($SubDir.Name)" -PercentComplete $DirPercent

                    $NewDirName = $null
                    $DirName = $SubDir.Name

                    # Does this folder contain child folders that look like seasons? Then it is a show root, not a season.
                    $ChildDirs = @(Get-ChildItem -LiteralPath $SubDir.FullName -Directory -ErrorAction SilentlyContinue)
                    $SeasonChildCount = @($ChildDirs | Where-Object { $_.Name -match $RegexSeasonDir }).Count

                    $SeasonMatch = [regex]::Match($DirName, $RegexSeasonDir)
                    $IsBoxSet = $DirName -match $RegexBoxSet -or $DirName -match $RegexMultiSeasonNumbers

                    if ($SeasonMatch.Success -and -not $IsBoxSet -and $SeasonChildCount -lt 2) {
                        # Genuine single-season folder.
                        $NewDirName = "Season {0}" -f [int]$SeasonMatch.Groups['Season'].Value
                    }
                    elseif ($SeasonMatch.Success -and ($IsBoxSet -or $SeasonChildCount -ge 2)) {
                        # Box set / show root: reduce to the bare show title.
                        $NewDirName = & $CleanTitle $SeasonMatch.Groups['Show'].Value -StripBrackets
                    }
                    elseif ($DirName -match $RegexExtrasKeywords) {
                        foreach ($Pattern in $ExtrasDirMap.Keys) {
                            if ($DirName -match $Pattern) {
                                $NewDirName = $ExtrasDirMap[$Pattern]
                                break
                            }
                        }
                    }
                    else {
                        # Movie folder cleanup: "Title (2007) [1080p]" -> "Title (2007)"
                        $Movie = & $ParseMovieName $DirName
                        if ($Movie) { $NewDirName = $Movie.Display }
                    }

                    if ($NewDirName -and $SubDir.Name -ne $NewDirName) {
                        $PendingRenames.Add([PSCustomObject]@{
                            Type    = 'Directory'
                            Depth   = ($SubDir.FullName -split '[\\/]').Count
                            Item    = $SubDir
                            OldName = $SubDir.Name
                            NewName = $NewDirName
                            OldPath = $SubDir.FullName
                            NewPath = Join-Path -Path $SubDir.Parent.FullName -ChildPath $NewDirName
                        })
                    }
                }
            }
        }
    }

    end {
        Write-Progress -Activity "Scanning Files" -Completed
        Write-Progress -Activity "Scanning Directories" -Completed

        if ($PendingRenames.Count -eq 0) {
            Write-Host "`n✔ Operation Complete: No files or directories require renaming." -ForegroundColor Green
            return
        }

        # Execution order matters: rename files first (their queued paths assume original folder names),
        # then rename directories deepest-first so ancestors never invalidate descendant paths.
        $OrderedRenames = $PendingRenames | Sort-Object -Property @{ Expression = { if ($_.Type -eq 'File') { 0 } else { 1 } } },
                                                                  @{ Expression = 'Depth'; Descending = $true }

        # --- PREVIEW / INTERACTIVE UI ---
        Write-Host "`n--------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host " PREVIEW: $($PendingRenames.Count) pending renaming operations" -ForegroundColor Cyan
        Write-Host "--------------------------------------------------------------`n" -ForegroundColor Cyan

        $OrderedRenames | Select-Object Type, OldName, NewName | Format-Table -AutoSize | Out-Host

        # Conflict Detection
        $Conflicts = $PendingRenames | Group-Object NewPath | Where-Object Count -gt 1
        if ($Conflicts) {
            Write-Host "`n[!] WARNING: Naming Conflicts Detected!" -ForegroundColor Red
            Write-Host "The following items will attempt to be renamed to the same exact name:" -ForegroundColor Red
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
                [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Apply all changes in bulk.")
                [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Abort operation and make no changes.")
                [System.Management.Automation.Host.ChoiceDescription]::new("&Interactive", "Prompt for each change individually.")
            )
            $Decision = $Host.UI.PromptForChoice("Confirm Action", "Do you want to apply these $($PendingRenames.Count) changes?", $Choices, 0)

            if ($Decision -eq 1) {
                Write-Host "`nOperation aborted by user. No files were modified." -ForegroundColor Yellow
                return
            } elseif ($Decision -eq 0) {
                $ApplyAll = $true
            } elseif ($Decision -eq 2) {
                $Interactive = $true
            }
        }

        # --- EXECUTION LOOP ---
        Write-Host ""
        foreach ($Change in $OrderedRenames) {
            $ExecuteItem = $ApplyAll

            if ($Interactive) {
                $IntChoices = @(
                    [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Rename this item.")
                    [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Skip this item.")
                )
                $IntDecision = $Host.UI.PromptForChoice("Rename $($Change.Type)", "Rename '$($Change.OldName)' to '$($Change.NewName)'?", $IntChoices, 0)
                $ExecuteItem = ($IntDecision -eq 0)
            }

            if ($ExecuteItem) {
                if ($PSCmdlet.ShouldProcess($Change.OldPath, "Rename to $($Change.NewName)")) {
                    try {
                        Rename-Item -LiteralPath $Change.OldPath -NewName $Change.NewName -ErrorAction Stop
                        Write-Host "[SUCCESS] $($Change.OldName) -> $($Change.NewName)" -ForegroundColor Green
                        $Stats.Processed++

                        if ($PassThru) {
                            $AuditLog.Add([PSCustomObject]@{
                                Status  = 'Success'
                                Type    = $Change.Type
                                OldName = $Change.OldName
                                NewName = $Change.NewName
                                OldPath = $Change.OldPath
                                NewPath = $Change.NewPath
                            })
                        }
                    } catch {
                        Write-Host "[FAILED]  Could not rename $($Change.OldName): $_" -ForegroundColor Red
                        $Stats.Errors++
                    }
                }
            } else {
                Write-Host "[SKIPPED] $($Change.OldName)" -ForegroundColor DarkGray
                $Stats.Skipped++
            }
        }

        # --- DASHBOARD SUMMARY ---
        Write-Host "`n--- Execution Summary ---" -ForegroundColor Cyan
        Write-Host " Total Items Evaluated : $($Stats.FilesFound + $Stats.DirsFound)"
        Write-Host " Successfully Renamed  : $($Stats.Processed)" -ForegroundColor Green
        if ($Stats.Skipped -gt 0) { Write-Host " Skipped by User       : $($Stats.Skipped)" -ForegroundColor Yellow }
        if ($Stats.Errors -gt 0)  { Write-Host " Errors Encountered    : $($Stats.Errors)" -ForegroundColor Red }

        if ($PassThru) { Write-Output $AuditLog }
    }
}

Export-ModuleMember -Function Rename-MediaFile
