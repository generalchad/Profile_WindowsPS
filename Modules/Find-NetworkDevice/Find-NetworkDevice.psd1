@{
    RootModule           = 'Find-NetworkDevice.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'f52b826a-9f5b-4ec6-8d19-4f7f2b9ca810'
    Author               = 'Timothy Brown'
    Description          = 'Subnet sweep to discover devices, resolve MAC/OUI vendors, probe printer ports, and pipe to Get-PrinterInfo.'
    PowerShellVersion    = '7.0'
    FunctionsToExport    = @('Find-NetworkDevice')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('Sweep-Subnet')
}
