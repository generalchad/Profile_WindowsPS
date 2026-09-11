function Format-UsbDrive {
    <#
    .SYNOPSIS
        Formats removable USB drives (under 70GB) to FAT32, exFAT or NTFS.

    .DESCRIPTION
        Format-UsbDrive is a safety-focused wrapper around Format-Volume for USB
        sticks. It only ever touches disks that are removable USB drives smaller
        than 70GB, which prevents a mistyped command from wiping an internal or
        large external drive.

        With no -Target it auto-detects every removable USB drive under 70GB that
        currently has a drive letter, shows them in a table, and asks for a single
        confirmation before formatting. Pass -Target to limit the operation to
        explicit drive letters (still validated as USB and under 70GB).

        SAFETY GUARDS (always active, even with -Force)
          * Non-USB disks are refused.
          * Disks at or above 70GB are refused.
          * FAT32 is refused on partitions larger than 32GB (a Windows native
            limit) - use exFAT or NTFS instead.

        Requires an elevated (Administrator) session.

    .PARAMETER Name
        The label applied to the newly formatted volume (e.g. -Name 'USB-BACKUP').
        FAT32 labels are limited to 11 characters.

    .PARAMETER Format
        The filesystem to use: FAT32 (default), exFAT or NTFS.

    .PARAMETER Force
        Skip the confirmation prompt and format every resolved target immediately.

    .PARAMETER Help
        Print a short usage summary and return without doing anything.

    .PARAMETER Target
        One or more drive letters to format (e.g. -Target E, F). Accepted forms are
        'E', 'E:' and 'E:\'. When omitted, all removable USB drives under 70GB are
        auto-detected.

    .EXAMPLE
        Format-UsbDrive

        Auto-detects removable USB drives under 70GB, lists them, and prompts before
        formatting each to FAT32.

    .EXAMPLE
        Format-UsbDrive -Target E -Name 'INSTALL' -Format exFAT

        Formats only drive E: to exFAT with the label INSTALL.

    .EXAMPLE
        Format-UsbDrive -Target E -Force

        Formats drive E: to FAT32 without any prompt.

    .EXAMPLE
        Format-UsbDrive -WhatIf

        Shows exactly which drives would be formatted, without writing anything.

    .NOTES
        Author   : GenChadT
        Requires : Administrator rights.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateSet('FAT32', 'exFAT', 'NTFS')]
        [string]$Format = 'FAT32',

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$Help,

        [Parameter(Mandatory = $false, Position = 0)]
        [string[]]$Target
    )

    if ($Help) {
        Write-Host ''
        Write-Host 'Format-UsbDrive' -ForegroundColor Cyan
        Write-Host '  Formats removable USB drives (under 70GB) to FAT32, exFAT or NTFS.' -ForegroundColor Gray
        Write-Host ''
        Write-Host 'Usage:' -ForegroundColor Cyan
        Write-Host '  Format-UsbDrive [-Name <label>] [-Format FAT32|exFAT|NTFS] [-Force] [-Help] [-Target <letters>] [-WhatIf]'
        Write-Host ''
        Write-Host 'Options:' -ForegroundColor Cyan
        Write-Host '  -Name    New volume label (e.g. -Name "USB-BACKUP")'
        Write-Host '  -Format  Filesystem to apply (default FAT32)'
        Write-Host '  -Force   Skip the confirmation prompt'
        Write-Host '  -Target  Explicit drive letter(s), e.g. -Target E  (default: auto-detect all)'
        Write-Host '  -Help    Show this usage'
        Write-Host ''
        Write-Host 'Examples:' -ForegroundColor Cyan
        Write-Host '  Format-UsbDrive                    # detect + prompt, FAT32'
        Write-Host '  Format-UsbDrive -Target E -Name X  # format E: with label X'
        Write-Host '  Format-UsbDrive -Target E -WhatIf  # preview only'
        Write-Host ''
        return
    }

    $dryRun = [bool]$WhatIfPreference

    # ---- Resolve targets ------------------------------------------------------
    $resolved = [System.Collections.Generic.List[object]]::new()

    if ($Target) {
        foreach ($letter in $Target) {
            $resolved.Add((Resolve-UsbDriveLetter -Letter $letter))
        }
    }
    else {
        $detected = @(Get-RemovableUsbTarget)
        if ($detected.Count -eq 0) {
            Write-Warning 'No removable USB drives under 70GB were found.'
            return
        }
        foreach ($t in $detected) { $resolved.Add($t) }
    }

    if ($resolved.Count -eq 0) {
        Write-Warning 'No drives matched the request.'
        return
    }

    # ---- FAT32 32GB limit -----------------------------------------------------
    if ($Format -eq 'FAT32') {
        $oversized = @($resolved | Where-Object { $_.SizeBytes -gt 32GB })
        if ($oversized.Count -gt 0) {
            $labels = ($oversized | ForEach-Object { "$($_.DriveLetter): ($($_.SizeGB)GB)" }) -join ', '
            throw ("FAT32 cannot be created on partitions larger than 32GB by Windows. " +
                "Affected: $labels. Use -Format exFAT or -Format NTFS instead.")
        }
    }

    # ---- Elevation gate -------------------------------------------------------
    $elevated = Test-Elevation
    if (-not $elevated -and -not $dryRun) {
        throw ("Format-UsbDrive requires an elevated session. Relaunch with: $(Get-ElevationHint)")
    }
    if (-not $elevated -and $dryRun) {
        Write-Warning 'Not elevated - this is a preview only. Formatting requires an elevated session.'
    }

    # ---- Summary --------------------------------------------------------------
    Write-Host ''
    Write-Host ('Targets (removable USB, <70GB) - formatting as {0}' -f $Format) -ForegroundColor Cyan
    Write-Host ('-' * 80) -ForegroundColor DarkGray

    $table = $resolved | Select-Object @{n = 'Drive'; e = { "$($_.DriveLetter):" } },
        @{n = 'SizeGB'; e = { $_.SizeGB } },
        @{n = 'FileSystem'; e = { $_.FileSystem } },
        @{n = 'Label'; e = { $_.VolumeLabel } },
        @{n = 'Device'; e = { $_.FriendlyName } }
    $table | Format-Table -AutoSize | Out-String | Write-Host

    $newLabel = if ($Name) { $Name } else { '(none)' }
    Write-Host ('New filesystem: {0}    New label: {1}' -f $Format, $newLabel) -ForegroundColor DarkGray
    Write-Host ''

    if ($dryRun) {
        foreach ($t in $resolved) {
            if ($PSCmdlet.ShouldProcess("$($t.DriveLetter):", "Format as $Format")) {
                Write-Host "  [WhatIf] Would format $($t.DriveLetter): as $Format" -ForegroundColor DarkGray
            }
        }
        Write-Host ''
        return
    }

    # ---- Confirmation ---------------------------------------------------------
    if (-not $Force) {
        $drives = ($resolved | ForEach-Object { "$($_.DriveLetter):" }) -join ', '
        $prompt = "Format $($resolved.Count) drive(s) ($drives) as $Format and DESTROY all data on them?"
        if (-not $PSCmdlet.ShouldContinue($prompt, 'Format-UsbDrive')) {
            Write-Host 'Cancelled - nothing was changed.' -ForegroundColor Cyan
            return
        }
    }

    # ---- Format ---------------------------------------------------------------
    foreach ($t in $resolved) {
        if (-not $PSCmdlet.ShouldProcess("$($t.DriveLetter):", "Format as $Format")) { continue }

        Write-Host ('Formatting {0}: ({1} GB) as {2}...' -f $t.DriveLetter, $t.SizeGB, $Format) -ForegroundColor Cyan
        try {
            $formatParams = @{
                DriveLetter        = $t.DriveLetter
                FileSystem         = $Format
                Confirm            = $false
                ErrorAction        = 'Stop'
            }
            if ($Name) { $formatParams['NewFileSystemLabel'] = $Name }

            Format-Volume @formatParams

            Write-Host ('  Done: {0}: formatted as {1}' -f $t.DriveLetter, $Format) -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to format $($t.DriveLetter): : $($_.Exception.Message)"
        }
    }

    Write-Host ''
}
