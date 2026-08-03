function Remove-FileSafely {
    <#
    .SYNOPSIS
        Deletes a file, preferring the Recycle Bin so mistakes are recoverable.
    .DESCRIPTION
        Uses Microsoft.VisualBasic.FileIO.FileSystem to route deletions through
        the Recycle Bin. If that assembly cannot be loaded (rare, but possible on
        trimmed installs) the deletion is REFUSED rather than silently escalated
        to a permanent delete - losing files is worse than skipping them.

        -Permanent opts into a genuine unrecoverable delete.
    .PARAMETER Path
        Full path of the file to remove.
    .PARAMETER Permanent
        Bypass the Recycle Bin.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [switch]$Permanent
    )

    if ($Permanent) {
        if ($PSCmdlet.ShouldProcess($Path, 'Permanently delete')) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
        return
    }

    if (-not $script:VisualBasicLoaded) {
        try {
            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
            $script:VisualBasicLoaded = $true
        } catch {
            throw "Recycle Bin unavailable (Microsoft.VisualBasic could not be loaded). Re-run with -PermanentDelete to force removal. Original error: $_"
        }
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Send to Recycle Bin')) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $Path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
}
