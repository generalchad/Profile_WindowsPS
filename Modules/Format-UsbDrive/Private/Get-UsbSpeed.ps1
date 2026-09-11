function Get-UsbSpeed {
    <#
    .SYNOPSIS
        Best-effort detection of the USB specification a disk is connected via.

    .DESCRIPTION
        Walks the PnP device tree from the disk's Win32_DiskDrive instance up to the
        USB host controller and classifies it as USB3 (xHCI / eXtensible), USB2 (EHCI /
        Enhanced) or USB1 (UHCI/OHCI). Returns 'Unknown' when the chain cannot be
        resolved, in which case callers should fall back to a generic advisory.

    .PARAMETER DiskNumber
        The disk number to inspect (as reported by Get-Disk).

    .NOTES
        Private helper. Not exported. Heuristic; may report 'Unknown' on some systems.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][uint32]$DiskNumber
    )

    try {
        $drive = Get-CimInstance -ClassName Win32_DiskDrive -Filter "Index = $DiskNumber" -ErrorAction Stop |
            Select-Object -First 1

        if (-not $drive) { return 'Unknown' }

        $instanceId = $drive.PNPDeviceID
        if (-not $instanceId) { return 'Unknown' }

        # Walk up the parent chain a few levels, looking for the host controller.
        $current = $instanceId
        foreach ($depth in 1..6) {
            $parent = Get-PnpDeviceProperty -InstanceId $current -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Data -ErrorAction SilentlyContinue

            if (-not $parent) { break }
            $current = $parent

            $device = Get-PnpDevice -InstanceId $current -ErrorAction SilentlyContinue
            if (-not $device) { continue }

            $name  = "$($device.FriendlyName) $($device.Class)"
            $class = "$($device.Class)"

            if ($class -eq 'USB' -or $name -match 'USB|eXtensible|Enhanced|Host Controller|xHCI|EHCI|UHCI|OHCI') {
                if ($name -match 'eXtensible|xHCI|USB 3|3\.\d') {
                    return 'USB3'
                }
                if ($name -match 'Enhanced|EHCI|USB 2|2\.0') {
                    return 'USB2'
                }
                if ($name -match 'UHCI|OHCI|USB 1|1\.[01]') {
                    return 'USB1'
                }
                # USB class device but no version hint - keep walking to the controller.
            }
        }
    }
    catch {
        Write-Verbose "USB speed detection failed for disk $DiskNumber`: $($_.Exception.Message)"
    }

    return 'Unknown'
}
