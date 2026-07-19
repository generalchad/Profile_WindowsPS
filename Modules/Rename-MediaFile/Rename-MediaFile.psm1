# Requires -Version 7.6

function Rename-MediaFile {
    <#
    .SYNOPSIS
        Renames media files and parent season/extras folders to adhere to Plex and Jellyfin naming conventions.
    .DESCRIPTION
        Analyzes file names and folder structures to extract Show, Season, Episode, and Bonus feature information.
        Renames media files to 'Show Name - SXXEXX.ext', scrubs unindexed DVD extras into clean titles,
        and standardizes miscellaneous folders into official Plex/Jellyfin Local Extras directories.
    .EXAMPLE
        Rename-MediaFile -TargetDirectory "D:\Media\TV Shows"
    .EXAMPLE
        Rename-MediaFile -TargetDirectory "D:\Media\TV Shows" -SkipDirectoryRename -PassThru | Export-Csv "Audit.csv"
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'Path')]
        [string[]]$TargetDirectory,

        [Parameter(Mandatory = $false)]
        [string[]]$MediaExtensions = @('.mp4', '.avi', '.mkv', '.mov', '.m4v'),

        [Parameter(Mandatory = $false)]
        [switch]$SkipDirectoryRename,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    begin {
        # --- REGEX COMPILE BLOCK ---
        $RegexScenario1 = '^(?<Show>.*?)[._\s]+[sS](?<Season>\d+)[eE](?<Episode>\d+).*$|^(?<Show>.*?)[._\s]+(?<Season>\d+)x(?<Episode>\d+).*$'
        $RegexSeasonDir = '^(?:.*?[._\s-]+)?(?:[sS]eason|[sS]taffel|[sS]eries|S)[\s._-]*0*(?<Season>\d+)(?:[._\s-].*)?$'

        # Regex to detect if a file or folder is a bonus/extra edge case
        $RegexExtrasKeywords = '(?i)(?:extra|bonus|outtake|blooper|gag|bts|behind.*?scene|deleted|interview|featurette|special|trailer|promo|dvd)'

        # Regex to scrub common release group and encoding junk from bonus filenames
        $RegexSceneJunk = '(?i)\b(?:dvdrip|xvid|divx|ffndvd|gore|dimension|h264|x264|hevc|1080p|720p|480p|bluray|web-dl|webrip|aac|mp3|ac3|flac|remux|dvd|xvid-.*|dvdrip-.*)\b'

        $WordMap = @{ 'one'='01'; 'two'='02'; 'three'='03'; 'four'='04'; 'five'='05'; 'six'='06'; 'seven'='07'; 'eight'='08'; 'nine'='09'; 'ten'='10' }

        # Official Plex / Jellyfin Local Extras Folder Mapping Table
        $ExtrasDirMap = [ordered]@{
            '(?i)(?:outtake|blooper|gag|bts|behind.*?scene|b-roll)' = 'Behind The Scenes'
            '(?i)(?:delete|cut.*?scene)'                           = 'Deleted Scenes'
            '(?i)(?:interview|cast.*?comment)'                     = 'Interviews'
            '(?i)(?:trailer|promo|teaser)'                         = 'Trailers'
            '(?i)(?:extra|bonus|feature|misc|dvd|special.*feature)' = 'Featurettes'
        }

        # Track execution statistics for the dashboard
        $Stats = [ordered]@{
            FilesFound   = 0
            FilesRenamed = 0
            FilesSkipped = 0
            DirsRenamed  = 0
            DirsSkipped  = 0
            Errors       = 0
        }

        $AuditLog = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        foreach ($Dir in $TargetDirectory) {
            if (-not (Test-Path -Path $Dir)) {
                Write-Error "Target directory not found: $Dir"
                continue
            }

            # =================================================================
            # PHASE 1: MEDIA FILE PROCESSING
            # =================================================================
            $Files = Get-ChildItem -Path $Dir -Recurse -File |
                Where-Object { $_.Extension -in $MediaExtensions }

            $TotalFiles = $Files.Count
            $Stats.FilesFound += $TotalFiles
            $Counter = 0

            foreach ($File in $Files) {
                $Counter++
                Write-Progress -Activity "Processing Media Files" -Status "[$Counter/$TotalFiles] $($File.Name)" -PercentComplete (($Counter / $TotalFiles) * 100)

                $ShortName = if ($File.Name.Length -gt 45) { $File.Name.Substring(0, 42) + "..." } else { $File.Name }
                Write-Host "`r[File $Counter/$TotalFiles] Checking: $ShortName$( ' ' * 15 )" -NoNewline -ForegroundColor Cyan

                $OldName = $File.BaseName
                $Extension = $File.Extension
                $ParentDir = $File.Directory.Name
                $GrandParentDir = $File.Directory.Parent.Name

                $ShowName = $null
                $SeasonStr = $null
                $EpisodeStr = $null
                $NewFileName = $null
                $IsExtra = $false

                # --- SCENARIO 1: Standard Inline Filename ---
                if ($OldName -match $RegexScenario1) {
                    $ShowName = $Matches.Show -replace '[._\s]+', ' '
                    $SeasonStr = $Matches.Season
                    $EpisodeStr = $Matches.Episode
                }
                # --- SCENARIO 2: Standard Folder Fallback ---
                elseif ($ParentDir -match '^[sS]eason\s*(?<Season>\d+)$' -and ($OldName -match '(?:Episode|Ep|Ep\.|_)\s*(?<Episode>\d+)' -or $OldName -match '^(?<Episode>\d+)$')) {
                    $ShowName = $GrandParentDir
                    $SeasonStr = $Matches.Season
                    $EpisodeStr = $Matches.Episode
                }
                # --- SCENARIO 3: Textual Number Fallback ---
                elseif ($ParentDir -match '^[sS]eason\s*(?<Season>\d+)$' -and $OldName -match '(?:Episode|Ep)\s+(?<Word>\w+)') {
                    $TargetWord = $Matches.Word.ToLower()
                    if ($WordMap.ContainsKey($TargetWord)) {
                        $ShowName = $GrandParentDir
                        $SeasonStr = $Matches.Season
                        $EpisodeStr = $WordMap[$TargetWord]
                    }
                }
                # --- SCENARIO 4: EDGE CASE - Bonus / Extras File Cleaner ---
                elseif ($OldName -match $RegexExtrasKeywords -or $ParentDir -match $RegexExtrasKeywords) {
                    $IsExtra = $true
                    # Scrub out release junk (dvdrip, xvid, etc.) and standalone 'dvd' words
                    $CleanTitle = $OldName -replace $RegexSceneJunk, '' -replace '[._-]+', ' ' -replace '\s+', ' '
                    $CleanTitle = (Get-Culture).TextInfo.ToTitleCase($CleanTitle.Trim())

                    # If the scrubbed title doesn't already start with the show name, try to prepend it from folder structure
                    if ($GrandParentDir -and $GrandParentDir -notmatch $RegexExtrasKeywords -and $CleanTitle -notmatch "^$GrandParentDir") {
                        $ShowPrefix = (Get-Culture).TextInfo.ToTitleCase($GrandParentDir.Trim())
                        $NewFileName = "$ShowPrefix - $CleanTitle$Extension"
                    } else {
                        $NewFileName = "$CleanTitle$Extension"
                    }
                }

                # --- BUILD STANDARD EPISODE FILENAME IF NOT AN EXTRA ---
                if (-not $IsExtra -and $ShowName -and $SeasonStr -and $EpisodeStr) {
                    $ShowName = (Get-Culture).TextInfo.ToTitleCase($ShowName.Trim())
                    $FinalSeason = [int]$SeasonStr
                    $FinalEpisode = [int]$EpisodeStr
                    $NewFileName = "{0} - S{1:D2}E{2:D2}{3}" -f $ShowName, $FinalSeason, $FinalEpisode, $Extension
                }

                # --- EXECUTE FILE RENAME ---
                if ($NewFileName) {
                    $NewPath = Join-Path -Path $File.DirectoryName -ChildPath $NewFileName

                    if ($File.Name -eq $NewFileName) {
                        $Stats.FilesSkipped++
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($File.FullName, "Rename file to $NewFileName")) {
                        try {
                            Rename-Item -Path $File.FullName -NewName $NewFileName -ErrorAction Stop
                            $Stats.FilesRenamed++

                            Write-Host "`r[File $Counter/$TotalFiles] Renamed : $NewFileName$( ' ' * 15 )" -NoNewline -ForegroundColor Green

                            if ($PassThru) {
                                $AuditLog.Add([PSCustomObject]@{
                                    Status  = 'Success'
                                    Type    = if ($IsExtra) { 'BonusFile' } else { 'EpisodeFile' }
                                    Show    = if ($ShowName) { $ShowName } else { $GrandParentDir }
                                    Season  = if ($FinalSeason) { $FinalSeason } else { 'Extras' }
                                    Episode = if ($FinalEpisode) { $FinalEpisode } else { 'N/A' }
                                    OldPath = $File.FullName
                                    NewPath = $NewPath
                                })
                            }
                        } catch {
                            $Stats.Errors++
                            Write-Warning "`nFailed to rename file $($File.Name): $_"
                        }
                    }
                } else {
                    $Stats.FilesSkipped++
                }
            }

            # =================================================================
            # PHASE 2: DIRECTORY PROCESSING (Bottom-Up execution)
            # =================================================================
            if (-not $SkipDirectoryRename) {
                $SubFolders = Get-ChildItem -Path $Dir -Recurse -Directory |
                    Sort-Object -Property { $_.FullName.Length } -Descending

                $TotalDirs = $SubFolders.Count
                $DirCounter = 0

                foreach ($SubDir in $SubFolders) {
                    $DirCounter++
                    Write-Progress -Activity "Processing Directories" -Status "[$DirCounter/$TotalDirs] $($SubDir.Name)" -PercentComplete (($DirCounter / $TotalDirs) * 100)

                    $ShortDir = if ($SubDir.Name.Length -gt 45) { $SubDir.Name.Substring(0, 42) + "..." } else { $SubDir.Name }
                    Write-Host "`r[Folder $DirCounter/$TotalDirs] Checking: $ShortDir$( ' ' * 15 )" -NoNewline -ForegroundColor Yellow

                    $NewDirName = $null

                    # --- MATCH 1: Standard Season Folder ---
                    if ($SubDir.Name -match $RegexSeasonDir) {
                        $SeasonNum = [int]$Matches.Season
                        $NewDirName = "Season {0}" -f $SeasonNum
                    }
                    # --- MATCH 2: Edge Case - Miscellaneous / Extras Folder Mapping ---
                    elseif ($SubDir.Name -match $RegexExtrasKeywords) {
                        foreach ($Pattern in $ExtrasDirMap.Keys) {
                            if ($SubDir.Name -match $Pattern) {
                                $NewDirName = $ExtrasDirMap[$Pattern]
                                break
                            }
                        }
                    }

                    # --- EXECUTE DIRECTORY RENAME ---
                    if ($NewDirName) {
                        $NewDirPath = Join-Path -Path $SubDir.Parent.FullName -ChildPath $NewDirName

                        if ($SubDir.Name -eq $NewDirName) {
                            $Stats.DirsSkipped++
                            continue
                        }

                        if ($PSCmdlet.ShouldProcess($SubDir.FullName, "Rename directory to $NewDirName")) {
                            try {
                                Rename-Item -Path $SubDir.FullName -NewName $NewDirName -ErrorAction Stop
                                $Stats.DirsRenamed++

                                Write-Host "`r[Folder $DirCounter/$TotalDirs] Renamed : $NewDirName$( ' ' * 15 )" -NoNewline -ForegroundColor Green

                                if ($PassThru) {
                                    $AuditLog.Add([PSCustomObject]@{
                                        Status  = 'Success'
                                        Type    = 'Directory'
                                        Show    = $SubDir.Parent.Name
                                        Season  = if ($SeasonNum) { $SeasonNum } else { 'Extras' }
                                        Episode = $null
                                        OldPath = $SubDir.FullName
                                        NewPath = $NewDirPath
                                    })
                                }
                            } catch {
                                $Stats.Errors++
                                Write-Warning "`nFailed to rename directory $($SubDir.Name): $_"
                            }
                        }
                    } else {
                        $Stats.DirsSkipped++
                    }
                }
            }
        }
    }

    end {
        Write-Host "`r$( ' ' * 75 )`r" -NoNewline

        Write-Host " Total Files Scanned  : $($Stats.FilesFound)" -ForegroundColor White
        Write-Host " Files Renamed        : $($Stats.FilesRenamed)" -ForegroundColor Green
        Write-Host " Files Unchanged/Skip : $($Stats.FilesSkipped)" -ForegroundColor DarkGray

        if (-not $SkipDirectoryRename) {
            Write-Host " Directories Renamed  : $($Stats.DirsRenamed)" -ForegroundColor Green
            Write-Host " Directories Skipped  : $($Stats.DirsSkipped)" -ForegroundColor DarkGray
        }

        if ($Stats.Errors -gt 0) {
            Write-Host " Errors / Failed      : $($Stats.Errors)" -ForegroundColor Red
        }

        if ($PassThru) {
            Write-Output $AuditLog
        }
    }
}

Export-ModuleMember -Function Rename-MediaFile
