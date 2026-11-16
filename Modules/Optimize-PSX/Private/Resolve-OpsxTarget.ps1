function Resolve-OpsxTarget {
    <#
    .SYNOPSIS
        Classifies one -Path argument as a folder, an archive or a disc image.
    .DESCRIPTION
        A run can be aimed at a folder, at an archive, or at a disc image. This
        decides which of those a single argument is and returns the files the
        file index must contain for that target.

        Disc image targets are resolved to the sheet that describes the disc,
        because compressing a payload on its own silently loses data:

          Sheet target   the sheet plus the tracks it references, so the size
                         accounting covers the disc rather than the few hundred
                         bytes of the .cue itself.
          ISO target     the ISO, unless a sheet of the same base name sits
                         beside it, in which case that sheet is used and the
                         ISO is left alone.
          Track target   the sheet that describes it: the sibling sheet of the
                         same base name, or the only sheet in the folder that
                         references the file. A bare track file cannot be
                         converted, because chdman needs the sector layout the
                         sheet carries and a lone .bin from a multi-track set
                         would produce a CHD missing every other track.

        A .chd is reported as already converted, and any other file type as
        unsupported. Both are returned rather than thrown so that a pipeline of
        mixed files can continue past the ones it cannot use.
    .PARAMETER Path
        A single path supplied to -Path.
    .OUTPUTS
        PSCustomObject:
          Status   Directory, Archive, DiscImage, Converted, Unsupported or NotFound
          Path     resolved full path, or $null when resolution failed
          Files    List[FileInfo] the index must include
          Message  detail for a status the caller has to report
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    $result = [pscustomobject]@{
        PSTypeName = 'Optimize-PSX.Target'
        Status     = 'NotFound'
        Path       = $null
        Files      = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        Message    = $null
    }

    try {
        $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        $result.Message = "Path not found: '$Path'."
        return $result
    }

    $result.Path = $resolved

    if ([System.IO.Directory]::Exists($resolved)) {
        $result.Status = 'Directory'
        return $result
    }

    if (-not [System.IO.File]::Exists($resolved)) {
        $result.Status = 'Unsupported'
        $result.Message = "'$resolved' is neither a file nor a folder."
        return $result
    }

    $file = [System.IO.FileInfo]::new($resolved)
    $extension = $file.Extension.ToLowerInvariant()

    if ($extension -in $script:ArchiveExtensions) {
        $result.Status = 'Archive'
        $result.Files.Add($file)
        return $result
    }

    if ($extension -in $script:SheetExtensions) {
        $result.Status = 'DiscImage'
        foreach ($member in Get-OpsxSheetScope -Sheet $file) { $result.Files.Add($member) }
        return $result
    }

    if ($extension -in $script:TrackExtensions) {
        $sheet = $null
        foreach ($sheetExtension in $script:SheetExtensions) {
            $candidate = [System.IO.Path]::Combine($file.DirectoryName, "$($file.BaseName)$sheetExtension")
            if ([System.IO.File]::Exists($candidate)) {
                $sheet = [System.IO.FileInfo]::new($candidate)
                break
            }
        }

        # Dreamcast sets name their tracks independently of the sheet
        # ('track01.bin' under 'Sonic.gdi'), so a same-name match is not always
        # available. A sheet in the same folder that actually references the
        # file is equally unambiguous, provided exactly one does.
        if (-not $sheet) {
            $referencing = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
            foreach ($sheetExtension in $script:SheetExtensions) {
                try {
                    foreach ($sheetPath in [System.IO.Directory]::EnumerateFiles($file.DirectoryName, "*$sheetExtension")) {
                        $candidateSheet = [System.IO.FileInfo]::new($sheetPath)
                        $scope = @(Get-OpsxSheetScope -Sheet $candidateSheet)
                        if (@($scope | Where-Object { $_.FullName -eq $file.FullName }).Count -gt 0) {
                            $referencing.Add($candidateSheet)
                        }
                    }
                } catch {
                    Write-OpsxLog "Could not inspect sheets in '$($file.DirectoryName)': $($_.Exception.Message)" -Level Detail
                }
            }

            if ($referencing.Count -eq 1) {
                $sheet = $referencing[0]
            } elseif ($referencing.Count -gt 1 -and $extension -ne '.iso') {
                $result.Status = 'Unsupported'
                $result.Message = "'$($file.Name)' is referenced by $($referencing.Count) sheets ($((($referencing | ForEach-Object Name) -join ', '))); target the sheet that describes the disc."
                return $result
            }
        }

        if ($sheet) {
            $result.Status = 'DiscImage'
            $result.Message = "'$($file.Name)' is described by '$($sheet.Name)'; using the sheet."
            foreach ($member in Get-OpsxSheetScope -Sheet $sheet) { $result.Files.Add($member) }
            return $result
        }

        if ($extension -eq '.iso') {
            $result.Status = 'DiscImage'
            $result.Files.Add($file)
            return $result
        }

        $result.Status = 'Unsupported'
        $result.Message = "'$($file.Name)' is a track file with no sheet referencing it; target the .cue, .gdi or .ccd that describes the disc."
        return $result
    }

    if ($extension -eq '.chd') {
        $result.Status = 'Converted'
        $result.Message = "'$($file.Name)' is already a CHD."
        return $result
    }

    $result.Status = 'Unsupported'
    $result.Message = "'$($file.Name)' is not an archive or a disc image."
    return $result
}
