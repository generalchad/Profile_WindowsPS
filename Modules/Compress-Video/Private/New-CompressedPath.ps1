function Test-AlreadyCompressed {
    <#
    .SYNOPSIS
        Returns $true if a file's base name already carries the
        '_compressed' suffix this module applies.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File
    )

    process {
        return $File.BaseName -match '_compressed$'
    }
}

function New-CompressedPath {
    <#
    .SYNOPSIS
        Computes the destination path for a compressed output file.

    .DESCRIPTION
        Internal helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter()]
        [string]$CustomPath,

        [Parameter()]
        [switch]$IsBatchMode
    )

    process {
        if ($CustomPath) {
            # If processing multiple files, treat CustomPath strictly as a directory
            if ($IsBatchMode) {
                return Join-Path $CustomPath ($File.BaseName + "_compressed.mp4")
            }

            if (Test-Path $CustomPath -PathType Container) {
                return Join-Path $CustomPath ($File.BaseName + "_compressed.mp4")
            }
            if ($CustomPath -match '\.mp4$') {
                return $CustomPath
            }
            return Join-Path $CustomPath ($File.BaseName + "_compressed.mp4")
        }

        $baseName = $File.BaseName
        if (-not (Test-AlreadyCompressed -File $File)) {
            $baseName += "_compressed"
        }

        return Join-Path $File.DirectoryName "${baseName}.mp4"
    }
}
