@{
    RootModule           = 'Get-PrinterInfo.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '4e676117-de4d-49f4-97af-a51cb55d254a'
    Author               = 'Timothy W. Brown'
    CompanyName          = 'Timothy W. Brown'
    Copyright            = '(c) Timothy W. Brown. Authored with LLM assistance (Anthropic Claude, Google Gemini, DeepSeek). All rights reserved.'

    Description          = 'Queries network printers and MFPs over SNMP (Printer MIB / RFC 3805) for model, serial number, page count, status and supply levels. No external SNMP tools required.'

    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @('Get-PrinterInfo')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('Printer', 'MFP', 'SNMP', 'Toner', 'Troubleshooting', 'Windows')
            ProjectUri = 'https://github.com/genchadt/Profile_WindowsPS'
        }
    }
}
