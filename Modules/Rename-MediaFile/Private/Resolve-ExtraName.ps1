function Resolve-ExtraName {
    <#
    .SYNOPSIS
        Builds a cleaned name for bonus / extras content.
    .DESCRIPTION
        Applies when either the file or its parent folder carries an extras
        keyword. Prefixes the grandparent (show/movie) title when the cleaned
        name does not already start with it.
    .PARAMETER BaseName
        File base name (no extension).
    .PARAMETER Extension
        File extension, including the leading dot.
    .PARAMETER ParentDirectory
        Name of the containing folder.
    .PARAMETER GrandParentDirectory
        Name of the folder above that, if any.
    .OUTPUTS
        The composed file name, or $null when this is not extras content.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$BaseName,

        [Parameter(Mandatory, Position = 1)]
        [string]$Extension,

        [Parameter(Position = 2)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ParentDirectory,

        [Parameter(Position = 3)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$GrandParentDirectory
    )

    if ($BaseName -notmatch $script:RegexExtrasKeywords -and
        $ParentDirectory -notmatch $script:RegexExtrasKeywords) {
        return $null
    }

    $Clean = Format-MediaTitle -Raw $BaseName
    if ([string]::IsNullOrWhiteSpace($Clean)) { return $null }

    if ($GrandParentDirectory -and
        $GrandParentDirectory -notmatch $script:RegexExtrasKeywords -and
        $Clean -notmatch "^$([regex]::Escape($GrandParentDirectory))") {

        $ShowPrefix = Format-MediaTitle -Raw $GrandParentDirectory -StripBrackets
        if ($ShowPrefix) { return "$ShowPrefix - $Clean$Extension" }
    }

    return "$Clean$Extension"
}
