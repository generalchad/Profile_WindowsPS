function Get-SubtitleLanguage {
    <#
    .SYNOPSIS
        Determines the language of a subtitle file using a three tier cascade.
    .DESCRIPTION
        Tier 1  Filename / folder tokens. Cheap, no I/O, correct most of the time.
        Tier 2  Content analysis: Unicode script detection, then weighted stop
                word scoring for Latin script languages.
        Tier 3  Caller driven prompt (handled by Read-SubtitleLanguageChoice).

        Detection failure is never fatal. A $null Code simply means the file
        keeps or loses its tag rather than blocking the rename.
    .PARAMETER File
        The subtitle file to inspect.
    .PARAMETER VideoBaseName
        Base name of the associated video. Tokens shared with the video name are
        ignored so release-group noise is not mistaken for a language tag.
    .PARAMETER Mode
        Auto          filename, then content.
        FilenameOnly  filename tokens only, never reads the file.
        None          no detection at all.
    .OUTPUTS
        PSCustomObject with Code, Confidence (High/Medium/Low/None), Source and Flags.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [System.IO.FileInfo]$File,

        [Parameter(Position = 1)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$VideoBaseName,

        [Parameter(Position = 2)]
        [ValidateSet('Auto', 'FilenameOnly', 'None')]
        [string]$Mode = 'Auto'
    )

    $Result = [PSCustomObject]@{
        Code       = $null
        Confidence = 'None'
        Source     = 'None'
        Flags      = @()
    }

    $BaseName = $File.BaseName

    # ---------------------------------------------------------------
    # Trait flags (SDH / forced / CC) come from the name in every mode.
    # ---------------------------------------------------------------
    $Flags = [System.Collections.Generic.List[string]]::new()
    foreach ($Flag in $script:SubtitleFlagMap.Keys) {
        if ($BaseName -match $script:SubtitleFlagMap[$Flag] -or
            $File.Directory.Name -match $script:SubtitleFlagMap[$Flag]) {
            # 'cc' is redundant when 'sdh' already applies.
            if ($Flag -eq 'cc' -and $Flags.Contains('sdh')) { continue }
            $Flags.Add($Flag)
        }
    }
    $Result.Flags = $Flags.ToArray()

    if ($Mode -eq 'None') { return $Result }

    # ===============================================================
    # TIER 1: FILENAME AND FOLDER TOKENS
    # ===============================================================

    # Strip the video's own name so shared release tokens cannot match.
    $Candidate = $BaseName
    if (-not [string]::IsNullOrWhiteSpace($VideoBaseName) -and
        $Candidate.StartsWith($VideoBaseName, [StringComparison]::OrdinalIgnoreCase)) {
        $Candidate = $Candidate.Substring($VideoBaseName.Length)
    }

    # MakeMKV / Handbrake extractions prefix a track index: "2_English".
    $Candidate = $Candidate -replace '^\s*\d+[\s._-]+', ''

    # Search the trailing tokens first: language tags live at the end.
    $Tokens = @($Candidate -split '[\s._\-\[\]()]+' | Where-Object { $_ })
    [array]::Reverse($Tokens)

    foreach ($Token in $Tokens) {
        $Key = $Token.ToLower()
        if ($script:LanguageMap.ContainsKey($Key)) {
            $Result.Code = $script:LanguageMap[$Key]
            $Result.Confidence = 'High'
            $Result.Source = 'Filename'
            return $Result
        }
    }

    # Nothing in the file name: the containing folder may be named for the
    # language instead (e.g. Subs\English\01.srt).
    $FolderName = $File.Directory.Name
    if ($FolderName -and $script:SubtitleFolderNames -notcontains $FolderName.ToLower()) {
        foreach ($Token in @($FolderName -split '[\s._\-\[\]()]+' | Where-Object { $_ })) {
            $Key = $Token.ToLower()
            if ($script:LanguageMap.ContainsKey($Key)) {
                $Result.Code = $script:LanguageMap[$Key]
                $Result.Confidence = 'High'
                $Result.Source = 'FolderName'
                return $Result
            }
        }
    }

    if ($Mode -eq 'FilenameOnly') { return $Result }

    # ===============================================================
    # TIER 2: CONTENT ANALYSIS
    # ===============================================================

    # Image based formats carry no text: detection is impossible by design.
    if ($script:ImageSubtitleExtensions -contains $File.Extension.ToLower()) {
        return $Result
    }

    $Sample = Read-SubtitleSample -Path $File.FullName
    if (-not $Sample -or $Sample.Count -eq 0) { return $Result }

    $Text = ($Sample -join ' ')
    if ($Text.Length -lt 40) { return $Result }

    # --- 2a. Unicode script detection --------------------------------
    $ScriptCounts = @{}
    foreach ($ScriptName in $script:ScriptRanges.Keys) {
        $Count = [regex]::Matches($Text, $script:ScriptRanges[$ScriptName]).Count
        if ($Count -gt 0) { $ScriptCounts[$ScriptName] = $Count }
    }

    if ($ScriptCounts.Count -gt 0) {
        $Dominant = ($ScriptCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)

        # Require the script to be a real presence, not a stray glyph.
        if ($Dominant.Value -ge 10) {
            $ScriptName = $Dominant.Key

            # Japanese mixes Kana with Han: any Kana at all means Japanese, not Chinese.
            if ($ScriptName -eq 'Han' -and $ScriptCounts.ContainsKey('Kana')) { $ScriptName = 'Kana' }
            # Korean mixes Hangul with occasional Han.
            if ($ScriptName -eq 'Han' -and $ScriptCounts.ContainsKey('Hangul')) { $ScriptName = 'Hangul' }

            if ($ScriptName -eq 'Cyrillic') {
                $Result.Code = 'rus'
                foreach ($Lang in $script:CyrillicHints.Keys) {
                    if ([regex]::Matches($Text, $script:CyrillicHints[$Lang]).Count -ge 3) {
                        $Result.Code = $Lang
                        break
                    }
                }
                $Result.Confidence = 'Medium'
                $Result.Source = 'Content'
                return $Result
            }

            if ($ScriptName -eq 'Arabic') {
                $Result.Code = 'ara'
                foreach ($Lang in $script:ArabicHints.Keys) {
                    if ([regex]::Matches($Text, $script:ArabicHints[$Lang]).Count -ge 3) {
                        $Result.Code = $Lang
                        break
                    }
                }
                $Result.Confidence = 'Medium'
                $Result.Source = 'Content'
                return $Result
            }

            if ($script:ScriptToLanguage.ContainsKey($ScriptName)) {
                $Result.Code = $script:ScriptToLanguage[$ScriptName]
                $Result.Confidence = 'High'
                $Result.Source = 'Content'
                return $Result
            }
        }
    }

    # --- 2b. Latin script stop word scoring ---------------------------
    $Words = @($Text.ToLower() -split '[^\p{L}'']+' | Where-Object { $_.Length -ge 2 })
    if ($Words.Count -lt 20) { return $Result }

    $Frequency = @{}
    foreach ($Word in $Words) {
        if ($Frequency.ContainsKey($Word)) { $Frequency[$Word]++ } else { $Frequency[$Word] = 1 }
    }

    $Scores = @{}
    foreach ($Lang in $script:StopWords.Keys) {
        $Total = 0
        foreach ($Stop in $script:StopWords[$Lang].Keys) {
            if ($Frequency.ContainsKey($Stop)) {
                $Total += $Frequency[$Stop] * $script:StopWords[$Lang][$Stop]
            }
        }
        # Normalise so long samples do not automatically outrank short ones.
        $Scores[$Lang] = $Total / [Math]::Sqrt($Words.Count)
    }

    $Ranked = @($Scores.GetEnumerator() | Sort-Object Value -Descending)
    if ($Ranked.Count -eq 0 -or $Ranked[0].Value -le 0) { return $Result }

    $Best = $Ranked[0]
    $Runner = if ($Ranked.Count -gt 1) { $Ranked[1].Value } else { 0 }

    # Confidence keys off both absolute strength and the margin over second place.
    if ($Best.Value -ge 1.5 -and $Best.Value -gt ($Runner * 2)) {
        $Result.Code = $Best.Key
        $Result.Confidence = 'High'
        $Result.Source = 'Content'
    } elseif ($Best.Value -ge 0.8 -and $Best.Value -gt ($Runner * 1.3)) {
        $Result.Code = $Best.Key
        $Result.Confidence = 'Medium'
        $Result.Source = 'Content'
    } elseif ($Best.Value -gt 0) {
        $Result.Code = $Best.Key
        $Result.Confidence = 'Low'
        $Result.Source = 'Content'
    }

    return $Result
}
