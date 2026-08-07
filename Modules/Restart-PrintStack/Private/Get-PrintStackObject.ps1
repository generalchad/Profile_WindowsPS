# =====================================================================
# Get-PrintStackObject.ps1 - Enumeration of the four object types
#
# Each getter normalises what Windows reports into a flat pscustomobject
# so that the planner and the review screen never have to care whether
# the data arrived from PrintManagement, CIM or a native tool.
# =====================================================================

function Get-PrintStackQueue {
    <#
    .SYNOPSIS
        Enumerates every print queue defined on this machine.

    .DESCRIPTION
        Prefers Get-Printer. Falls back to the Win32_Printer CIM class, which is
        present on every Windows build back to XP and needs no optional feature.

        The two sources name things differently, so both are flattened into a
        single shape: Name, DriverName, PortName, Shared, Published, Type, Default,
        Status and Comment.

        PortName can hold a comma-separated list when printer pooling is enabled.
        It is preserved verbatim here and split by the port sweep, because a
        pooled queue references every port in that list and losing one would
        break it.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $queues = @()

    if (Test-PrintManagementAvailable) {
        try {
            $queues = @(
                Get-Printer -ErrorAction Stop | ForEach-Object {
                    [pscustomobject]@{
                        Name       = $_.Name
                        DriverName = $_.DriverName
                        PortName   = $_.PortName
                        Shared     = [bool]$_.Shared
                        Published  = [bool]$_.Published
                        Type       = "$($_.Type)"
                        ShareName  = $_.ShareName
                        Comment    = $_.Comment
                        Location   = $_.Location
                        Status     = "$($_.PrinterStatus)"
                        Default    = $false
                        Source     = 'Cmdlet'
                    }
                }
            )
        }
        catch {
            Write-Verbose "Get-Printer failed, falling back to CIM: $($_.Exception.Message)"
            $queues = @()
        }
    }

    if (-not $queues -or $queues.Count -eq 0) {
        try {
            $queues = @(
                Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop | ForEach-Object {
                    [pscustomobject]@{
                        Name       = $_.Name
                        DriverName = $_.DriverName
                        PortName   = $_.PortName
                        Shared     = [bool]$_.Shared
                        Published  = $false
                        Type       = if ($_.Network) { 'Connection' } else { 'Local' }
                        ShareName  = $_.ShareName
                        Comment    = $_.Comment
                        Location   = $_.Location
                        Status     = "$($_.PrinterStatus)"
                        Default    = [bool]$_.Default
                        Source     = 'CIM'
                    }
                }
            )
        }
        catch {
            Write-Warning "Unable to enumerate print queues: $($_.Exception.Message)"
            return @()
        }
    }

    # Get-Printer does not report the default queue, so it is resolved separately
    # and merged in. Knowing the default matters: if the sweep deletes it, the
    # caller has to nominate a survivor or Windows will silently pick one.
    $defaultName = Get-DefaultPrintQueueName
    if ($defaultName) {
        foreach ($q in $queues) {
            if ($q.Name -eq $defaultName) { $q.Default = $true }
        }
    }

    $queues | Sort-Object -Property Name
}

function Get-DefaultPrintQueueName {
    <#
    .SYNOPSIS
        Returns the name of the current default print queue, or $null.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $default = Get-CimInstance -ClassName Win32_Printer -Filter 'Default = True' -ErrorAction Stop |
            Select-Object -First 1
        if ($default) { return $default.Name }
    }
    catch {
        Write-Verbose "Could not determine the default printer via CIM: $($_.Exception.Message)"
    }

    # Registry fallback. The value is 'Name,driver,port'; only the name is wanted.
    try {
        $windows = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -ErrorAction Stop
        if ($windows.PSObject.Properties['Device'] -and $windows.Device) {
            return ($windows.Device -split ',')[0]
        }
    }
    catch {
        Write-Verbose "Could not read the default printer from the registry: $($_.Exception.Message)"
    }

    return $null
}

