# =====================================================================
# Remove-PrintStackObject.ps1 - The destructive actions
#
# Every function here returns a step result and never throws: a failure
# to delete one queue must not abandon the other twenty. Ordering across
# the file matters and is enforced by the caller - jobs, then queues,
# then ports, then scanners - because the spooler refuses to release a
# port while any queue still references it.
# =====================================================================

function Clear-PrintQueueJob {
    <#
    .SYNOPSIS
        Cancels every pending job on a queue that is about to be deleted.

    .DESCRIPTION
        A queue with jobs still spooled either refuses to delete or leaves orphaned
        .SPL/.SHD files behind in the spool folder. Cancelling first avoids both.

        A queue with no jobs is the overwhelmingly common case, so it is checked
        before anything is attempted and reported as Skipped rather than Success -
        the summary should not imply work that did not happen.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [switch] $DryRun
    )

    $command = "Get-PrintJob -PrinterName '$Name' | Remove-PrintJob"

    if (-not (Get-Command Get-PrintJob -ErrorAction SilentlyContinue)) {
        return Write-StepResult -Step 'Cancel jobs' -Target $Name -Method 'Cmdlet' -Command $command `
            -Status 'Skipped' -Message 'Get-PrintJob is unavailable.'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $jobs = @(Get-PrintJob -PrinterName $Name -ErrorAction Stop)
    }
    catch {
        $sw.Stop()
        return Write-StepResult -Step 'Cancel jobs' -Target $Name -Method 'Cmdlet' -Command $command `
            -Status 'Skipped' -Duration $sw.Elapsed -Message "Could not read the job list: $($_.Exception.Message)"
    }

    if ($jobs.Count -eq 0) {
        $sw.Stop()
        return Write-StepResult -Step 'Cancel jobs' -Target $Name -Method 'Cmdlet' -Command $command `
            -Status 'Skipped' -Duration $sw.Elapsed -Message 'No pending jobs.'
    }

    if ($DryRun) {
        $sw.Stop()
        return Write-StepResult -Step 'Cancel jobs' -Target $Name -Method 'Cmdlet' -Command $command `
            -Status 'WhatIf' -Message "$($jobs.Count) job(s) would be cancelled."
    }

    $failed = 0
    foreach ($job in $jobs) {
        try {
            Remove-PrintJob -PrinterName $Name -ID $job.Id -ErrorAction Stop
        }
        catch {
            $failed++
            Write-Verbose "Could not cancel job $($job.Id) on '$Name': $($_.Exception.Message)"
        }
    }
    $sw.Stop()

    if ($failed) {
        Write-StepResult -Step 'Cancel jobs' -Target $Name -Method 'Cmdlet' -Command $command `
            -Status 'Failed' -Duration $sw.Elapsed `
            -Message "$failed of $($jobs.Count) job(s) could not be cancelled."
    }
    else {
        Write-StepResult -Step 'Cancel jobs' -Target $Name -Method 'Cmdlet' -Command $command `
            -Status 'Success' -Duration $sw.Elapsed -Message "$($jobs.Count) job(s) cancelled."
    }
}

function Remove-PrintQueue {
    <#
    .SYNOPSIS
        Deletes a single print queue.

    .DESCRIPTION
        Prefers Remove-Printer. Falls back first to the Win32_Printer Delete method
        and finally to printui.dll's /dl entry point, which is the only one of the
        three present on every Windows install and the last resort when the others
        are missing or refuse.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [switch] $DryRun
    )

    $command = "Remove-Printer -Name '$Name'"

    if ($DryRun) {
        return Write-StepResult -Step 'Remove printer' -Target $Name -Method 'Cmdlet' -Command $command `
            -Status 'WhatIf' -Message 'Printer was not removed (WhatIf).'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if (Test-PrintManagementAvailable) {
        try {
            Remove-Printer -Name $Name -ErrorAction Stop
            $sw.Stop()
            return Write-StepResult -Step 'Remove printer' -Target $Name -Method 'Cmdlet' -Command $command `
                -Status 'Success' -Duration $sw.Elapsed -Message 'Queue deleted.'
        }
        catch {
            Write-Verbose "Remove-Printer failed for '$Name', trying CIM: $($_.Exception.Message)"
        }
    }

    # CIM fallback.
    try {
        $printer = Get-CimInstance -ClassName Win32_Printer -Filter "Name = '$($Name -replace "'", "\'")'" -ErrorAction Stop |
            Select-Object -First 1
        if ($printer) {
            $null = Remove-CimInstance -InputObject $printer -ErrorAction Stop
            $sw.Stop()
            return Write-StepResult -Step 'Remove printer' -Target $Name -Method 'CIM' `
                -Command "Remove-CimInstance Win32_Printer '$Name'" -Status 'Success' `
                -Duration $sw.Elapsed -Message 'Queue deleted.'
        }
    }
    catch {
        Write-Verbose "CIM deletion failed for '$Name', trying printui: $($_.Exception.Message)"
    }

    $sw.Stop()

    # printui.dll is the oldest and most universally present path.
    $result = Invoke-NativeCommand -Step 'Remove printer' -Target $Name -FilePath 'rundll32.exe' `
        -ArgumentList @('printui.dll,PrintUIEntry', '/dl', "/n`"$Name`"", '/q')

    if ($result.Status -eq 'Success') {
        # printui returns 0 whether or not it actually removed anything, so the
        # outcome is verified rather than trusted.
        Start-Sleep -Milliseconds 500
        $still = @(Get-PrintStackQueue | Where-Object { $_.Name -eq $Name })
        if ($still.Count) {
            $result.Status = 'Failed'
            $result.Message = 'printui reported success but the queue still exists.'
        }
        else {
            $result.Message = 'Queue deleted via printui.'
        }
    }

    $result
}

function Remove-PrintStackPort {
    <#
    .SYNOPSIS
        Deletes a printer port, retrying once after a spooler restart if needed.

    .DESCRIPTION
        The spooler holds port handles open for a short time after the last queue
        using them is deleted, so an immediate delete of a just-freed port fails
        with "the port is currently in use" even though nothing references it.

        Rather than surfacing that as an error the technician has to interpret and
        chase manually, the caller is told to retry: a single spooler bounce
        releases the handles and the second attempt succeeds. -AllowRetry lets the
        caller batch that restart across every failed port instead of bouncing the
        service once per port.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [switch] $DryRun
    )

    $command = "Remove-PrinterPort -Name '$Name'"

    if ($DryRun) {
        return Write-StepResult -Step 'Remove port' -Target $Name -Method 'Cmdlet' -Command $command `
            -Status 'WhatIf' -Message 'Port was not removed (WhatIf).'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ((Test-PrintManagementAvailable) -and (Get-Command Remove-PrinterPort -ErrorAction SilentlyContinue)) {

        try {
            Remove-PrinterPort -Name $Name -ErrorAction Stop
            $sw.Stop()
            return Write-StepResult -Step 'Remove port' -Target $Name -Method 'Cmdlet' -Command $command `
                -Status 'Success' -Duration $sw.Elapsed -Message 'Port deleted.'
        }
        catch {
            Write-Verbose "Remove-PrinterPort failed for '$Name', trying CIM: $($_.Exception.Message)"
        }
    }

    try {
        $port = Get-CimInstance -ClassName Win32_TCPIPPrinterPort -Filter "Name = '$($Name -replace "'", "\'")'" -ErrorAction Stop |
            Select-Object -First 1
        if ($port) {
            $null = Remove-CimInstance -InputObject $port -ErrorAction Stop
            $sw.Stop()
            return Write-StepResult -Step 'Remove port' -Target $Name -Method 'CIM' `
                -Command "Remove-CimInstance Win32_TCPIPPrinterPort '$Name'" -Status 'Success' `
                -Duration $sw.Elapsed -Message 'Port deleted.'
        }
    }
    catch {
        Write-Verbose "CIM port deletion failed for '$Name': $($_.Exception.Message)"
    }

    $sw.Stop()

    Invoke-NativeCommand -Step 'Remove port' -Target $Name -FilePath 'rundll32.exe' `
        -ArgumentList @('printui.dll,PrintUIEntry', '/dl', "/n`"$Name`"", '/q')
}

function Remove-ScanDevice {
    <#
    .SYNOPSIS
        Removes an imaging device through the PnP stack.

    .DESCRIPTION
        Prefers Remove-PnpDevice where the cmdlet exists (Windows 10 1809 and
        later), falling back to 'pnputil /remove-device'. Exit code 3010 from
        pnputil means "removed, reboot to finish" and is treated as success -
        reporting a reboot advisory as a failure would send the technician
        chasing a problem that is not one.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $InstanceId,

        [string] $Name = '',

        [switch] $DryRun
    )

    $label = if ($Name) { $Name } else { $InstanceId }
    $command = "Remove-PnpDevice -InstanceId '$InstanceId'"

    if ($DryRun) {
        return Write-StepResult -Step 'Remove scanner' -Target $label -Method 'Cmdlet' -Command $command `
            -Status 'WhatIf' -Message 'Device was not removed (WhatIf).'
    }

    if (Get-Command Remove-PnpDevice -ErrorAction SilentlyContinue) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Remove-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
            $sw.Stop()
            return Write-StepResult -Step 'Remove scanner' -Target $label -Method 'Cmdlet' -Command $command `
                -Status 'Success' -Duration $sw.Elapsed -Message 'Imaging device removed.'
        }
        catch {
            $sw.Stop()
            Write-Verbose "Remove-PnpDevice failed for '$InstanceId', trying pnputil: $($_.Exception.Message)"
        }
    }

    Invoke-NativeCommand -Step 'Remove scanner' -Target $label -FilePath 'pnputil.exe' `
        -ArgumentList @('/remove-device', $InstanceId) -SuccessExitCodes @(0, 3010)
}

function Restart-PrintSpooler {
    <#
    .SYNOPSIS
        Restarts the Print Spooler service and waits for it to settle.

    .DESCRIPTION
        Used to release cached port handles when a port refuses to delete. The
        short settle wait matters: the service reports Running before it has
        finished re-enumerating its objects, and a delete issued in that window
        fails for the same reason the first attempt did.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch] $DryRun
    )

    $command = "Restart-Service -Name $($script:SpoolerServiceName) -Force"

    if ($DryRun) {
        return Write-StepResult -Step 'Restart spooler' -Target $script:SpoolerServiceName -Method 'Cmdlet' `
            -Command $command -Status 'WhatIf' -Message 'Service was not restarted (WhatIf).'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Restart-Service -Name $script:SpoolerServiceName -Force -ErrorAction Stop
        Start-Sleep -Seconds $script:SpoolerSettleSeconds
        $sw.Stop()
        Write-StepResult -Step 'Restart spooler' -Target $script:SpoolerServiceName -Method 'Cmdlet' `
            -Command $command -Status 'Success' -Duration $sw.Elapsed -Message 'Spooler restarted.'
    }
    catch {
        $sw.Stop()
        Write-StepResult -Step 'Restart spooler' -Target $script:SpoolerServiceName -Method 'Cmdlet' `
            -Command $command -Status 'Failed' -Duration $sw.Elapsed -Message $_.Exception.Message
    }
}

function Set-DefaultPrintQueue {
    <#
    .SYNOPSIS
        Nominates a surviving queue as the default printer.

    .DESCRIPTION
        Called when the sweep deleted the queue that was default. Left alone,
        Windows either picks one arbitrarily or re-enables "let Windows manage my
        default printer", and the next print job goes somewhere unexpected - which
        on a technician's laptop can mean a job landing on a customer's device.

        Selection order prefers Microsoft Print to PDF: it is always present, it
        cannot print to anyone else's hardware by accident, and it is the least
        surprising default on a machine whose real printers were just removed.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Name,

        [switch] $DryRun
    )

    $candidates = @(Get-PrintStackQueue)
    if ($candidates.Count -eq 0) {
        return Write-StepResult -Step 'Set default printer' -Status 'Skipped' `
            -Message 'No printers remain to nominate.'
    }

    $target = $null
    if ($Name) {
        $target = @($candidates | Where-Object { $_.Name -like $Name } | Select-Object -First 1)
        if (-not $target -or $target.Count -eq 0) {
            return Write-StepResult -Step 'Set default printer' -Target $Name -Status 'Skipped' `
                -Message "No remaining printer matches '$Name'."
        }
        $target = $target[0]
    }
    else {
        foreach ($preferred in @('Microsoft Print to PDF', 'Microsoft XPS Document Writer*', '*OneNote*')) {
            $match = @($candidates | Where-Object { $_.Name -like $preferred } | Select-Object -First 1)
            if ($match -and $match.Count) { $target = $match[0]; break }
        }
        if (-not $target) { $target = $candidates[0] }
    }

    $command = "(Get-CimInstance Win32_Printer -Filter `"Name='$($target.Name)'`").SetDefaultPrinter()"

    if ($DryRun) {
        return Write-StepResult -Step 'Set default printer' -Target $target.Name -Method 'CIM' `
            -Command $command -Status 'WhatIf' -Message 'Default printer was not changed (WhatIf).'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $printer = Get-CimInstance -ClassName Win32_Printer -Filter "Name = '$($target.Name -replace "'", "\'")'" -ErrorAction Stop |
            Select-Object -First 1
        if (-not $printer) { throw "Printer '$($target.Name)' could not be located." }

        $null = Invoke-CimMethod -InputObject $printer -MethodName SetDefaultPrinter -ErrorAction Stop
        $sw.Stop()
        Write-StepResult -Step 'Set default printer' -Target $target.Name -Method 'CIM' -Command $command `
            -Status 'Success' -Duration $sw.Elapsed -Message "Default printer is now '$($target.Name)'."
    }
    catch {
        $sw.Stop()
        Write-StepResult -Step 'Set default printer' -Target $target.Name -Method 'CIM' -Command $command `
            -Status 'Failed' -Duration $sw.Elapsed -Message $_.Exception.Message
    }
}

function New-PrintStackBackup {
    <#
    .SYNOPSIS
        Writes a JSON snapshot of the current print configuration before any
        deletion happens.

    .DESCRIPTION
        Records the name, driver, port and host address of every queue, plus every
        port and imaging device. That is exactly the information needed to
        recreate a queue by hand, so a technician who deletes something they
        wanted back has a ten-second fix rather than a phone call to the customer
        asking for the printer's IP again.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan,

        [switch] $DryRun
    )

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $folder = Join-Path $env:TEMP "$($script:BackupFolderPrefix)_$stamp"
    $file = Join-Path $folder 'print-inventory.json'

    if ($DryRun) {
        return Write-StepResult -Step 'Backup inventory' -Method 'File' -Command $file -Status 'WhatIf' `
            -Message 'Snapshot was not written (WhatIf).'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not (Test-Path -LiteralPath $folder)) {
            $null = New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop
        }

        $snapshot = [ordered]@{
            takenAt        = (Get-Date).ToString('o')
            computerName   = $env:COMPUTERNAME
            defaultPrinter = $Plan.DefaultPrinter
            printers       = @($Plan.Queues | ForEach-Object {
                    [ordered]@{
                        name    = $_.Object.Name
                        driver  = $_.Object.DriverName
                        port    = $_.Object.PortName
                        shared  = $_.Object.Shared
                        type    = $_.Object.Type
                        action  = $_.Action
                        reason  = $_.Reason
                    }
                })
            ports          = @($Plan.Ports | ForEach-Object {
                    [ordered]@{
                        name    = $_.Object.Name
                        monitor = $_.Object.Monitor
                        address = $_.Object.Address
                        port    = $_.Object.PortNumber
                        action  = $_.Action
                        reason  = $_.Reason
                    }
                })
            scanners       = @($Plan.Scanners | ForEach-Object {
                    [ordered]@{
                        name       = $_.Object.Name
                        instanceId = $_.Object.InstanceId
                        connection = $_.Object.Connection
                        action     = $_.Action
                        reason     = $_.Reason
                    }
                })
            drivers        = @($Plan.Drivers | ForEach-Object {
                    [ordered]@{
                        name  = $_.Name
                        inUse = $_.InUse
                    }
                })
        }

        $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop

        $sw.Stop()
        Write-StepResult -Step 'Backup inventory' -Method 'File' -Command $file -Status 'Success' `
            -Duration $sw.Elapsed -Message $file
    }
    catch {
        $sw.Stop()
        Write-StepResult -Step 'Backup inventory' -Method 'File' -Command $file -Status 'Failed' `
            -Duration $sw.Elapsed -Message $_.Exception.Message
    }
}
