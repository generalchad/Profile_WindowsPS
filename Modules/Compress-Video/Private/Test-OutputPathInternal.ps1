function Test-OutputPathInternal {
    <#
    .SYNOPSIS
        Validates a destination path (length, invalid characters) and
        creates its parent directory if missing.

    .DESCRIPTION
        Internal helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path
    )

    begin {
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    }

    process {
        try {
            if ($Path.Length -gt 260) {
                Write-Error "Path exceeds maximum length (260 characters): $Path"
                return $false
            }

            $parentDir = Split-Path -Path $Path -Parent
            if (-not (Test-Path -Path $parentDir -PathType Container)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }

            $fileName = Split-Path -Path $Path -Leaf
            if ($fileName.IndexOfAny($invalidChars) -ge 0) {
                Write-Error "Filename contains invalid characters: $fileName"
                return $false
            }

            return $true
        }
        catch {
            Write-Error "Error testing path: $_"
            return $false
        }
    }
}
