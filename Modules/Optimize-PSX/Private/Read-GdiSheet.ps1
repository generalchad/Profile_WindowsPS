function Read-GdiSheet {
    <#
    .SYNOPSIS
        Parses a Dreamcast .gdi sheet into its track list.
    .DESCRIPTION
        A GDI sheet opens with the track count, followed by one line per track:

            <index> <lba> <type> <sectorSize> <filename> <offset>

        Read-only: the sheet is never modified. Track filenames are resolved
        against the sheet's own directory.

        The declared track count is compared with the number of parsed lines and
        reported as a mismatch when they disagree, which identifies a truncated
        or hand-edited sheet before chdman is invoked.
    .PARAMETER Path
        Full path to the .gdi file.
    .OUTPUTS
        PSCustomObject:
          Path          the sheet
          Directory     containing directory
          DeclaredCount track count from the first line
          Tracks        List of PSCustomObject { Index, Lba, Type, SectorSize, Leaf, ResolvedPath, Exists }
          MissingFiles  leaf names that do not exist on disk
          ParseError    populated when the sheet is unreadable or malformed
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    $result = [pscustomobject]@{
        PSTypeName    = 'Optimize-PSX.GdiSheet'
        Path          = $Path
        Directory     = [System.IO.Path]::GetDirectoryName($Path)
        DeclaredCount = 0
        Tracks        = [System.Collections.Generic.List[pscustomobject]]::new()
        MissingFiles  = [System.Collections.Generic.List[string]]::new()
        ParseError    = $null
    }

    try {
        $lines = [System.IO.File]::ReadAllLines($Path)
    } catch {
        $result.ParseError = "Could not read GDI sheet: $($_.Exception.Message)"
        return $result
    }

    $lines = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -lt 2) {
        $result.ParseError = 'GDI sheet contains no track entries.'
        return $result
    }

    $declared = 0
    if ([int]::TryParse($lines[0].Trim(), [ref]$declared)) {
        $result.DeclaredCount = $declared
    }

    foreach ($line in $lines[1..($lines.Count - 1)]) {
        $match = [regex]::Match($line, $script:RegexGdiTrack)
        if (-not $match.Success) { continue }

        $leaf = if ($match.Groups['Quoted'].Success) {
            $match.Groups['Quoted'].Value
        } else {
            $match.Groups['Bare'].Value
        }

        $resolved = [System.IO.Path]::Combine($result.Directory, $leaf)
        $exists = [System.IO.File]::Exists($resolved)

        $result.Tracks.Add([pscustomobject]@{
            Index        = [int]$match.Groups['Index'].Value
            Lba          = [int]$match.Groups['Lba'].Value
            Type         = [int]$match.Groups['Type'].Value
            SectorSize   = [int]$match.Groups['SectorSize'].Value
            Leaf         = $leaf
            ResolvedPath = $resolved
            Exists       = $exists
        })

        if (-not $exists) { $result.MissingFiles.Add($leaf) }
    }

    if ($result.Tracks.Count -eq 0) {
        $result.ParseError = 'No parseable track lines found in GDI sheet.'
    } elseif ($result.DeclaredCount -gt 0 -and $result.DeclaredCount -ne $result.Tracks.Count) {
        $result.ParseError = "Track count mismatch: sheet declares $($result.DeclaredCount) but $($result.Tracks.Count) parsed."
    }

    return $result
}
