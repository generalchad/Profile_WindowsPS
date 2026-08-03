function Format-SubtitleFileName {
    <#
    .SYNOPSIS
        Composes a Plex/Jellyfin conformant subtitle sidecar name.
    .DESCRIPTION
        Produces "<VideoBaseName>.<lang>[.<flag>][.<n>].<ext>", e.g.

            Grandma's Boy (2006).eng.srt
            Grandma's Boy (2006).eng.sdh.srt
            Grandma's Boy (2006).eng.forced.srt
            Grandma's Boy (2006).eng.2.srt      <- disambiguated duplicate

        In LanguageOnly mode the existing base name is preserved and only the
        language tag is corrected, which keeps already-organised libraries intact.
    .PARAMETER VideoBaseName
        The video's final base name (post rename), used as the sidecar stem.
    .PARAMETER Language
        Canonical 3 letter code. When absent the sidecar is left untagged.
    .PARAMETER Flags
        Trait flags such as sdh or forced.
    .PARAMETER Extension
        Subtitle extension including the leading dot.
    .PARAMETER Ordinal
        Disambiguator appended when several subtitles share a language.
    .PARAMETER LanguageOnly
        Preserve the original base name and only normalise the language tag.
    .PARAMETER OriginalBaseName
        Required when -LanguageOnly is used.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$VideoBaseName,

        [Parameter(Position = 1)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Language,

        [Parameter(Position = 2)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Flags = @(),

        [Parameter(Mandatory, Position = 3)]
        [string]$Extension,

        [Parameter(Position = 4)]
        [int]$Ordinal = 1,

        [switch]$LanguageOnly,

        [Parameter(Position = 5)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$OriginalBaseName
    )

    # ---------------------------------------------------------------
    # LanguageOnly: keep the stem, replace only the trailing tag block.
    # ---------------------------------------------------------------
    if ($LanguageOnly) {
        if ([string]::IsNullOrWhiteSpace($OriginalBaseName)) { return $null }
        if ([string]::IsNullOrWhiteSpace($Language)) { return $null }

        $Stem = $OriginalBaseName

        # Peel off any trailing language / flag / ordinal tokens so we do not
        # stack a new tag on top of the old one ("Hero.English.forced" must not
        # become "Hero.English.eng.forced" - that never converges on re-runs).
        #
        # Two distinct cases, because they carry different risks:
        #
        #   Full names ("English", "Deutsch")  - unambiguous in the tag position.
        #       No film title ends in a bare language name after a dot separator,
        #       so these are stripped outright.
        #
        #   Short codes ("en", "it", "no")     - genuinely ambiguous. ".no." could
        #       be Norwegian or the word "no". Restricted to 2-3 characters, which
        #       is the only form a real ISO code ever takes.
        $Changed = $true
        while ($Changed) {
            $Changed = $false
            $LastDot = $Stem.LastIndexOf('.')
            if ($LastDot -le 0) { break }

            $Tail = $Stem.Substring($LastDot + 1).ToLower()

            $IsFlag      = $script:SubtitleFlagMap.Keys -contains $Tail
            $IsOrdinal   = $Tail -match '^\d{1,2}$'
            $IsShortCode = $script:LanguageMap.ContainsKey($Tail) -and $Tail.Length -le 3
            $IsFullName  = $Tail.Length -gt 3 -and
                           $script:LanguageMap.ContainsKey($Tail) -and
                           $Tail -match '^[\p{L}]+$'

            if (-not ($IsFlag -or $IsOrdinal -or $IsShortCode -or $IsFullName)) { break }

            $Remaining = $Stem.Substring(0, $LastDot)

            # Floor: never dissolve the stem into nothing. A sidecar named
            # "English.srt" has no real name to preserve, so keep what is there
            # and let the tag be appended instead of leaving an empty stem.
            if ([string]::IsNullOrWhiteSpace($Remaining)) { break }

            $Stem = $Remaining
            $Changed = $true
        }


        $Parts = [System.Collections.Generic.List[string]]::new()
        $Parts.Add($Stem)
        $Parts.Add($Language)
        foreach ($Flag in $Flags) { $Parts.Add($Flag) }
        if ($Ordinal -gt 1) { $Parts.Add([string]$Ordinal) }

        return ($Parts -join '.') + $Extension
    }

    # ---------------------------------------------------------------
    # Standard: rebuild from the video's name.
    # ---------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($VideoBaseName)) { return $null }

    $Parts = [System.Collections.Generic.List[string]]::new()
    $Parts.Add($VideoBaseName)
    if (-not [string]::IsNullOrWhiteSpace($Language)) { $Parts.Add($Language) }
    foreach ($Flag in $Flags) { $Parts.Add($Flag) }
    if ($Ordinal -gt 1) { $Parts.Add([string]$Ordinal) }

    return ($Parts -join '.') + $Extension
}
