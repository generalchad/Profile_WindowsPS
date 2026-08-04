#
# Module manifest for module 'Optimize-PSX'
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'Optimize-PSX.psm1'

# Version number of this module.
ModuleVersion = '2.0.0'

# Supported PSEditions
CompatiblePSEditions = @('Core')

# ID used to uniquely identify this module
GUID = '940e5974-a530-4623-8a4d-9977e20e2c23'

# Author of this module
Author = 'GenChadT'

# Company or vendor of this module
CompanyName = 'Unknown'

# Copyright statement for this module
Copyright = '(c) GenChadT. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Extracts disc image archives and compresses PS1/PS2, Saturn and Dreamcast images into CHD files using chdman, with parallel conversion, cue/gdi validation and verified source cleanup.'

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '7.6'

# Functions to export from this module
FunctionsToExport = 'Optimize-PSX'

# Cmdlets to export from this module
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = @()

# Aliases to export from this module
AliasesToExport = 'opsx'

# List of all files packaged with this module
FileList = @(
    'Optimize-PSX.psd1'
    'Optimize-PSX.psm1'
    'Private\_Config.ps1'
    'Private\Complete-ChdmanProcess.ps1'
    'Private\Expand-OpsxArchive.ps1'
    'Private\Format-OpsxSize.ps1'
    'Private\Get-OpsxConcurrencyPlan.ps1'
    'Private\Get-OpsxConversionPlan.ps1'
    'Private\Get-OpsxFileIndex.ps1'
    'Private\Get-OpsxMediaType.ps1'
    'Private\Initialize-OpsxLog.ps1'
    'Private\Invoke-ChdmanBatch.ps1'
    'Private\New-OpsxJob.ps1'
    'Private\Read-CueSheet.ps1'
    'Private\Read-GdiSheet.ps1'
    'Private\Remove-OpsxSource.ps1'
    'Private\Remove-OpsxTempFile.ps1'
    'Private\Repair-CueSheet.ps1'
    'Private\Resolve-ChdmanBinary.ps1'
    'Private\Send-OpsxToRecycleBin.ps1'
    'Private\Show-OpsxPlan.ps1'
    'Private\Start-ChdmanProcess.ps1'
    'Private\Update-ChdmanProgress.ps1'
    'Private\Write-OpsxLog.ps1'
    'Private\Write-OpsxSummary.ps1'
    'Public\Optimize-PSX.ps1'
)

# Private data to pass to the module specified in RootModule/ModuleToProcess.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('CHD', 'chdman', 'MAME', 'PSX', 'PS2', 'Dreamcast', 'Saturn', 'DiscImage', 'Compression', 'Retro')

        # A URL to the license for this module.
        # LicenseUri = ''

        # A URL to the main website for this project.
        # ProjectUri = ''

        # A URL to an icon representing this module.
        # IconUri = ''

        # External modules this module can use when present.
        ExternalModuleDependencies = @('7Zip4PowerShell')

        # ReleaseNotes of this module
        ReleaseNotes = @'
2.0.0
  - Refactored the monolithic .psm1 into Private\ and Public\ files with a
    thin loader, matching the layout used by the other modules here.
  - Conversions now run as a pool of concurrent chdman processes sized from
    a -CpuBudget percentage, with a separate -ThreadsPerJob dial for each
    process. -Sequential and -MaxConcurrency override the derived values.
  - Concurrency is reduced to one on rotational media, detected through the
    Storage provider. -IgnoreDiskType opts out.
  - The target tree is enumerated once into a reusable index instead of
    once per phase.
  - Conversion inputs are the disc sheets plus ISOs not described by a
    sheet, so each disc converts once and track files are never compressed
    on their own.
  - Cue and GDI sheets are parsed and validated during planning. Unresolved
    references are reported before any process starts.
  - Cue repair is opt-in via -RepairCueSheets, limited to unambiguous
    single-track sheets, takes a .bak first, and writes UTF-8 without BOM.
    Multi-track sheets are never modified.
  - Output is written to a temporary file and promoted only after chdman
    exits cleanly with a non-empty result.
  - Cleanup is driven by verified conversions rather than an extension
    sweep, and defaults to the Recycle Bin. -PermanentDelete opts out.
  - Added -Compression for an explicit codec chain, validated up front.
  - createdvd is selected for DVD-sized ISOs when the chdman build
    supports it.
  - Replaced -DeleteArchive/-DeleteImage with -RemoveArchives/-RemoveImages,
    -SkipArchive with -SkipExtraction, and the Verbose verbosity level with
    Detailed. Added -PassThru for a structured result object.

1.1.1
  - Previous single-file release.
'@

        # Prerelease string of this module
        # Prerelease = ''

        # Flag to indicate whether the module requires explicit user acceptance for install/update/save
        # RequireLicenseAcceptance = $false

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module.
# DefaultCommandPrefix = ''

}
