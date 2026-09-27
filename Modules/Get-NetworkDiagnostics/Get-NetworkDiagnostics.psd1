@{
    RootModule           = 'Get-NetworkDiagnostics.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'b208985d-85fa-4c6e-b6a4-68f44d8c6b90'
    Author               = 'Timothy Brown'
    Description          = 'One-shot network triage for unfamiliar sites: adapter inventory, DNS validation, reachability, egress, and ticket-ready HTML/JSON reporting.'
    PowerShellVersion    = '7.0'
    FunctionsToExport    = @('Get-NetworkDiagnostics')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('Test-NetworkDiagnostics')
}
