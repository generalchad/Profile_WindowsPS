function Get-PrintStackPlan {
    <#
    .SYNOPSIS
        Classifies every queue, port and scanner as Keep or Remove and explains why.

    .DESCRIPTION
        The planner is the whole safety model of this module: nothing is deleted
        that the plan did not first mark Remove, and every decision carries a
        human-readable reason that is shown before anything happens.

        Evaluation order for a print queue, first match wins:

          1. -Remove / removePrinters   -> Remove. Force-removal outranks every
                                           protection so a stale Adobe or OneNote
                                           queue can be dropped without editing
                                           the module.
          2. Allow-list name or driver  -> Keep. Driver matching is what catches a
                                           renamed "Microsoft Print to PDF".
          3. Network connection (\\...) -> Keep unless -IncludeNetwork. These are
                                           usually pushed by Group Policy and
                                           simply reappear.
          4. Redirected / RDP session   -> Keep unless -IncludeRedirected. Removing
                                           one breaks printing in the live remote
                                           session and it returns at next logon.
          5. Everything else            -> Remove. This is the site clutter the
                                           tool exists to clear.

        Ports are planned only after the surviving queue set is known. A port is
        removable when it is referenced by nothing that survives, is served by a
        sweepable monitor, and is not protected by name. Sweeping every orphan
        rather than only the ports freed during this run is deliberate: queues
        deleted by hand through Settings leave their ports behind indefinitely,
        and those strays are the bulk of the clutter.

    .PARAMETER AllowList
        The merged allow-list from Get-PrintStackAllowList.

    .PARAMETER IncludeNetwork
        Treat \\server\queue connections as removable.

    .PARAMETER IncludeRedirected
        Treat redirected/RDP queues as removable.

    .PARAMETER NoPortSweep
        Plan no port removals at all.

    .PARAMETER NoScanners
        Plan no scanner removals at all.

    .PARAMETER IncludeLocalScanners
        Also remove USB-attached imaging devices, which normally re-enumerate on
        reconnect and are therefore left alone.

    .OUTPUTS
        pscustomobject with Queues, Ports, Scanners, Drivers, DefaultPrinter and
        counts. Each item carries Action ('Keep'/'Remove') and Reason.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $AllowList,

        [switch] $IncludeNetwork,

        [switch] $IncludeRedirected,

        [switch] $NoPortSweep,

        [switch] $NoScanners,

        [switch] $IncludeLocalScanners
    )

    $queues = @(Get-PrintStackQueue)
    $ports = @(Get-PrintStackPort)
    $drivers = @(Get-PrintStackDriver)
    $scanners = if ($NoScanners) { @() } else { @(Get-PrintStackScanner) }

    $defaultPrinter = @($queues | Where-Object { $_.Default } | Select-Object -First 1 -ExpandProperty Name)
    $defaultPrinter = if ($defaultPrinter) { $defaultPrinter[0] } else { $null }

    # -----------------------------------------------------------------
    # Queues
    # -----------------------------------------------------------------
    $plannedQueues = foreach ($q in $queues) {
        $action = 'Remove'
        $reason = 'Not on the allow-list.'

        $forced = Test-AllowListMatch -Value $q.Name -Patterns $AllowList.RemovePrinters
        $keptByName = Test-AllowListMatch -Value $q.Name -Patterns $AllowList.KeepPrinters
        $keptByDriver = Test-AllowListMatch -Value $q.DriverName -Patterns $AllowList.KeepDrivers

        $isNetwork = ($q.Name -match $script:RegexNetworkPrinter) -or ($q.Type -eq 'Connection')
        $isRedirected = ($q.Name -match $script:RegexRedirectedPrinter)

        if ($forced) {
            $action = 'Remove'
            $reason = "Force-removed by '$forced'."
        }
        elseif ($keptByName) {
            $action = 'Keep'
            $reason = "Allow-list name '$keptByName'."
        }
        elseif ($keptByDriver) {
            $action = 'Keep'
            $reason = "Allow-list driver '$keptByDriver'."
        }
        elseif ($isNetwork -and -not $IncludeNetwork) {
            $action = 'Keep'
            $reason = 'Network connection; use -IncludeNetwork to remove.'
        }
        elseif ($isRedirected -and -not $IncludeRedirected) {
            $action = 'Keep'
            $reason = 'Redirected session printer; use -IncludeRedirected to remove.'
        }

        [pscustomobject]@{
            PSTypeName   = 'RestartPrintStack.PlanItem'
            Type         = 'Printer'
            Name         = $q.Name
            Detail       = $q.PortName
            Driver       = $q.DriverName
            Action       = $action
            Reason       = $reason
            IsDefault    = [bool]$q.Default
            IsNetwork    = $isNetwork
            IsRedirected = $isRedirected
            Pinned       = $false
            Object       = $q
        }
    }
    $plannedQueues = @($plannedQueues)

    # -----------------------------------------------------------------
    # Ports
    #
    # Reference counting is done against the queues that will still exist
    # after the removals above, not against the current set.
    # -----------------------------------------------------------------
    $plannedPorts = @(Get-PortPlan -Ports $ports -PlannedQueues $plannedQueues `
            -AllowList $AllowList -NoPortSweep:$NoPortSweep)

    # -----------------------------------------------------------------
    # Scanners
    # -----------------------------------------------------------------
    $plannedScanners = foreach ($s in $scanners) {
        $action = 'Remove'
        $reason = 'Network-discovered imaging device.'

        $protected = Test-AllowListMatch -Value $s.Name -Patterns $script:ProtectedScannerNames
        $keptByName = Test-AllowListMatch -Value $s.Name -Patterns $AllowList.KeepPrinters

        if ($protected) {
            $action = 'Keep'
            $reason = "Built-in or integrated device ('$protected')."
        }
        elseif ($keptByName) {
            $action = 'Keep'
            $reason = "Allow-list name '$keptByName'."
        }
        elseif ($s.Connection -eq 'Local' -and -not $IncludeLocalScanners) {
            # A USB scanner re-enumerates the instant it is reconnected, so
            # removing it achieves nothing but a driver reinstall prompt.
            $action = 'Keep'
            $reason = 'Locally attached; use -IncludeLocalScanners to remove.'
        }
        elseif ($s.Connection -eq 'Unknown' -and -not $IncludeLocalScanners) {
            $action = 'Keep'
            $reason = 'Connection type could not be determined; left alone.'
        }

        [pscustomobject]@{
            PSTypeName   = 'RestartPrintStack.PlanItem'
            Type         = 'Scanner'
            Name         = $s.Name
            Detail       = $s.Connection
            Driver       = $s.InstanceId
            Action       = $action
            Reason       = $reason
            IsDefault    = $false
            IsNetwork    = ($s.Connection -eq 'Network')
            IsRedirected = $false
            Pinned       = $false
            Object       = $s
        }
    }
    $plannedScanners = @($plannedScanners)

    # -----------------------------------------------------------------
    # Drivers - reported only. Marked with whether a surviving queue
    # still references them, so a later -IncludeDrivers has its data.
    # -----------------------------------------------------------------
    $survivingDrivers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($q in $plannedQueues) {
        if ($q.Action -eq 'Keep' -and $q.Driver) { $null = $survivingDrivers.Add($q.Driver) }
    }
    foreach ($d in $drivers) {
        $d.InUse = $survivingDrivers.Contains("$($d.Name)")
    }

    New-PlanObject -Queues $plannedQueues -Ports $plannedPorts -Scanners $plannedScanners `
        -Drivers $drivers -DefaultPrinter $defaultPrinter -AllowList $AllowList
}

