@{
    RootModule        = 'Get-CustomModule.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '78a603c0-639b-4a77-9f1a-40705b24abe8'
    Author            = 'Timothy W. Brown'
    CompanyName       = 'Timothy W. Brown'
    Copyright         = '(c) Timothy W. Brown. Authored with LLM assistance (Anthropic Claude, Google Gemini, DeepSeek). All rights reserved.'
    Description       = "Lists the profile's custom modules with their version, description, exported commands, and aliases."
    PowerShellVersion = '7.0'

    FunctionsToExport = @('Get-CustomModule')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
