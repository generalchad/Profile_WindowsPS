function Get-PrintStackInventory {
    <#
    .SYNOPSIS
        Reports every printer, port, driver and imaging device, and what
        Restart-PrintStack would do with each.

    .DESCRIPTION
        A read-only view of the same plan Restart-PrintStack acts on. Nothing is
        deleted, no service is touched, and the allow-list file is read but never
        created - simply looking at the print system must not have side effects.

        Useful both as a diagnostic ("why is this queue being kept?") and as a
        safe way to preview a cleanup before running one.

    .PARAMETER Keep
        Additional patterns to treat as protected, exactly as Restart-PrintStack
        would.

    .PARAMETER Remove
        Patterns to treat as force-removed.

    .PARAMETER Type
        Limit the output to one object type.

    .PARAMETER RemovalsOnly
        Show only the items that would be removed.

    .PARAMETER ConfigPath
        Alternate location for the allow-list file.

    .PARAMETER AsObject
        Emit the plan items instead of printing a table, for scripting.

    .EXAMPLE
        Get-PrintStackInventory

        Prints the whole print system with a Keep/Remove verdict and reason.

    .EXAMPLE
        Get-PrintStackInventory -RemovalsOnly

        Shows only what a cleanup would remove.

    .EXAMPLE
        Get-PrintStackInventory -Type Port -AsObject | Where-Object Action -eq 'Remove'

        The orphaned ports, as objects.

    .OUTPUTS
        RestartPrintStack.PlanItem objects when -AsObject is supplied.

    .NOTES
        Does not require elevation for enumeration, although some device details
        are only visible to an elevated session.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]] $Keep = @(),

        [string[]] $Remove = @(),

        [ValidateSet('All', 'Printer', 'Port', 'Scanner', 'Driver')]
        [string] $Type = 'All',

        [switch] $RemovalsOnly,

        [string] $ConfigPath,

        [switch] $AsObject
    )

    Set-StrictMode -Version Latest

    # -NoCreate: reading the inventory must never write to the technician's
    # profile. Only Restart-PrintStack creates the allow-list file.
    $allowList = Get-PrintStackAllowList -Keep $Keep -Remove $Remove -ConfigPath $ConfigPath -NoCreate

    $plan = Get-PrintStackPlan -AllowList $allowList

    if ($Type -eq 'Driver') {
        $drivers = @($plan.Drivers)
        if ($AsObject) { return $drivers }

        Write-Host ''
        Write-Host 'Print drivers' -ForegroundColor Cyan
        Write-Host ('=' * 78) -ForegroundColor DarkGray
        $drivers |
            Select-Object Name, Version, Environment, @{ Name = 'InUse'; Expression = { $_.InUse } } |
            Format-Table -AutoSize |
            Out-String |
            Write-Host
        return
    }

    $items = switch ($Type) {
        'Printer' { @($plan.Queues) }
        'Port' { @($plan.Ports) }
        'Scanner' { @($plan.Scanners) }
        default { @($plan.Queues) + @($plan.Ports) + @($plan.Scanners) }
    }

    if ($RemovalsOnly) {
        $items = @($items | Where-Object { $_.Action -eq 'Remove' })
    }

    if ($AsObject) { return $items }

    Write-Host ''
    Write-Host "Print stack inventory - $env:COMPUTERNAME" -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor DarkGray

    if ($plan.DefaultPrinter) {
        Write-Host "  Default printer: $($plan.DefaultPrinter)" -ForegroundColor DarkGray
    }
    Write-Host "  Allow-list:      $($allowList.Path)" -ForegroundColor DarkGray

    $subset = [pscustomobject]@{
        PSTypeName       = 'RestartPrintStack.Plan'
        Queues           = @($items | Where-Object { $_.Type -eq 'Printer' })
        Ports            = @($items | Where-Object { $_.Type -eq 'Port' })
        Scanners         = @($items | Where-Object { $_.Type -eq 'Scanner' })
        Drivers          = @($plan.Drivers)
        AllowList        = $allowList
        DefaultPrinter   = $plan.DefaultPrinter
        DefaultIsRemoved = $plan.DefaultIsRemoved
        RemoveCount      = @($items | Where-Object { $_.Action -eq 'Remove' }).Count
        KeepCount        = @($items | Where-Object { $_.Action -eq 'Keep' }).Count
        PrinterRemovals  = @()
        PortRemovals     = @()
        ScannerRemovals  = @()
    }

    Show-PrintStackPlan -Plan $subset

    Write-Host ("  {0} item(s) would be removed, {1} kept." -f $subset.RemoveCount, $subset.KeepCount) `
        -ForegroundColor $(if ($subset.RemoveCount) { 'Yellow' } else { 'Green' })
    Write-Host ''
}