function Get-PortPlan {
    <#
    .SYNOPSIS
        Determines which ports are orphaned once the planned queue removals happen.

    .DESCRIPTION
        Builds the set of port names still referenced by surviving queues, then
        marks everything outside that set as removable, subject to the protected
        name list and the sweepable monitor list.

        Split out from Get-PrintStackPlan because the review screen has to re-run
        exactly this calculation each time a technician keeps or pins a queue: a
        queue moving from Remove back to Keep re-references its port, which must
        immediately drop off the removal list.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Ports,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $PlannedQueues,

        [Parameter(Mandatory)]
        [pscustomobject] $AllowList,

        [switch] $NoPortSweep
    )

    $referenced = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($q in $PlannedQueues) {
        if ($q.Action -ne 'Keep') { continue }
        foreach ($name in (Split-PortName -PortName $q.Object.PortName)) {
            $null = $referenced.Add($name)
        }
    }

    $result = foreach ($p in $Ports) {
        $action = 'Remove'
        $reason = 'Orphaned; no remaining printer uses it.'

        $protected = Test-AllowListMatch -Value $p.Name -Patterns $AllowList.KeepPorts

        # A $null monitor means the port was discovered indirectly through a queue
        # and its owning monitor is unknown. Sweeping those blind risks deleting a
        # vendor port whose utility depends on it, so unknown monitors are kept.
        $sweepable = $false
        if ($p.Monitor) {
            $sweepable = [bool](Test-AllowListMatch -Value $p.Monitor -Patterns $script:SweepablePortMonitors)
        }

        if ($NoPortSweep) {
            $action = 'Keep'
            $reason = 'Port sweep disabled (-NoPortSweep).'
        }
        elseif ($referenced.Contains("$($p.Name)")) {
            $action = 'Keep'
            $reason = 'Still used by a printer that is being kept.'
        }
        elseif ($protected) {
            $action = 'Keep'
            $reason = "Protected port '$protected'."
        }
        elseif (-not $p.Monitor) {
            $action = 'Keep'
            $reason = 'Port monitor is unknown; left alone.'
        }
        elseif (-not $sweepable) {
            $action = 'Keep'
            $reason = "Monitor '$($p.Monitor)' is not swept."
        }

        $detail = if ($p.Address) { $p.Address } elseif ($p.Monitor) { $p.Monitor } else { '' }

        [pscustomobject]@{
            PSTypeName   = 'RestartPrintStack.PlanItem'
            Type         = 'Port'
            Name         = $p.Name
            Detail       = $detail
            Driver       = $p.Monitor
            Action       = $action
            Reason       = $reason
            IsDefault    = $false
            IsNetwork    = $false
            IsRedirected = $false
            Pinned       = $false
            Object       = $p
        }
    }

    @($result)
}

