#
# Module manifest for module 'New-CliCommandShortcut'
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'New-CliCommandShortcut.psm1'

# Version number of this module.
ModuleVersion = '1.1.0'

# Supported PSEditions
CompatiblePSEditions = @('Core')

# ID used to uniquely identify this module
GUID = 'be98d69d-6adf-40b7-84af-038f12e80b04'

# Author of this module
Author = 'Timothy W. Brown'

# Company or vendor of this module
CompanyName = 'Timothy W. Brown'

# Copyright statement for this module
Copyright = '(c) Timothy W. Brown. Authored with LLM assistance (Anthropic Claude, Google Gemini, DeepSeek). All rights reserved.'

# Description of the functionality provided by this module
Description = 'Creates a .lnk shortcut that re-runs the most recent non-destructive command from PSReadLine history, skipping commands that mutate or destroy state.'

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '7.2'

# Functions to export from this module
FunctionsToExport = @('New-CliCommandShortcut')

# Cmdlets to export from this module
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = @()

# Aliases to export from this module
AliasesToExport = @()

# List of all files packaged with this module
FileList = @(
    'New-CliCommandShortcut.psd1'
    'New-CliCommandShortcut.psm1'
    'Tests\New-CliCommandShortcut.Tests.ps1'
)

# Private data to pass to the module specified in RootModule/ModuleToProcess.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('Shortcut', 'lnk', 'PSReadLine', 'History', 'Desktop')

        # A URL to the license for this module.
        LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'

        # ReleaseNotes of this module
        ReleaseNotes = @'
1.1.0
  - Default selection now skips the invoking command: -Skip defaults to 1 and
    New-CliCommandShortcut entries are never selected, so the shortcut points at
    the command run just before.
  - Added -Skip, -Scan, -Index, -List, and -IncludeDestructive for history
    selection and inspection.

1.0.0
  - Initial release.
'@

    } # End of PSData hashtable

} # End of PrivateData hashtable

}
