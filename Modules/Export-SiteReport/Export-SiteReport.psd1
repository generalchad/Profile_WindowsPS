@{
    RootModule           = 'Export-SiteReport.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'c83e18a9-7a31-4195-a2fe-8b17a1024e12'
    Author               = 'Timothy W. Brown'
    CompanyName          = 'Timothy W. Brown'
    Copyright            = '(c) Timothy W. Brown. Authored with LLM assistance (Anthropic Claude, Google Gemini, DeepSeek). All rights reserved.'
    Description          = 'Consolidates system specs, print stack inventory, discovered network printers, and network triage into a single job-ticket artifact.'
    PowerShellVersion    = '7.0'
    FunctionsToExport    = @('Export-SiteReport')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('New-SiteReport')
    PrivateData = @{
        PSData = @{
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
        }
    }
}
