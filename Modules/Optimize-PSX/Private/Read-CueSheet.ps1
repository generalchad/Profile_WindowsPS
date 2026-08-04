function Read-CueSheet {
    <#
    .SYNOPSIS
        Parses a .cue sheet into its FILE references and track count.
    .DESCRIPTION
        Read-only analysis: the sheet on disk is never modified. Repair is a
        separate opt-in operation (Repair-CueSheet).

        Encoding is detected from the byte order mark, falling back to UTF-8,
        which decodes plain ASCII sheets correctly and preserves accented
        characters in track filenames. A UTF-16 sheet decoded as single-byte
        text yields interleaved nulls and parses as empty, so detection is
        required rather than optional.

        FILE references are resolved to the sheet's own directory using only the
        leaf name. Sheets authored on other systems may carry forward slashes or
        a full original path, but by the time a sheet is processed its payload
        always sits alongside it.
    .PARAMETER Path
        Full path to the .cue file.
    .OUTPUTS
        PSCustomObject:
          Path            the sheet
          Directory       containing directory
          Encoding        detected encoding name
          HasBom          whether a byte order mark is present
          TrackCount      number of TRACK entries
          FileReferences  List of PSCustomObject { Name, Leaf, Type, ResolvedPath, Exists }
          MissingFiles    references whose target does not exist
          IsSingleFile    exactly one FILE reference
          IsValid         every reference resolves
          ParseError      populated when the sheet could not be read at all
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    $result = [pscustomobject]@{
        PSTypeName     = 'Optimize-PSX.CueSheet'
        Path           = $Path
        Directory      = [System.IO.Path]::GetDirectoryName($Path)
        Encoding       = 'Unknown'
        HasBom         = $false
        TrackCount     = 0
        FileReferences = [System.Collections.Generic.List[pscustomobject]]::new()
        MissingFiles   = [System.Collections.Generic.List[pscustomobject]]::new()
        IsSingleFile   = $false
        IsValid        = $false
        ParseError     = $null
    }

    $text = $null
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)

        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $result.Encoding = 'UTF8-BOM'
            $result.HasBom = $true
            $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
        } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            $result.Encoding = 'UTF16-LE'
            $result.HasBom = $true
            $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
        } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
            $result.Encoding = 'UTF16-BE'
            $result.HasBom = $true
            $text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
        } else {
            $result.Encoding = 'UTF8'
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        }
    } catch {
        $result.ParseError = "Could not read cue sheet: $($_.Exception.Message)"
        return $result
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        $result.ParseError = 'Cue sheet is empty.'
        return $result
    }

    $result.TrackCount = ([regex]::Matches($text, $script:RegexCueTrack)).Count

    foreach ($match in [regex]::Matches($text, $script:RegexCueFile)) {
        $name = if ($match.Groups['Quoted'].Success) {
            $match.Groups['Quoted'].Value
        } else {
            $match.Groups['Bare'].Value
        }

        $leaf = [System.IO.Path]::GetFileName($name.Replace('/', '\'))
        $resolved = [System.IO.Path]::Combine($result.Directory, $leaf)

        $reference = [pscustomobject]@{
            Name         = $name
            Leaf         = $leaf
            Type         = $match.Groups['Type'].Value
            ResolvedPath = $resolved
            Exists       = [System.IO.File]::Exists($resolved)
        }

        $result.FileReferences.Add($reference)
        if (-not $reference.Exists) { $result.MissingFiles.Add($reference) }
    }

    if ($result.FileReferences.Count -eq 0) {
        $result.ParseError = 'Cue sheet contains no FILE directive.'
        return $result
    }

    $result.IsSingleFile = ($result.FileReferences.Count -eq 1)
    $result.IsValid = ($result.MissingFiles.Count -eq 0)

    return $result
}
