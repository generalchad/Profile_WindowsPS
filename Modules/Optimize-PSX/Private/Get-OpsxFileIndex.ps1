function Get-OpsxFileIndex {
    <#
    .SYNOPSIS
        Builds a file index from folders and from explicit files.
    .DESCRIPTION
        Every later phase reads from this index rather than re-enumerating the
        tree, so the phases share one scan instead of each performing its own.
        The index is rebuilt only when the contents of the scope change, which
        in practice means after an archive has been extracted.

        Two sources feed the index:

          Path         folders walked recursively
          IncludeFile  individual files added verbatim, for runs aimed at an
                       archive or a disc image rather than at a folder

        Files are deduplicated by full path. A file handed over explicitly that
        also sits under a walked folder is therefore indexed once, which lets
        the caller union folder targets, file targets and the CHDs a run
        produced without double counting any of them.

        Enumeration uses System.IO.Directory directly, bypassing the PowerShell
        provider. Recursion is explicit rather than using
        SearchOption.AllDirectories so that a single unreadable subdirectory
        skips only itself instead of aborting the whole scan.

        Directory reparse points are not followed. A junction pointing at an
        ancestor would recurse indefinitely, and one pointing at another volume
        would silently pull unrelated files into the batch.
    .PARAMETER Path
        Root folders to index. May be empty when files are supplied explicitly.
    .PARAMETER IncludeFile
        Files to index regardless of Path.
    .PARAMETER Recurse
        Walk subdirectories. Enabled by default.
    .OUTPUTS
        PSCustomObject:
          Roots       the indexed folders
          ByExtension hashtable of lowercase extension -> List[FileInfo]
          All         List[FileInfo] of everything found
          TotalBytes  sum of all file lengths
          Count       file count
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Position = 0)]
        [AllowEmptyCollection()]
        [string[]]$Path = @(),

        [AllowEmptyCollection()]
        [System.IO.FileInfo[]]$IncludeFile = @(),

        [switch]$Recurse = $true
    )

    $byExtension = @{}
    $all = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    [long]$totalBytes = 0

    # First pass collects paths from both sources, second pass stats each one
    # exactly once. Statting during the walk would make deduplication against
    # IncludeFile impossible without reading some files twice.
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $filePaths = [System.Collections.Generic.List[string]]::new()

    $stack = [System.Collections.Generic.Stack[string]]::new()
    foreach ($root in $Path) { $stack.Push($root) }

    # Second line of defence against a cyclic link that somehow presents
    # without the ReparsePoint attribute, as can happen over SMB. It also
    # collapses overlapping roots, where a folder target and a file target
    # resolve to the same subtree.
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()

        if (-not $visited.Add($current)) { continue }

        try {
            foreach ($filePath in [System.IO.Directory]::EnumerateFiles($current)) {
                if ($seen.Add($filePath)) { $filePaths.Add($filePath) }
            }

            if ($Recurse) {
                foreach ($dirPath in [System.IO.Directory]::EnumerateDirectories($current)) {
                    try {
                        $dirInfo = [System.IO.DirectoryInfo]::new($dirPath)
                        if ($dirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                            Write-OpsxLog "Skipping reparse point: $dirPath" -Level Detail
                            continue
                        }
                        $stack.Push($dirInfo.FullName)
                    } catch {
                        Write-OpsxLog "Skipping unreadable directory '$dirPath': $($_.Exception.Message)" -Level Detail
                    }
                }
            }
        } catch [System.UnauthorizedAccessException] {
            Write-OpsxLog "Access denied, skipping: $current" -Level Detail
        } catch {
            Write-OpsxLog "Error enumerating '$current': $($_.Exception.Message)" -Level Detail
        }
    }

    foreach ($file in $IncludeFile) {
        if (-not [System.IO.File]::Exists($file.FullName)) {
            Write-OpsxLog "Target file vanished before it could be indexed: $($file.FullName)" -Level Detail
            continue
        }
        if ($seen.Add($file.FullName)) { $filePaths.Add($file.FullName) }
    }

    foreach ($filePath in $filePaths) {
        try {
            $info = [System.IO.FileInfo]::new($filePath)

            # Length is read before the entry is recorded: a file deleted
            # between enumeration and stat must be skipped here rather than
            # fault a later phase.
            $length = $info.Length
            $ext = $info.Extension.ToLowerInvariant()

            if (-not $byExtension.ContainsKey($ext)) {
                $byExtension[$ext] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
            }
            $byExtension[$ext].Add($info)
            $all.Add($info)
            $totalBytes += $length
        } catch {
            Write-OpsxLog "Skipping unreadable file '$filePath': $($_.Exception.Message)" -Level Detail
        }
    }

    [pscustomobject]@{
        PSTypeName  = 'Optimize-PSX.FileIndex'
        Roots       = @($Path)
        ByExtension = $byExtension
        All         = $all
        TotalBytes  = $totalBytes
        Count       = $all.Count
    }
}
