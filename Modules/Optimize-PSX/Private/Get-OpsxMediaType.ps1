function Get-OpsxMediaType {
    <#
    .SYNOPSIS
        Reports the physical media type of the volume holding a path.
    .DESCRIPTION
        Resolves the path's drive letter to a physical disk through the Storage
        CIM provider and maps the reported MediaType:

          SSD      solid state, safe for concurrent reads
          HDD      rotational, benefits from serialised access
          SCM      storage class memory
          Network  UNC path, treated as safe for concurrency
          Unknown  detection unavailable or inconclusive

        Detection is best effort. Storage cmdlets are Windows-only, require the
        volume to be locally attached, and report Unspecified for many RAID and
        virtualised configurations. Unknown is returned rather than guessing, and
        callers treat Unknown as permitting concurrency.
    .PARAMETER Path
        Any path on the volume to inspect.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    try {
        $full = [System.IO.Path]::GetFullPath($Path)

        if ($full.StartsWith('\\')) { return 'Network' }

        $root = [System.IO.Path]::GetPathRoot($full)
        if (-not $root) { return 'Unknown' }

        $letter = $root.TrimEnd('\', ':')
        if ($letter.Length -ne 1) { return 'Unknown' }

        if (-not (Get-Command -Name Get-Partition -ErrorAction SilentlyContinue)) {
            return 'Unknown'
        }

        $partition = Get-Partition -DriveLetter $letter -ErrorAction Stop
        $disk = Get-PhysicalDisk -ErrorAction Stop |
            Where-Object { $_.DeviceId -eq $partition.DiskNumber } |
            Select-Object -First 1

        if (-not $disk) { return 'Unknown' }

        switch ($disk.MediaType) {
            'SSD'  { return 'SSD' }
            'HDD'  { return 'HDD' }
            'SCM'  { return 'SCM' }
            default {
                # Some NVMe and virtual controllers report Unspecified while
                # still exposing a spindle speed of zero, which identifies
                # solid state media reliably.
                if ($disk.PSObject.Properties.Name -contains 'SpindleSpeed') {
                    if ($disk.SpindleSpeed -eq 0) { return 'SSD' }
                    if ($disk.SpindleSpeed -gt 0) { return 'HDD' }
                }
                return 'Unknown'
            }
        }
    } catch {
        Write-OpsxLog "Media type detection failed for '$Path': $($_.Exception.Message)" -Level Detail
        return 'Unknown'
    }
}
