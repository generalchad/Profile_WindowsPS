function Get-OpsxFileIndex {
    <#
    .SYNOPSIS
        Walks the target tree once and returns an index bucketed by extension.
    .DESCRIPTION
        Every later phase reads from this index rather than re-enumerating the
        tree, so a run performs exactly one directory walk regardless of how
        many phases are enabled.

        Enumeration uses System.IO.Directory directly, bypassing the PowerShell
        provider. Recursion is explicit rather than using
        SearchOption.AllDirectories so that a single unreadable subdirectory
        skips only itself instead of aborting the whole scan.

        Directory reparse points are not followed. A junction pointing at an
        ancestor would recurse indefinitely, and one pointing at another volume
        would silently pull unrelated files into the batch.
    .PARAMETER Path
        Root directory to index.
    .PARAMETER Recurse
        Walk subdirectories. Enabled by default.
    .OUTPUTS
        PSCustomObject:
          Root        the indexed root
          ByExtension hashtable of lowercase extension -> List[FileInfo]
          All         List[FileInfo] of everything found
          TotalBytes  sum of all file lengths
          Count       file count
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [switch]$Recurse = $true
    )

    $byExtension = @{}
    $all = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    [long]$totalBytes = 0

    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($Path)

    # Second line of defence against a cyclic link that somehow presents
    # without the ReparsePoint attribute, as can happen over SMB.
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()

        if (-not $visited.Add($current)) { continue }

        try {
            foreach ($filePath in [System.IO.Directory]::EnumerateFiles($current)) {
                try {
                    $info = [System.IO.FileInfo]::new($filePath)
                    $ext = $info.Extension.ToLowerInvariant()

                    if (-not $byExtension.ContainsKey($ext)) {
                        $byExtension[$ext] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
                    }
                    $byExtension[$ext].Add($info)
                    $all.Add($info)
                    $totalBytes += $info.Length
                } catch {
                    Write-OpsxLog "Skipping unreadable file '$filePath': $($_.Exception.Message)" -Level Detail
                }
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

    [pscustomobject]@{
        PSTypeName  = 'Optimize-PSX.FileIndex'
        Root        = $Path
        ByExtension = $byExtension
        All         = $all
        TotalBytes  = $totalBytes
        Count       = $all.Count
    }
}
