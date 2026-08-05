function Get-VideoFiles {
    <#
    .SYNOPSIS
        Resolves a path (file or directory) into the list of video files
        to process.

    .DESCRIPTION
        Internal helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string[]]$Extensions,

        [Parameter()]
        [switch]$Recurse
    )

    process {
        if (Test-Path $Path -PathType Leaf) {
            return (Get-Item -Force $Path)
        }

        $searchParams = @{
            Path        = $Path
            File        = $true
            Force       = $true
            Recurse     = $Recurse
            ErrorAction = 'SilentlyContinue'
        }

        Get-ChildItem @searchParams |
            Where-Object { $Extensions -contains $_.Extension.ToLower() }
    }
}
