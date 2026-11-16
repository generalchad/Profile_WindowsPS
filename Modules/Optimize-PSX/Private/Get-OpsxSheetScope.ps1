function Get-OpsxSheetScope {
    <#
    .SYNOPSIS
        Lists a disc sheet and the track files it references.
    .DESCRIPTION
        Used to size a disc target and to recognise which sheet consumes a
        track file when the target is a payload. The conversion planner re-reads
        the sheet itself, so this answers only "which files belong to this
        disc".

        Unresolved references are skipped rather than reported; planning is
        where a missing track file becomes actionable, and duplicating that
        warning during target resolution would be noise.

        A .ccd references its .img and optional .sub by base name rather than
        through an internal directive, matching how the planner reads it.
    .PARAMETER Sheet
        The .cue, .gdi or .ccd file.
    .OUTPUTS
        System.IO.FileInfo, beginning with the sheet itself.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [System.IO.FileInfo]$Sheet
    )

    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $files.Add($Sheet)

    try {
        switch ($Sheet.Extension.ToLowerInvariant()) {
            '.cue' {
                $cue = Read-CueSheet -Path $Sheet.FullName
                foreach ($reference in $cue.FileReferences) {
                    if ($reference.Exists) { $files.Add([System.IO.FileInfo]::new($reference.ResolvedPath)) }
                }
            }
            '.gdi' {
                $gdi = Read-GdiSheet -Path $Sheet.FullName
                foreach ($track in $gdi.Tracks) {
                    if ($track.Exists) { $files.Add([System.IO.FileInfo]::new($track.ResolvedPath)) }
                }
            }
            '.ccd' {
                foreach ($sidecarExtension in $script:CcdSidecarExtensions) {
                    $sidecar = [System.IO.Path]::Combine($Sheet.DirectoryName, "$($Sheet.BaseName)$sidecarExtension")
                    if ([System.IO.File]::Exists($sidecar)) { $files.Add([System.IO.FileInfo]::new($sidecar)) }
                }
            }
        }
    } catch {
        Write-OpsxLog "Could not measure '$($Sheet.Name)': $($_.Exception.Message)" -Level Detail
    }

    return $files
}
