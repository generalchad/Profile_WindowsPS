function New-UsbTarget {
    <#
    .SYNOPSIS
        Builds a normalized target object from a disk and one of its partitions.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Disk,
        [Parameter(Mandatory)][object]$Partition
    )

    $vol = Get-Volume -DriveLetter $Partition.DriveLetter -ErrorAction SilentlyContinue

    [pscustomobject]@{
        DiskNumber      = $Disk.Number
        PartitionNumber = $Partition.PartitionNumber
        DriveLetter     = $Partition.DriveLetter
        SizeBytes       = $Partition.Size
        SizeGB          = [math]::Round($Partition.Size / 1GB, 2)
        FriendlyName    = $Disk.FriendlyName
        FileSystem      = if ($vol) { $vol.FileSystem } else { 'Unknown' }
        VolumeLabel     = if ($vol -and $vol.FileSystemLabel) { $vol.FileSystemLabel } else { '' }
        UsbSpeed        = Get-UsbSpeed -DiskNumber $Disk.Number
    }
}

function Get-RemovableUsbTarget {
    <#
    .SYNOPSIS
        Enumerates every removable USB drive under 70GB with a drive letter.

    .DESCRIPTION
        Filters Get-Disk to BusType USB and Size under 70GB, then maps each disk
        to the partitions that currently expose a drive letter.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    param()

    $targets = [System.Collections.Generic.List[object]]::new()

    $disks = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object {
            $_.BusType -eq 'USB' -and $_.Size -lt 70GB
        })

    foreach ($disk in $disks) {
        $partitions = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveLetter })

        foreach ($part in $partitions) {
            $targets.Add((New-UsbTarget -Disk $disk -Partition $part))
        }
    }

    return $targets.ToArray()
}

function Resolve-UsbDriveLetter {
    <#
    .SYNOPSIS
        Resolves an explicit drive letter to a removable USB target, validating it.

    .DESCRIPTION
        Accepts 'E', 'E:' or 'E:\' and validates that the referenced partition lives
        on a USB disk under 70GB. Throws otherwise.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Letter
    )

    $normalized = ($Letter.Trim()).TrimEnd(':', '\').ToUpperInvariant()
    if (-not $normalized) { throw "Drive letter '$Letter' is empty." }

    $part = Get-Partition -DriveLetter $normalized -ErrorAction SilentlyContinue
    if (-not $part) { throw "No volume is mounted at drive letter '$normalized'." }

    $disk = Get-Disk -Number $part.DiskNumber -ErrorAction SilentlyContinue
    if (-not $disk) { throw "Could not resolve the disk behind drive '$normalized'." }

    if ($disk.BusType -ne 'USB') {
        throw "Drive '$normalized' is not a removable USB drive (BusType $($disk.BusType)). Refusing."
    }

    if ($disk.Size -ge 70GB) {
        $sizeGB = [math]::Round($disk.Size / 1GB, 1)
        throw "Drive '$normalized' is ${sizeGB}GB, at or above the 70GB safety cap. Refusing."
    }

    New-UsbTarget -Disk $disk -Partition $part
}