function Get-PrintStackPort {
    <#
    .SYNOPSIS
        Enumerates every printer port defined on this machine.

    .DESCRIPTION
        Prefers Get-PrinterPort, falling back to Win32_TCPIPPrinterPort merged with
        the port names referenced by Win32_Printer. The CIM path is deliberately
        wider than the TCP/IP class alone: WSD and LPR ports do not appear in
        Win32_TCPIPPrinterPort at all, and those are precisely the ones that
        accumulate.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $ports = @()

    # Parenthesised: an unparenthesised command call would swallow '-and' as a
    # parameter name rather than treating it as the boolean operator.
    if ((Test-PrintManagementAvailable) -and (Get-Command Get-PrinterPort -ErrorAction SilentlyContinue)) {

        try {
            $ports = @(
                Get-PrinterPort -ErrorAction Stop | ForEach-Object {
                    $address = $null
                    if ($_.PSObject.Properties['PrinterHostAddress']) { $address = $_.PrinterHostAddress }
                    if (-not $address -and $_.PSObject.Properties['HostAddress']) { $address = $_.HostAddress }

                    [pscustomobject]@{
                        Name        = $_.Name
                        Description = $_.Description
                        Monitor     = $_.PortMonitor
                        Address     = $address
                        PortNumber  = if ($_.PSObject.Properties['PortNumber']) { $_.PortNumber } else { $null }
                        Protocol    = if ($_.PSObject.Properties['Protocol']) { "$($_.Protocol)" } else { $null }
                        Source      = 'Cmdlet'
                    }
                }
            )
        }
        catch {
            Write-Verbose "Get-PrinterPort failed, falling back to CIM: $($_.Exception.Message)"
            $ports = @()
        }
    }

    if (-not $ports -or $ports.Count -eq 0) {
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $list = [System.Collections.Generic.List[object]]::new()

        try {
            foreach ($p in @(Get-CimInstance -ClassName Win32_TCPIPPrinterPort -ErrorAction Stop)) {
                if ($seen.Add($p.Name)) {
                    $list.Add([pscustomobject]@{
                            Name        = $p.Name
                            Description = $p.Description
                            Monitor     = 'Standard TCP/IP Port'
                            Address     = $p.HostAddress
                            PortNumber  = $p.PortNumber
                            Protocol    = "$($p.Protocol)"
                            Source      = 'CIM'
                        })
                }
            }
        }
        catch {
            Write-Verbose "Win32_TCPIPPrinterPort is unavailable: $($_.Exception.Message)"
        }

        # Everything else referenced by a queue but not returned above - WSD, LPR,
        # vendor monitors. Without this pass those ports are invisible and would
        # never be swept.
        try {
            foreach ($q in @(Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop)) {
                foreach ($name in (Split-PortName -PortName $q.PortName)) {
                    if ($seen.Add($name)) {
                        $list.Add([pscustomobject]@{
                                Name        = $name
                                Description = $null
                                Monitor     = $null
                                Address     = $null
                                PortNumber  = $null
                                Protocol    = $null
                                Source      = 'CIM'
                            })
                    }
                }
            }
        }
        catch {
            Write-Verbose "Could not enumerate ports from Win32_Printer: $($_.Exception.Message)"
        }

        $ports = @($list)
    }

    $ports | Sort-Object -Property Name
}

