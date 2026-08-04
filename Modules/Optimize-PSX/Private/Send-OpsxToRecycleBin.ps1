function Send-OpsxToRecycleBin {
    <#
    .SYNOPSIS
        Moves a file to the Recycle Bin.
    .DESCRIPTION
        Uses Microsoft.VisualBasic.FileIO.FileSystem, which is the only managed
        API that performs a genuine shell recycle rather than a delete.

        If the assembly cannot be loaded the operation throws. It never falls
        back to a permanent delete: silently escalating a recoverable delete into
        an unrecoverable one is worse than failing. Callers wanting a permanent
        delete request it explicitly.

        The assembly load is cached for the session.
    .PARAMETER Path
        Full path of the file to recycle.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    if (-not $script:VisualBasicLoaded) {
        try {
            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
            $script:VisualBasicLoaded = $true
        } catch {
            throw "Recycle Bin is unavailable (Microsoft.VisualBasic could not be loaded). Re-run with -Permanent to force removal. Original error: $_"
        }
    }

    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
        $Path,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
}
