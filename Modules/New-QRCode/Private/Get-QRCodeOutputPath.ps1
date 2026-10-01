function Get-QRCodeOutputPath {
    <#
    .SYNOPSIS
        Resolves the file path a QR code is written to.

    .DESCRIPTION
        A -Path that is an existing directory, ends in a separator, or has no
        extension is treated as a folder; the file name is derived from the text
        so bulk output stays readable. Otherwise the path is used verbatim.

    .PARAMETER Path
        The caller-supplied -Path.

    .PARAMETER Text
        The payload being encoded, used to name the file in directory mode.

    .PARAMETER Label
        An optional friendly name (CSV Label column or preset) preferred over the
        text when naming the file in directory mode.

    .PARAMETER Format
        PNG or SVG; selects the extension in directory mode.

    .PARAMETER Index
        The 1-based position in the input set, used to disambiguate collisions.

    .OUTPUTS
        System.String. The absolute output file path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter()]
        [string]$Label,

        [Parameter(Mandatory)]
        [ValidateSet('PNG', 'SVG')]
        [string]$Format,

        [Parameter(Mandatory)]
        [int]$Index
    )

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $altSeparator = [System.IO.Path]::AltDirectorySeparatorChar

    $isDirectory = (Test-Path -LiteralPath $Path -PathType Container) -or
        $Path.EndsWith($separator) -or
        $Path.EndsWith($altSeparator) -or
        [string]::IsNullOrEmpty([System.IO.Path]::GetExtension($Path))

    if (-not $isDirectory) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    $directory = $Path.TrimEnd([char[]]@($separator, $altSeparator))
    $extension = if ($Format -eq 'SVG') { '.svg' } else { '.png' }

    $nameSource = if (-not [string]::IsNullOrWhiteSpace($Label)) { $Label } else { $Text }
    $slug = Get-QRCodeSlug -Text $nameSource
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'qrcode' }

    $candidate = Join-Path $directory ($slug + $extension)
    $suffix = $Index
    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $directory ('{0}-{1}{2}' -f $slug, $suffix, $extension)
        $suffix++
    }
    return $candidate
}
