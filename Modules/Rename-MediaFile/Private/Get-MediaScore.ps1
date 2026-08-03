function Get-MediaScore {
    <#
    .SYNOPSIS
        Weighted Movie/TV classifier.
    .DESCRIPTION
        Returns a score where a positive value indicates TV content and a value
        of zero or less indicates a Movie. Signals considered: explicit episode
        markers, sibling media counts, season-like parent folders, part/volume
        or absolute numbering, and the presence of a standalone release year.
    .PARAMETER File
        The media file being classified.
    .PARAMETER SiblingMediaCount
        How many media files share the file's directory.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [System.IO.FileInfo]$File,

        [Parameter(Position = 1)]
        [int]$SiblingMediaCount
    )

    $Score  = 0
    $Name   = $File.BaseName
    $Parent = $File.Directory.Name
    $HasEpisodeMarker = $Name -match $script:RegexEpisodeMarker

    if ($HasEpisodeMarker)                        { $Score += 100 }
    if ($SiblingMediaCount -ge 2)                 { $Score += 80 }
    if ($Parent -match $script:RegexSeasonDir -or
        $Parent -match '(?i)\bspecials?\b')       { $Score += 80 }
    if ($Name -match $script:RegexPartVol -or
        $Name -match $script:RegexAbsoluteNumber) { $Score += 30 }
    if ($SiblingMediaCount -le 1)                 { $Score -= 40 }
    if (-not $HasEpisodeMarker -and
        $Name -match $script:RegexYear)           { $Score -= 80 }

    return $Score
}
