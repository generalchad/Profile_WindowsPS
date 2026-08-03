function Resolve-EpisodeName {
    <#
    .SYNOPSIS
        Attempts to extract Show / Season / Episode / Title from a media file.
    .DESCRIPTION
        Handles three shapes:
          1.   Show.Name.S01E01.Episode.Title      (inline show name)
          1.5  S01E01 - Title / 1x01               (bare marker, show from folder)
          2.   Episode Three - Title               (textual episode number)

        Each match is snapshotted immediately because $Matches is overwritten by
        every subsequent -match. Running as a discrete function also gives each
        call its own $Matches, which removes the clobbering hazard entirely.
    .PARAMETER BaseName
        File base name (no extension).
    .PARAMETER ParentDirectory
        Name of the containing folder.
    .PARAMETER GrandParentDirectory
        Name of the folder above that, if any.
    .OUTPUTS
        PSCustomObject with Show, Season, Episode and Title, or $null.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$BaseName,

        [Parameter(Position = 1)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ParentDirectory,

        [Parameter(Position = 2)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$GrandParentDirectory
    )

    $ShowName = $null; $SeasonStr = $null; $EpisodeStr = $null; $EpisodeTitle = $null

    # --- SCENARIO 1: Standard inline filename ---
    if ($BaseName -match $script:RegexScenario1 -and $Matches.Show.Trim()) {
        $M = @{} + $Matches
        $ShowName   = $M.Show -replace '[._\s]+', ' '
        $SeasonStr  = $M.Season
        $EpisodeStr = $M.Episode
        if ($M.Title) { $EpisodeTitle = $M.Title }
    }
    # --- SCENARIO 1.5: Standalone SxxEyy inside an organised folder ---
    elseif ($BaseName -match $script:RegexStandalone) {
        $M = @{} + $Matches
        $SeasonStr  = $M.Season
        $EpisodeStr = $M.Episode
        if ($M.Title) { $EpisodeTitle = $M.Title }

        # Walk upward looking for a show name.
        if ($ParentDirectory -match $script:RegexSeasonDir) {
            $PM = @{} + $Matches
            if (-not [string]::IsNullOrWhiteSpace($PM.Show)) {
                $ShowName = $PM.Show -replace '[._\s]+', ' '
            }
        }

        if ([string]::IsNullOrWhiteSpace($ShowName) -and $GrandParentDirectory) {
            # Grandparent may itself be a box set folder ("Show Complete Series 1 2 3") - strip that down.
            if ($GrandParentDirectory -match $script:RegexSeasonDir) {
                $GM = @{} + $Matches
                $ShowName = if (-not [string]::IsNullOrWhiteSpace($GM.Show)) {
                    $GM.Show -replace '[._\s]+', ' '
                } else {
                    $GrandParentDirectory
                }
            } else {
                $ShowName = $GrandParentDirectory
            }
        }
    }
    # --- SCENARIO 2: Textual number fallback (Episode Three) ---
    elseif ($BaseName -match $script:RegexWordEpisode) {
        $FM = @{} + $Matches
        $TargetWord = $FM.Word.ToLower()

        if ($script:WordMap.ContainsKey($TargetWord) -and $ParentDirectory -match $script:RegexSeasonDir) {
            $PM = @{} + $Matches
            $ShowName   = if (-not [string]::IsNullOrWhiteSpace($PM.Show)) { $PM.Show -replace '[._\s]+', ' ' } else { $GrandParentDirectory }
            $SeasonStr  = $PM.Season
            $EpisodeStr = $script:WordMap[$TargetWord]
            if ($FM.Title) { $EpisodeTitle = $FM.Title }
        }
    }

    if (-not ($ShowName -and $SeasonStr -and $EpisodeStr)) { return $null }

    return [PSCustomObject]@{
        Show    = $ShowName
        Season  = $SeasonStr
        Episode = $EpisodeStr
        Title   = $EpisodeTitle
    }
}
