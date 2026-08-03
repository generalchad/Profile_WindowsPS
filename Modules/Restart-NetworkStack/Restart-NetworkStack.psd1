@{
    RootModule           = 'Restart-NetworkStack.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '6168d03a-fd8f-48e4-aa3f-1e84d8525b2d'
    Author               = 'GenChadt'
    CompanyName          = 'Unknown'
    Copyright            = '(c) GenChadT. All rights reserved.'

    Description          = 'Resets and refreshes the Windows network stack - DNS, DHCP, adapters, Winsock, TCP/IP, firewall, proxy, ARP and NetBIOS - from a single opt-in cmdlet. Prefers native PowerShell cmdlets and falls back to ipconfig/netsh/nbtstat where no cmdlet equivalent exists.'

    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Deliberately no RequiredModules: the module degrades to native command
    # fallbacks when NetAdapter / NetTCPIP / DnsClient are unavailable.
    RequiredModules      = @()

    FunctionsToExport    = @('Restart-NetworkStack')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('rns', 'Reset-NetworkStack')

    PrivateData          = @{
        PSData = @{
            Tags         = @(
                'Network', 'DNS', 'DHCP', 'Winsock', 'TCPIP', 'netsh', 'ipconfig',
                'Troubleshooting', 'Windows', 'Reset'
            )
            ProjectUri   = 'https://github.com/genchadt/Profile_WindowsPS'
            ReleaseNotes = @'
1.0.0
- Initial release.
- Opt-in switches: -Dns, -Dhcp, -Adapter, -ArpNetBios (non-destructive) and
  -Winsock, -TcpIp, -Firewall, -Proxy (destructive).
- -Safe runs the complete non-destructive sequence: ARP/NetBIOS purge, adapter
  bounce, DHCP release/renew, DNS flush and re-registration. No prompt, no reboot.
- -Full runs every step in the recommended order.
- Tiered confirmation: non-destructive steps never prompt; the destructive steps
  raise a single consolidated prompt itemising exactly what will be lost.
- Automatic pre-reset backups (IP configuration, firewall policy, proxy settings)
  written to %TEMP% with the restore command printed in the summary. -NoBackup opts out.
- -Force, -Restart, -IncludeIPv6, -InterfaceAlias, -PassThru, -SkipConnectivityTest.
- Full -WhatIf support; every native command is echoed before execution.
- Cmdlet-first with automatic native fallbacks; per-step result objects and summary table.
'@
        }
    }
}
