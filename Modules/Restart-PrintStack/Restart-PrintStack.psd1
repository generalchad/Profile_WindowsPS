@{
    RootModule        = 'Restart-PrintStack.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a4f2c8e1-9b3d-4e7a-8c5f-2d6b1a9e4c73'
    Author            = 'Timothy W. Brown'
    CompanyName       = 'Unknown'
    Copyright         = '(c) Timothy W. Brown. All rights reserved.'
    Description       = 'Returns the Windows printing system to its default state: removes accumulated print queues, orphaned printer ports and stale network scanners while preserving the built-in virtual printers (Microsoft Print to PDF, XPS, OneNote, Fax). Includes an interactive review screen and a persistent per-user allow-list.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Restart-PrintStack'
        'Get-PrintStackInventory'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @(
        'Reset-PrintStack'
    )


    PrivateData       = @{
        PSData = @{
            Tags         = @('Printing', 'Printer', 'Spooler', 'Cleanup', 'Windows', 'Scanner', 'Maintenance')
            ReleaseNotes = @'
1.0.0
- Initial release.
- Restart-PrintStack: plan-and-confirm removal of print queues, orphaned ports
  and network-discovered imaging devices.
- Interactive review screen with per-run keeps and permanent pins.
- Per-user JSON allow-list at %APPDATA%\Restart-PrintStack\allowlist.json.
- JSON backup of the previous configuration written to %TEMP% before any change.
- Get-PrintStackInventory: read-only view of the same plan.
'@
        }
    }
}
