function Format-MediaTitle {
    <#
    .SYNOPSIS
        Normalises separators, strips scene junk and title-cases a candidate title.
    .DESCRIPTION
        Converts scene separators to spaces, drops everything following the final
        scene-junk token (that tail is release-group noise), removes any remaining
        junk tokens, then title-cases the result.
    .PARAMETER Raw
        The raw text to clean.
    .PARAMETER StripBrackets
        Also remove (parenthesised), [bracketed] and {braced} groups.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Raw,

        [switch]$StripBrackets
    )

    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    $Text = $Raw

    if ($StripBrackets) { $Text = $Text -replace $script:RegexBracketed, ' ' }

    # Convert scene separators to spaces before junk removal so \b boundaries behave predictably.
    $Text = $Text -replace '[._]+', ' '

    # Remember where the last junk token appeared; everything past it is release-group noise.
    $JunkMatches = [regex]::Matches($Text, $script:RegexSceneJunk)
    if ($JunkMatches.Count -gt 0) {
        $Last = $JunkMatches[$JunkMatches.Count - 1]
        $Text = $Text.Substring(0, $Last.Index)
    }

    $Text = $Text -replace $script:RegexSceneJunk, ' '
    $Text = $Text -replace '\s+', ' '
    $Text = $Text.Trim(' ', '-', '_', '.', ',')

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    # ToTitleCase leaves ALL-CAPS words untouched, so lower first for consistent output.
    return (Get-Culture).TextInfo.ToTitleCase($Text.ToLower())
}
