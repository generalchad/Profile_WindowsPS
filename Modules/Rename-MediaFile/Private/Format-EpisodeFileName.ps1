function Format-EpisodeFileName {
    <#
    .SYNOPSIS
        Builds the final "Show - S01E02 - Title.ext" file name.
    .PARAMETER Episode
        Object produced by Resolve-EpisodeName.
    .PARAMETER Extension
        File extension, including the leading dot.
    .OUTPUTS
        The composed file name, or $null when the show name cleans to nothing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [PSCustomObject]$Episode,

        [Parameter(Mandatory, Position = 1)]
        [string]$Extension
    )

    $ShowName = Format-MediaTitle -Raw $Episode.Show -StripBrackets
    if ([string]::IsNullOrWhiteSpace($ShowName)) { return $null }

    $FinalSeason  = [int]$Episode.Season
    $FinalEpisode = [int]$Episode.Episode

    $EpisodeTitle = if ($Episode.Title) { Format-MediaTitle -Raw $Episode.Title -StripBrackets } else { $null }

    if (-not [string]::IsNullOrWhiteSpace($EpisodeTitle)) {
        return '{0} - S{1:D2}E{2:D2} - {3}{4}' -f $ShowName, $FinalSeason, $FinalEpisode, $EpisodeTitle, $Extension
    }

    return '{0} - S{1:D2}E{2:D2}{3}' -f $ShowName, $FinalSeason, $FinalEpisode, $Extension
}
