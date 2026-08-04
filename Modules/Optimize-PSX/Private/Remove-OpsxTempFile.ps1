function Remove-OpsxTempFile {
    <#
    .SYNOPSIS
        Deletes a temporary conversion artefact if present.
    .DESCRIPTION
        Best-effort removal of a .chd.tmp file. Failures are logged at detail
        level and otherwise ignored, since a leftover temporary file is harmless
        and must never interrupt a batch or mask the real error that led to the
        cleanup.

        Deliberately does not implement ShouldProcess: it operates only on files
        this module created moments earlier, and prompting mid-batch to remove
        internal scratch data would be noise.
    .PARAMETER Path
        Temporary file path.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    try {
        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Delete($Path)
            Write-OpsxLog "Removed temporary file: $Path" -Level Detail
        }
    } catch {
        Write-OpsxLog "Could not remove temporary file '$Path': $($_.Exception.Message)" -Level Detail
    }
}
