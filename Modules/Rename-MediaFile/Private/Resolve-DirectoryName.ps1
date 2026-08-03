function Resolve-DirectoryName {
    <#
    .SYNOPSIS
        Determines the Plex/Jellyfin conformant name for a directory.
    .DESCRIPTION
        Classifies the folder as one of:
          - genuine single season       -> "Season 3"
          - box set / show root         -> bare show title
          - extras container            -> official local-extras folder name
          - movie folder                -> "Title (Year)"
    .PARAMETER Directory
        The directory being evaluated.
    .OUTPUTS
        The new directory name, or $null when no change is warranted.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [System.IO.DirectoryInfo]$Directory
    )

    $DirName = $Directory.Name

    # Does this folder contain child folders that look like seasons? Then it is a show root, not a season.
    $ChildDirs = @(Get-ChildItem -LiteralPath $Directory.FullName -Directory -ErrorAction SilentlyContinue)
    $SeasonChildCount = @($ChildDirs | Where-Object { $_.Name -match $script:RegexSeasonDir }).Count

    $SeasonMatch = [regex]::Match($DirName, $script:RegexSeasonDir)
    $IsBoxSet = $DirName -match $script:RegexBoxSet -or $DirName -match $script:RegexMultiSeasonNumbers

    if ($SeasonMatch.Success -and -not $IsBoxSet -and $SeasonChildCount -lt 2) {
        # Genuine single-season folder.
        return 'Season {0}' -f [int]$SeasonMatch.Groups['Season'].Value
    }

    if ($SeasonMatch.Success -and ($IsBoxSet -or $SeasonChildCount -ge 2)) {
        # Box set / show root: reduce to the bare show title.
        return Format-MediaTitle -Raw $SeasonMatch.Groups['Show'].Value -StripBrackets
    }

    if ($DirName -match $script:RegexExtrasKeywords) {
        foreach ($Pattern in $script:ExtrasDirMap.Keys) {
            if ($DirName -match $Pattern) { return $script:ExtrasDirMap[$Pattern] }
        }
        return $null
    }

    # Movie folder cleanup: "Title (2007) [1080p]" -> "Title (2007)"
    $Movie = Resolve-MovieName -Raw $DirName
    if ($Movie) { return $Movie.Display }

    return $null
}
