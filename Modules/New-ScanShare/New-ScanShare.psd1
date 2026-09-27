@{
    RootModule           = 'New-ScanShare.psm1'
    ModuleVersion        = '0.3.0'
    GUID                 = 'b735b035-cf82-4c2a-a47e-13783d33079e'
    Author               = 'GenChadt'
    CompanyName          = 'Unknown'
    Copyright            = '(c) GenChadT. All rights reserved.'

    Description          = 'Sets up an SMB scan-to-folder destination for an MFP in one step: a locked-down local account (SMB network logon only), the folder, NTFS and share permissions, and firewall rules, then verifies it with Test-FileShare. Idempotent and -WhatIf aware. Includes an optional Show-ScanShare dialog that runs on Windows PowerShell 5.1 and PowerShell 7.'

    # Kept 5.1-compatible so it can be copied onto client PCs without PowerShell 7.
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Test-FileShare is used for the final verification but is optional: it is
    # autoloaded when present and the step is skipped otherwise.
    RequiredModules      = @()

    FunctionsToExport    = @('New-ScanShare', 'Show-ScanShare')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('SMB', 'Scan', 'MFP', 'Printer', 'Share', 'Troubleshooting', 'Windows')
            ProjectUri = 'https://github.com/genchadt/Profile_WindowsPS'
        }
    }
}
