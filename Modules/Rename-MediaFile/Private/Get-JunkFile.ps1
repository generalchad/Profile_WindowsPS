function Get-JunkFile {
    <#
    .SYNOPSIS
        Identifies scene-release litter that is safe to remove.
    .DESCRIPTION
        Deliberately conservative. A file must satisfy ALL THREE conditions:

          1. Its extension is on the junk list. .nfo is excluded because
             Jellyfin and Kodi consume it as real metadata.
          2. Its name matches a known junk pattern.
          3. It is smaller than the size ceiling, so a large legitimate
             document is never caught by a loose name match. The ceiling
             is per-extension: images get a far larger allowance than
             text because scene banners routinely run 50-300 KB.

    .PARAMETER Directory
        Root directory to scan recursively.
    .OUTPUTS
        FileInfo objects considered junk.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Directory
    )

    $Junk = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

    foreach ($File in @(Get-ChildItem -LiteralPath $Directory -File -Recurse -ErrorAction SilentlyContinue)) {

        $Extension = $File.Extension.ToLower()

        # 1. Extension gate
        if ($script:JunkExtensions -notcontains $Extension) { continue }

        # 2. Size gate. Use the per-extension ceiling when one is defined,
        #    otherwise fall back to the conservative global value.
        $Ceiling = if ($script:JunkSizeCeilingByExtension -and
                       $script:JunkSizeCeilingByExtension.ContainsKey($Extension)) {
            $script:JunkSizeCeilingByExtension[$Extension]
        } else {
            $script:JunkSizeCeiling
        }
        if ($File.Length -gt $Ceiling) { continue }

        # 3. Name gate (test both with and without extension)
        $Matched = $false
        foreach ($Pattern in $script:JunkFilePatterns) {
            if ($File.BaseName -match $Pattern -or $File.Name -match $Pattern) {
                $Matched = $true
                break
            }
        }

        if ($Matched) { $Junk.Add($File) }
    }

    return $Junk.ToArray()
}
