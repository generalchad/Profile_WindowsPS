@{
    RootModule           = 'Format-UsbDrive.psm1'
    ModuleVersion        = '1.1.0'
    GUID                 = 'cb63a23c-b797-4050-b6b9-c5dac8f4d8a3'
    Author               = 'GenChadT'
    CompanyName          = 'Unknown'
    Copyright            = '(c) GenChadT. All rights reserved.'

    Description          = 'Formats removable USB drives (under 70GB) to FAT32, exFAT or NTFS with safety guards against touching non-USB or oversized disks, plus Xerox, Kyocera and generic MFD firmware-upgrade profiles.'

    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Storage module provides Get-Disk / Get-Partition / Get-Volume / Format-Volume.
    RequiredModules      = @(
        @{ ModuleName = 'Storage'; ModuleVersion = '2.0.0.0' }
    )

    FunctionsToExport    = @('Format-UsbDrive')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('USB', 'Disk', 'Format', 'FAT32', 'exFAT', 'NTFS', 'Removable', 'Windows', 'Xerox', 'Kyocera', 'MFD', 'Firmware')
            ProjectUri   = 'https://github.com/genchadt/Profile_WindowsPS'
            ReleaseNotes = @'
1.1.0
- Added MFD firmware-upgrade profiles: -Xerox, -Kyocera and -GeneralMfd.
  Each forces FAT32, applies a default label (XEROX-FW-UPGRADE,
  KYOCERA-FW-UPGRADE, MFD-UPGRADE), and prints vendor-specific reminders.
- Advisory notifications: warns on drives larger than 8GB and 16GB, and on
  USB 3.0+ (best-effort detection). Labels over the 11-char FAT32 limit are
  truncated (the word UPGRADE is shortened).
- Profiles are mutually exclusive with -Format (separate parameter sets).

1.0.0
- Initial release.
- Targets only removable USB drives (BusType USB) under 70GB.
- -Name sets the new volume label, -Format selects FAT32 (default), exFAT or NTFS.
- -Target accepts explicit drive letters; otherwise all candidates are auto-detected.
- FAT32 is refused for partitions over 32GB (Windows native limit).
- -Force skips confirmation, -Help prints usage, -WhatIf previews without writing.
'@
        }
    }
}
