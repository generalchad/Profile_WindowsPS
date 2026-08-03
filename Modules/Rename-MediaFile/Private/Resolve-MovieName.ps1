function Resolve-MovieName {
    <#
    .SYNOPSIS
        Pulls "Some Title (2007)" out of a folder name, or "Some.Title.2007" out of a file name.
    .DESCRIPTION
        Prefers a parenthesised year; otherwise falls back to the last standalone
        year in the string. A leading year is treated as part of the title rather
        than a release-year suffix. Returns $null when no usable year is present.
    .PARAMETER Raw
        The folder or file base name to parse.
    .OUTPUTS
        PSCustomObject with Title, Year and Display properties, or $null.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Raw
    )

    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }

    $Year = $null
    $TitlePart = $Raw

    $ParenYear = [regex]::Match($Raw, '\((?<Year>19\d{2}|20\d{2})\)')
    if ($ParenYear.Success) {
        $Year = $ParenYear.Groups['Year'].Value
        $TitlePart = $Raw.Substring(0, $ParenYear.Index)
    } else {
        $YearMatches = [regex]::Matches($Raw, $script:RegexYear)
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

    $Title = Format-MediaTitle -Raw $TitlePart -StripBrackets
    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }

    return [PSCustomObject]@{
        Title   = $Title
        Year    = $Year
        Display = "$Title ($Year)"
    }
}
