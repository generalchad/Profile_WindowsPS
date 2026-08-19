# -----------------------------------------------------------------------------
# ProfileTools.psm1 - Personal toolbox: functions, utilities and static aliases
# -----------------------------------------------------------------------------
# Dot-sources the loose script files. The manifest (ProfileTools.psd1) declares
# the explicit FunctionsToExport / AliasesToExport lists so PowerShell can
# auto-load this module on first use without paying for it at startup.

foreach ($Folder in 'Functions', 'Utilities') {
    $Path = Join-Path $PSScriptRoot $Folder
    if (Test-Path $Path) {
        foreach ($File in [System.IO.Directory]::GetFiles($Path, '*.ps1')) {
            . $File
        }
    }
}

. (Join-Path $PSScriptRoot 'Aliases.ps1')
