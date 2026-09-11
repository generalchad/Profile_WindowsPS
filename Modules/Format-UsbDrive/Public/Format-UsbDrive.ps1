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

        MFD FIRMWARE PROFILES
        -Xerox, -Kyocera and -GeneralMfd format the drive for multifunction-device
        firmware upgrades. Each forces FAT32, applies a default volume label, and
        prints vendor-specific reminders plus advisories about drive size and USB
        version (e.g. larger than 8/16GB, or a USB 3.0+ drive).

        SAFETY GUARDS (always active, even with -Force)
          * Non-USB disks are refused.
          * Disks at or above 70GB are refused.
          * FAT32 is refused on partitions larger than 32GB (a Windows native
            limit) - use exFAT or NTFS instead.

        Requires an elevated (Administrator) session.

    .PARAMETER Name
        The label applied to the newly formatted volume (e.g. -Name 'USB-BACKUP').
        Overrides a profile's default label. FAT32 labels are limited to 11
        characters; longer labels are truncated to fit.

    .PARAMETER Format
        The filesystem to use: FAT32 (default), exFAT or NTFS. Only available
        without a profile.

    .PARAMETER Xerox
        Format for a Xerox MFD firmware upgrade (FAT32, .dlm in an "Upgrades" folder).

    .PARAMETER Kyocera
        Format for a Kyocera MFD firmware upgrade (FAT or FAT32; FAT32 used here).

    .PARAMETER GeneralMfd
        Format for a generic MFD firmware upgrade (FAT32, most compatible).

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
        Format-UsbDrive -Target E -Xerox

        Formats drive E: to FAT32 with the Xerox profile (label, size and USB advisories).

    .EXAMPLE
        Format-UsbDrive -Target E -Kyocera -Name 'FIRMWARE'

        Formats drive E: with the Kyocera profile, overriding the label.

    .EXAMPLE
        Format-UsbDrive -GeneralMfd -Force

        Formats every detected removable USB drive with the generic MFD profile, no prompt.

    .EXAMPLE
        Format-UsbDrive -Xerox -WhatIf

        Shows the drive selection and advisories without writing anything.

    .NOTES
        Author   : GenChadT
        Requires : Administrator rights.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Custom')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false, ParameterSetName = 'Custom')]
        [ValidateSet('FAT32', 'exFAT', 'NTFS')]
        [string]$Format = 'FAT32',

        [Parameter(Mandatory = $true, ParameterSetName = 'Xerox')]
        [switch]$Xerox,

        [Parameter(Mandatory = $true, ParameterSetName = 'Kyocera')]
        [switch]$Kyocera,

        [Parameter(Mandatory = $true, ParameterSetName = 'GeneralMfd')]
        [switch]$GeneralMfd,

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
        Write-Host '  Format-UsbDrive [-Xerox | -Kyocera | -GeneralMfd] [-Name <label>] [-Force] [-Help] [-Target <letters>] [-WhatIf]'
        Write-Host ''
        Write-Host 'Options:' -ForegroundColor Cyan
        Write-Host '  -Name        New volume label (overrides a profile default)'
        Write-Host '  -Format      Filesystem to apply (default FAT32; not available with a profile)'
        Write-Host '  -Xerox       Format for a Xerox MFD firmware upgrade (FAT32)'
        Write-Host '  -Kyocera     Format for a Kyocera MFD firmware upgrade (FAT32)'
        Write-Host '  -GeneralMfd  Format for a generic MFD firmware upgrade (FAT32)'
        Write-Host '  -Force       Skip the confirmation prompt'
        Write-Host '  -Target      Explicit drive letter(s), e.g. -Target E  (default: auto-detect all)'
        Write-Host '  -Help        Show this usage'
        Write-Host ''
        Write-Host 'Examples:' -ForegroundColor Cyan
        Write-Host '  Format-UsbDrive                      # detect + prompt, FAT32'
        Write-Host '  Format-UsbDrive -Target E -Name X    # format E: with label X'
        Write-Host '  Format-UsbDrive -Target E -Xerox     # Xerox firmware profile'
        Write-Host '  Format-UsbDrive -Xerox -WhatIf       # preview + advisories only'
        Write-Host ''
        return
    }

    $dryRun = [bool]$WhatIfPreference

    # ---- Profile resolution ---------------------------------------------------
    $profileName = switch ($PSCmdlet.ParameterSetName) {
        'Xerox'      { 'Xerox'; break }
        'Kyocera'    { 'Kyocera'; break }
        'GeneralMfd' { 'GeneralMfd'; break }
        default      { $null }
    }

    $profileMeta = @{
        Xerox      = @{
            Label = 'XEROX-FW-UPGRADE'
            Notes = @('Place the .dlm firmware file in an "Upgrades" folder at the drive root.')
        }
        Kyocera    = @{
            Label = 'KYOCERA-FW-UPGRADE'
            Notes = @('Newer Kyocera models support multi-model firmware via per-model folders; older models read firmware from the drive root.')
        }
        GeneralMfd = @{
            Label = 'MFD-UPGRADE'
            Notes = @('FAT32 is the most widely supported MFD filesystem. Keep the drive at or under 32GB.')
        }
    }

    # A profile forces FAT32 (Xerox requires it; Kyocera/MFD accept FAT/FAT32).
    $FileSystem = if ($profileName) { 'FAT32' } else { $Format }

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

    # ---- Label resolution + FAT32 truncation ---------------------------------
    $label = $Name
    if (-not $label -and $profileName) { $label = $profileMeta[$profileName].Label }

    if ($FileSystem -eq 'FAT32' -and $label -and $label.Length -gt 11) {
        $truncated = $label.Substring(0, 11)
        Write-Warning "Volume label '$label' exceeds the 11-character FAT32 limit and was truncated to '$truncated'."
        $label = $truncated
    }

    # ---- FAT32 32GB limit -----------------------------------------------------
    if ($FileSystem -eq 'FAT32') {
        $oversized = @($resolved | Where-Object { $_.SizeBytes -gt 32GB })
        if ($oversized.Count -gt 0) {
            $labels = ($oversized | ForEach-Object { "$($_.DriveLetter): ($($_.SizeGB)GB)" }) -join ', '
            if ($profileName) {
                throw ("$profileName MFD profiles require FAT32, which Windows cannot create on " +
                    "partitions larger than 32GB. Affected: $labels. Use a drive 32GB or smaller.")
            }
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
    $header = 'Targets (removable USB, <70GB) - formatting as {0}' -f $FileSystem
    if ($profileName) { $header += " [$profileName MFD profile]" }
    Write-Host $header -ForegroundColor Cyan
    Write-Host ('-' * 80) -ForegroundColor DarkGray

    $table = $resolved | Select-Object @{n = 'Drive'; e = { "$($_.DriveLetter):" } },
        @{n = 'SizeGB'; e = { $_.SizeGB } },
        @{n = 'USB'; e = { $_.UsbSpeed } },
        @{n = 'FileSystem'; e = { $_.FileSystem } },
        @{n = 'Label'; e = { $_.VolumeLabel } },
        @{n = 'Device'; e = { $_.FriendlyName } }
    $table | Format-Table -AutoSize | Out-String | Write-Host

    $newLabel = if ($label) { $label } else { '(none)' }
    Write-Host ('New filesystem: {0}    New label: {1}' -f $FileSystem, $newLabel) -ForegroundColor DarkGray
    Write-Host ''

    # ---- Advisories (informational, always shown) -----------------------------
    foreach ($t in $resolved) {
        $drive = "$($t.DriveLetter):"

        if ($t.SizeGB -gt 8) {
            Write-Warning "$drive is $($t.SizeGB) GB - larger than 8 GB. Some older MFDs may not read drives this large; 8 GB or less is recommended."
        }
        if ($t.SizeGB -gt 16) {
            Write-Warning "$drive is $($t.SizeGB) GB - larger than 16 GB. Verify the specific model supports it before relying on it."
        }

        switch ($t.UsbSpeed) {
            'USB3' {
                Write-Host "  $drive : USB 3.0+ detected - some MFDs prefer USB 2.0; if the device does not see the drive, try a USB 2.0 drive." -ForegroundColor DarkYellow
            }
            'USB1' {
                Write-Host "  $drive : USB 1.1 detected - slow but widely compatible." -ForegroundColor DarkGray
            }
            default {
                Write-Host "  $drive : USB version could not be determined - USB 2.0 is recommended for older MFDs." -ForegroundColor DarkYellow
            }
        }
    }

    if ($profileName) {
        foreach ($note in $profileMeta[$profileName].Notes) {
            Write-Host "  Note: $note" -ForegroundColor DarkCyan
        }
    }
    Write-Host ''

    if ($dryRun) {
        foreach ($t in $resolved) {
            if ($PSCmdlet.ShouldProcess("$($t.DriveLetter):", "Format as $FileSystem")) {
                Write-Host "  [WhatIf] Would format $($t.DriveLetter): as $FileSystem" -ForegroundColor DarkGray
            }
        }
        Write-Host ''
        return
    }

    # ---- Confirmation ---------------------------------------------------------
    if (-not $Force) {
        $drives = ($resolved | ForEach-Object { "$($_.DriveLetter):" }) -join ', '
        $prompt = "Format $($resolved.Count) drive(s) ($drives) as $FileSystem and DESTROY all data on them?"
        if (-not $PSCmdlet.ShouldContinue($prompt, 'Format-UsbDrive')) {
            Write-Host 'Cancelled - nothing was changed.' -ForegroundColor Cyan
            return
        }
    }

    # ---- Format ---------------------------------------------------------------
    foreach ($t in $resolved) {
        if (-not $PSCmdlet.ShouldProcess("$($t.DriveLetter):", "Format as $FileSystem")) { continue }

        Write-Host ('Formatting {0}: ({1} GB) as {2}...' -f $t.DriveLetter, $t.SizeGB, $FileSystem) -ForegroundColor Cyan
        try {
            $formatParams = @{
                DriveLetter = $t.DriveLetter
                FileSystem  = $FileSystem
                Confirm     = $false
                ErrorAction = 'Stop'
            }
            if ($label) { $formatParams['NewFileSystemLabel'] = $label }

            Format-Volume @formatParams

            Write-Host ('  Done: {0}: formatted as {1}' -f $t.DriveLetter, $FileSystem) -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to format $($t.DriveLetter): : $($_.Exception.Message)"
        }
    }

    Write-Host ''
}
