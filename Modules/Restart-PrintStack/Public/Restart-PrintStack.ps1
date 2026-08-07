function Restart-PrintStack {
    <#
    .SYNOPSIS
        Returns the Windows printing system to its default state by removing
        accumulated printers, orphaned ports and stale network scanners.

    .DESCRIPTION
        Built for a technician's laptop that has collected a queue and a port for
        every customer site it has ever visited. It removes that clutter while
        preserving the printers Windows expects to have: Microsoft Print to PDF,
        the XPS writer, OneNote, Fax and Adobe.

        The default run is deliberately conservative and interactive:

          1. Confirms the session is elevated - the spooler will not accept
             deletions otherwise.
          2. Enumerates every queue, port, driver and imaging device.
          3. Builds a plan classifying each item Keep or Remove, with a reason.
          4. Writes a JSON snapshot of the whole configuration to %TEMP%.
          5. Shows the interactive review screen, where rows can be kept for this
             run or PINNED to the allow-list so they survive every future run.
          6. Persists any pins.
          7. Cancels jobs, removes queues, sweeps orphaned ports, removes stale
             network scanners - in that order, because the spooler will not
             release a port while a queue still references it.
          8. Re-points the default printer if the old default was removed.

        Network connections (\\server\queue) and RDP-redirected queues are kept by
        default. Both are recreated automatically - by Group Policy and by the
        remote session respectively - so removing them accomplishes nothing while
        briefly breaking printing.

    .PARAMETER Keep
        Wildcard patterns to protect for this invocation only. Nothing is written
        to the allow-list file.

    .PARAMETER Remove
        Wildcard patterns to force-remove. Overrides every keep rule including the
        built-in defaults, so a stale 'Adobe PDF' queue can be dropped without
        editing the module.

    .PARAMETER Pin
        Wildcard patterns to append to the allow-list file without going through
        the review screen. Useful when scripting a laptop build.

    .PARAMETER IncludeNetwork
        Also remove \\server\queue connections.

    .PARAMETER IncludeRedirected
        Also remove redirected/RDP session printers.

    .PARAMETER IncludeLocalScanners
        Also remove USB-attached imaging devices. They re-enumerate on reconnect,
        so this is rarely useful.

    .PARAMETER NoPortSweep
        Leave all printer ports alone.

    .PARAMETER NoScanners
        Leave all imaging devices alone.

    .PARAMETER NoBackup
        Skip the JSON snapshot.

    .PARAMETER SetDefault
        Name (wildcards allowed) of the printer to make default afterwards. When
        omitted and the old default was removed, Microsoft Print to PDF is chosen.

    .PARAMETER ConfigPath
        Alternate location for the allow-list file.

    .PARAMETER NonInteractive
        Skip the review screen and use a single yes/no prompt. Implied
        automatically when the host cannot support an interactive screen.

    .PARAMETER Force
        Skip all prompting. Intended for scripted builds.

    .PARAMETER PassThru
        Emit the step result objects instead of only printing the summary.

    .EXAMPLE
        Restart-PrintStack

        Interactive review, then removes everything not protected.

    .EXAMPLE
        Restart-PrintStack -WhatIf

        Shows the full plan and changes nothing.

    .EXAMPLE
        Restart-PrintStack -Keep 'HP LaserJet*' -IncludeNetwork

        Protects the HP queues for this run and also drops server connections.

    .EXAMPLE
        Restart-PrintStack -Force -NoScanners

        Unattended cleanup of queues and ports only.

    .OUTPUTS
        RestartPrintStack.StepResult objects when -PassThru is supplied.

    .NOTES
        Requires an elevated session.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string[]] $Keep = @(),

        [Parameter()]
        [string[]] $Remove = @(),

        [Parameter()]
        [string[]] $Pin = @(),

        [switch] $IncludeNetwork,
        [switch] $IncludeRedirected,
        [switch] $IncludeLocalScanners,
        [switch] $NoPortSweep,
        [switch] $NoScanners,
        [switch] $NoBackup,

        [string] $SetDefault,
        [string] $ConfigPath,

        [switch] $NonInteractive,
        [switch] $Force,
        [switch] $PassThru
    )

    begin {
        Set-StrictMode -Version Latest
        $results = [System.Collections.Generic.List[object]]::new()
        $backupPath = ''

        # -WhatIf must reach the private helpers, which are plain functions rather
        # than ShouldProcess cmdlets, so the preference is captured once here.
        $dryRun = [bool]$WhatIfPreference
    }

    process {
        # -------------------------------------------------------------
        # 1. Elevation
        # -------------------------------------------------------------
        # -WhatIf is allowed to run unelevated: previewing the plan changes
        # nothing, and refusing to show it would force a technician to open an
        # admin window just to find out whether they need one.
        if (-not (Test-Elevation)) {
            if (-not $dryRun) {
                Write-Warning 'Restart-PrintStack requires an elevated session.'
                Write-Host "  Relaunch with: $(Get-ElevationHint)" -ForegroundColor DarkGray
                return
            }
            Write-Warning 'Not elevated - this is a preview only; an elevated session is required to apply it.'
        }


        # -------------------------------------------------------------
        # 2. Allow-list and plan
        # -------------------------------------------------------------
        Write-Verbose 'Building the effective allow-list.'
        $allowList = Get-PrintStackAllowList -Keep $Keep -Remove $Remove -ConfigPath $ConfigPath

        # -Pin is applied before planning so a pattern pinned on the command line
        # protects its printer in this very run, not just in later ones.
        if (@($Pin).Count) {
            $pinResult = Add-PrintStackAllowListEntry -Printer $Pin -ConfigPath $ConfigPath -DryRun:$dryRun
            $results.Add($pinResult)
            $allowList = Get-PrintStackAllowList -Keep $Keep -Remove $Remove -ConfigPath $ConfigPath
        }

        Write-Verbose 'Enumerating the print system.'
        $plan = Get-PrintStackPlan -AllowList $allowList `
            -IncludeNetwork:$IncludeNetwork `
            -IncludeRedirected:$IncludeRedirected `
            -NoPortSweep:$NoPortSweep `
            -NoScanners:$NoScanners `
            -IncludeLocalScanners:$IncludeLocalScanners

        if ($plan.RemoveCount -eq 0) {
            Write-Host ''
            Write-Host '  The print system is already at its default state - nothing to remove.' -ForegroundColor Green
            Write-Host ''
            if ($PassThru) { return $results }
            return
        }

        # -------------------------------------------------------------
        # 3. Backup, before anything is touched
        # -------------------------------------------------------------
        if (-not $NoBackup) {
            $backup = New-PrintStackBackup -Plan $plan -DryRun:$dryRun
            $results.Add($backup)
            if ($backup.Status -eq 'Success') { $backupPath = $backup.Message }
        }

        # -------------------------------------------------------------
        # 4. Review / confirmation
        # -------------------------------------------------------------
        if ($dryRun) {
            Write-Host ''
            Write-Host 'Restart-PrintStack - planned changes (WhatIf)' -ForegroundColor Cyan
            Write-Host ('=' * 78) -ForegroundColor DarkGray
            Show-PrintStackPlan -Plan $plan
            Write-Host ("  {0} item(s) would be removed, {1} kept." -f $plan.RemoveCount, $plan.KeepCount) -ForegroundColor Yellow
            Write-Host ''
            if ($PassThru) { return $results }
            return
        }

        $useReview = -not $Force -and -not $NonInteractive -and (Test-InteractiveHost)

        if ($useReview) {
            $review = Show-PrintStackReview -Plan $plan -NoPortSweep:$NoPortSweep

            if (-not $review.Confirmed) {
                Write-Host '  Cancelled. Nothing was changed.' -ForegroundColor DarkGray
                if ($PassThru) { return $results }
                return
            }

            $plan = $review.Plan

            # Pins are committed only now, after confirmation - cancelling the
            # review must leave the technician's allow-list untouched.
            if (@($review.PinnedPrinters).Count -or @($review.PinnedPorts).Count) {
                $results.Add((Add-PrintStackAllowListEntry `
                            -Printer $review.PinnedPrinters `
                            -Port $review.PinnedPorts `
                            -ConfigPath $ConfigPath))
            }
        }
        elseif (-not $Force) {
            Show-PrintStackPlan -Plan $plan -RemovalsOnly
            Write-Host ("  {0} item(s) will be removed." -f $plan.RemoveCount) -ForegroundColor Yellow

            if (-not $PSCmdlet.ShouldProcess(
                    "$($plan.RemoveCount) printing object(s) on $env:COMPUTERNAME",
                    'Remove')) {
                Write-Host '  Cancelled. Nothing was changed.' -ForegroundColor DarkGray
                if ($PassThru) { return $results }
                return
            }
        }

        if ($plan.RemoveCount -eq 0) {
            Write-Host '  Nothing left to remove after the review.' -ForegroundColor Green
            if ($PassThru) { return $results }
            return
        }

        # -------------------------------------------------------------
        # 5. Removals. Order is load-bearing: jobs, queues, ports, then
        #    scanners. A port cannot be deleted while a queue references
        #    it, and a queue with spooled jobs may refuse to delete.
        # -------------------------------------------------------------
        Write-Host ''
        Write-Host 'Removing...' -ForegroundColor Cyan

        foreach ($item in $plan.PrinterRemovals) {
            $results.Add((Clear-PrintQueueJob -Name $item.Name))
            $results.Add((Remove-PrintQueue -Name $item.Name))
        }

        $portFailures = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $plan.PortRemovals) {
            $r = Remove-PrintStackPort -Name $item.Name
            if ($r.Status -eq 'Failed') {
                $portFailures.Add($item)
            }
            else {
                $results.Add($r)
            }
        }

        # A port whose last queue was deleted moments ago can still report as in
        # use because the spooler caches its handle. One restart releases every
        # such handle, so the retries are batched behind a single bounce rather
        # than restarting the service once per port.
        if ($portFailures.Count) {
            Write-Verbose "$($portFailures.Count) port(s) were still in use; restarting the spooler and retrying."
            $results.Add((Restart-PrintSpooler))

            foreach ($item in $portFailures) {
                $retry = Remove-PrintStackPort -Name $item.Name
                if ($retry.Status -ne 'Success') {
                    $retry.Message = "$($retry.Message) (retried after a spooler restart)"
                }
                $results.Add($retry)
            }
        }

        foreach ($item in $plan.ScannerRemovals) {
            $results.Add((Remove-ScanDevice -InstanceId $item.Object.InstanceId -Name $item.Name))
        }

        # -------------------------------------------------------------
        # 6. Default printer
        # -------------------------------------------------------------
        if ($SetDefault -or $plan.DefaultIsRemoved) {
            $results.Add((Set-DefaultPrintQueue -Name $SetDefault))
        }

        Write-PrintStackSummary -Results $results -BackupPath $backupPath
    }

    end {
        if ($PassThru) { $results }
    }
}