function New-PlanObject {
    <#
    .SYNOPSIS
        Assembles the plan container and its derived counts.

    .DESCRIPTION
        Counts are computed here rather than at each display site so the review
        screen, the summary and -WhatIf can never disagree about how many items
        are in play.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()] [object[]] $Queues = @(),
        [AllowEmptyCollection()] [object[]] $Ports = @(),
        [AllowEmptyCollection()] [object[]] $Scanners = @(),
        [AllowEmptyCollection()] [object[]] $Drivers = @(),
        [string] $DefaultPrinter,
        [pscustomobject] $AllowList
    )

    $all = @($Queues) + @($Ports) + @($Scanners)
    $removing = @($all | Where-Object { $_.Action -eq 'Remove' })

    # The default queue disappearing matters enough to precompute: the caller has
    # to nominate a survivor or Windows will quietly choose one for the technician.
    $defaultRemoved = [bool](@($Queues | Where-Object { $_.IsDefault -and $_.Action -eq 'Remove' }).Count)

    [pscustomobject]@{
        PSTypeName       = 'RestartPrintStack.Plan'
        Queues           = @($Queues)
        Ports            = @($Ports)
        Scanners         = @($Scanners)
        Drivers          = @($Drivers)
        AllowList        = $AllowList
        DefaultPrinter   = $DefaultPrinter
        DefaultIsRemoved = $defaultRemoved
        RemoveCount      = $removing.Count
        KeepCount        = @($all).Count - $removing.Count
        PrinterRemovals  = @($Queues | Where-Object { $_.Action -eq 'Remove' })
        PortRemovals     = @($Ports | Where-Object { $_.Action -eq 'Remove' })
        ScannerRemovals  = @($Scanners | Where-Object { $_.Action -eq 'Remove' })
    }
}

function Update-PrintStackPlan {
    <#
    .SYNOPSIS
        Recomputes the port plan and the derived counts after the review screen
        changes a queue's action.

    .DESCRIPTION
        Keeping a queue re-references its port, so the port must immediately move
        from Remove back to Keep. Recomputing rather than patching in place means
        the displayed plan is always internally consistent, however many times the
        technician changes their mind.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan,

        [switch] $NoPortSweep
    )

    $rawPorts = @($Plan.Ports | ForEach-Object { $_.Object })
    $pinnedPorts = @{}
    foreach ($p in $Plan.Ports) {
        if ($p.Pinned) { $pinnedPorts[$p.Name] = $true }
    }

    $ports = @(Get-PortPlan -Ports $rawPorts -PlannedQueues $Plan.Queues `
            -AllowList $Plan.AllowList -NoPortSweep:$NoPortSweep)

    # Pins survive the recompute; they are a technician's explicit decision and
    # must not be undone by a later keep/unkeep of some unrelated queue.
    foreach ($p in $ports) {
        if ($pinnedPorts.ContainsKey($p.Name)) {
            $p.Pinned = $true
            $p.Action = 'Keep'
            $p.Reason = 'Pinned to the allow-list.'
        }
    }

    New-PlanObject -Queues $Plan.Queues -Ports $ports -Scanners $Plan.Scanners `
        -Drivers $Plan.Drivers -DefaultPrinter $Plan.DefaultPrinter -AllowList $Plan.AllowList
}