function Split-PortName {
    <#
    .SYNOPSIS
        Splits a queue's PortName value into individual port names.

    .DESCRIPTION
        A printer with pooling enabled stores every pooled port in one
        comma-separated PortName string. Treating that string as a single port
        name means each pooled port looks unreferenced, and the sweep would delete
        the ports out from under a working queue. This splitting is therefore a
        correctness requirement, not a convenience.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string] $PortName
    )

    if ([string]::IsNullOrWhiteSpace($PortName)) { return @() }

    @($PortName -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-PrintStackDriver {
    <#
    .SYNOPSIS
        Enumerates installed print drivers.

    .DESCRIPTION
        Collected for reporting only in this version - nothing removes drivers yet.
        Each entry is marked with whether any surviving queue still references it,
        so the inventory already answers "which drivers are dead weight?" and a
        future -IncludeDrivers has the data it needs without reshaping anything.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $drivers = @()

    if ((Test-PrintManagementAvailable) -and (Get-Command Get-PrinterDriver -ErrorAction SilentlyContinue)) {

        try {
            $drivers = @(
                Get-PrinterDriver -ErrorAction Stop | ForEach-Object {
                    [pscustomobject]@{
                        Name         = $_.Name
                        Manufacturer = if ($_.PSObject.Properties['Manufacturer']) { $_.Manufacturer } else { $null }
                        Version      = if ($_.PSObject.Properties['MajorVersion']) { $_.MajorVersion } else { $null }
                        Environment  = if ($_.PSObject.Properties['PrinterEnvironment']) { $_.PrinterEnvironment } else { $null }
                        InUse        = $false
                        Source       = 'Cmdlet'
                    }
                }
            )
        }
        catch {
            Write-Verbose "Get-PrinterDriver failed: $($_.Exception.Message)"
            $drivers = @()
        }
    }

    if (-not $drivers -or $drivers.Count -eq 0) {
        try {
            $drivers = @(
                Get-CimInstance -ClassName Win32_PrinterDriver -ErrorAction Stop | ForEach-Object {
                    # Win32_PrinterDriver names are 'Driver,version,environment'.
                    $parts = "$($_.Name)" -split ','
                    [pscustomobject]@{
                        Name         = $parts[0]
                        Manufacturer = $null
                        Version      = if ($parts.Count -gt 1) { $parts[1] } else { $null }
                        Environment  = if ($parts.Count -gt 2) { $parts[2] } else { $null }
                        InUse        = $false
                        Source       = 'CIM'
                    }
                }
            )
        }
        catch {
            Write-Verbose "Win32_PrinterDriver is unavailable: $($_.Exception.Message)"
            return @()
        }
    }

    $drivers | Sort-Object -Property Name -Unique
}

function Get-PrintStackScanner {
    <#
    .SYNOPSIS
        Enumerates imaging devices (scanners and multifunction scan units).

    .DESCRIPTION
        Scanners are not spooler objects: they are PnP devices in the Image class,
        so they are enumerated through Get-PnpDevice and removed through the PnP
        stack rather than through any printing API.

        Each device is classified as Network (WSD/eSCL discovery entries, which
        accumulate and never clean themselves up) or Local (USB and other attached
        hardware, which re-enumerates the moment it is reconnected and is therefore
        pointless to remove). Only the former is swept by default.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    if (-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
        Write-Verbose 'Get-PnpDevice is unavailable; scanner enumeration is skipped.'
        return @()
    }

    try {
        $devices = @(Get-PnpDevice -Class $script:ScannerDeviceClasses -ErrorAction Stop)
    }
    catch {
        Write-Verbose "Get-PnpDevice failed: $($_.Exception.Message)"
        return @()
    }

    $result = foreach ($d in $devices) {
        $id = "$($d.InstanceId)"

        $connection = 'Unknown'
        foreach ($prefix in $script:NetworkDeviceIdPrefixes) {
            if ($id -like "$prefix*") { $connection = 'Network'; break }
        }
        if ($connection -eq 'Unknown') {
            foreach ($prefix in $script:LocalDeviceIdPrefixes) {
                if ($id -like "$prefix*") { $connection = 'Local'; break }
            }
        }

        [pscustomobject]@{
            Name       = $d.FriendlyName
            InstanceId = $id
            Class      = $d.Class
            Status     = "$($d.Status)"
            Present    = ($d.Status -eq 'OK')
            Connection = $connection
            Source     = 'Cmdlet'
        }
    }

    @($result) | Sort-Object -Property Name
}
