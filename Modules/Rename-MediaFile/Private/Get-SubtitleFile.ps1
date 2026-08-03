function Get-SubtitleFile {
    <#
    .SYNOPSIS
        Finds subtitle files belonging to a directory and associates them with a video.
    .DESCRIPTION
        Searches the supplied directory plus one level of recognised subtitle
        subfolders (Subs, Subtitles, ...). Each subtitle is matched to one of the
        directory's videos:

          - single video  -> everything belongs to it
          - many videos   -> longest common prefix, then episode marker matching

        Subtitles that cannot be matched are returned with a $null Video so the
        caller can report them as orphans rather than guessing.

        .idx and .sub form an inseparable VobSub pair. They are grouped so both
        halves always receive the same base name; renaming only one breaks the
        subtitle entirely.
    .PARAMETER Directory
        Directory holding the video files.
    .PARAMETER Videos
        Video FileInfo objects found in that directory.
    .PARAMETER SubtitleExtensions
        Extensions treated as subtitles.
    .OUTPUTS
        PSCustomObject per subtitle group: Files, Video, InSubFolder.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Directory,

        [Parameter(Position = 1)]
        [AllowEmptyCollection()]
        [System.IO.FileInfo[]]$Videos = @(),

        [Parameter(Position = 2)]
        [string[]]$SubtitleExtensions = @('.srt', '.ass', '.ssa', '.sub', '.idx', '.vtt', '.sup')
    )

    $Found = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

    # Subtitles sitting directly beside the video.
    foreach ($F in @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue)) {
        if ($F.Extension.ToLower() -in $SubtitleExtensions) { $Found.Add($F) }
    }

    # Subtitles one level down inside a recognised subtitle folder.
    foreach ($Sub in @(Get-ChildItem -LiteralPath $Directory -Directory -ErrorAction SilentlyContinue)) {
        if ($script:SubtitleFolderNames -notcontains $Sub.Name.ToLower()) { continue }

        foreach ($F in @(Get-ChildItem -LiteralPath $Sub.FullName -File -Recurse -Depth 1 -ErrorAction SilentlyContinue)) {
            if ($F.Extension.ToLower() -in $SubtitleExtensions) { $Found.Add($F) }
        }
    }

    if ($Found.Count -eq 0) { return @() }

    # -----------------------------------------------------------------
    # Group VobSub .idx/.sub pairs so they rename atomically.
    # -----------------------------------------------------------------
    $Groups = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Consumed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($F in $Found) {
        if ($Consumed.Contains($F.FullName)) { continue }

        $Pair = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $Pair.Add($F)
        $Consumed.Add($F.FullName) | Out-Null

        if ($F.Extension -match '(?i)^\.(idx|sub)$') {
            foreach ($Other in $Found) {
                if ($Consumed.Contains($Other.FullName)) { continue }
                if ($Other.DirectoryName -ne $F.DirectoryName) { continue }
                if ($Other.BaseName -ne $F.BaseName) { continue }
                if ($Other.Extension -notmatch '(?i)^\.(idx|sub)$') { continue }

                $Pair.Add($Other)
                $Consumed.Add($Other.FullName) | Out-Null
            }
        }

        $Groups.Add([PSCustomObject]@{
            Files       = $Pair.ToArray()
            Primary     = $Pair[0]
            Video       = $null
            InSubFolder = ($Pair[0].DirectoryName -ne $Directory)
        })
    }

    # -----------------------------------------------------------------
    # Associate each group with a video.
    # -----------------------------------------------------------------
    if ($Videos.Count -eq 1) {
        foreach ($G in $Groups) { $G.Video = $Videos[0] }
        return $Groups.ToArray()
    }

    if ($Videos.Count -eq 0) { return $Groups.ToArray() }

    foreach ($G in $Groups) {
        $SubBase = $G.Primary.BaseName
        $Best = $null
        $BestScore = 0

        foreach ($V in $Videos) {
            $Score = 0

            # Episode markers are decisive when both sides carry one.
            $SubMarker   = [regex]::Match($SubBase, '(?i)\bs(\d{1,2})[\s._-]*e(\d{1,3})\b')
            $VideoMarker = [regex]::Match($V.BaseName, '(?i)\bs(\d{1,2})[\s._-]*e(\d{1,3})\b')

            if ($SubMarker.Success -and $VideoMarker.Success) {
                if ([int]$SubMarker.Groups[1].Value -eq [int]$VideoMarker.Groups[1].Value -and
                    [int]$SubMarker.Groups[2].Value -eq [int]$VideoMarker.Groups[2].Value) {
                    $Score = 1000
                }
            }

            if ($Score -eq 0) {
                # Longest common prefix, case insensitive.
                $Max = [Math]::Min($SubBase.Length, $V.BaseName.Length)
                $Common = 0
                while ($Common -lt $Max -and
                       [char]::ToLowerInvariant($SubBase[$Common]) -eq [char]::ToLowerInvariant($V.BaseName[$Common])) {
                    $Common++
                }
                $Score = $Common
            }

            if ($Score -gt $BestScore) {
                $BestScore = $Score
                $Best = $V
            }
        }

        # Require a meaningful prefix overlap before claiming a match.
        if ($Best -and $BestScore -ge 6) { $G.Video = $Best }
    }

    return $Groups.ToArray()
}
