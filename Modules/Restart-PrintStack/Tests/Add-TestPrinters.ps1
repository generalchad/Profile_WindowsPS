# =====================================================================
# Add-TestPrinters.ps1 - Synthetic copier fixtures for exercising the module
#
# Creates fake "copier" print queues on a few different port types so the
# planner's classification and the removal path can be exercised without a
# real device. Every fixture name carries the RPS-Test prefix, so nothing here
# can be mistaken for a genuine queue and cleanup cannot hit the wrong thing.
#
#   pwsh -NoProfile -File .\Tests\Add-TestPrinters.ps1           # add fixtures
#   pwsh -NoProfile -File .\Tests\Add-TestPrinters.ps1 -Cleanup  # remove them
#   pwsh -NoProfile -File .\Tests\Add-TestPrinters.ps1 -List     # print the plan only
#
# Port types that CAN be synthesised here: Standard TCP/IP (JetDirect), LPR/LPD
# and Local Port. WSD and IPP cannot be created from cmdlets alone - WSD needs a
# real device on the wire, and IPP has no Add-PrinterPort parameter set - so
# those are documented in the module README and reproduced on a real machine.
# =====================================================================

[CmdletBinding()]
param(
    [switch] $Cleanup,
    [switch] $List
)

$ErrorActionPreference = 'Stop'

# TEST-NET-1 addresses (RFC 5737) are guaranteed non-routable and never belong
# to a real device, so the ports cannot accidentally point at a live printer.
$Prefix = 'RPS-Test'

$Fixtures = @(
    [ordered]@{
        Queue   = "$Prefix Kyocera TASKalfa 4052ci"
        Port    = "$Prefix-TCP-192.0.2.10"
        Kind    = 'TcpIp'
        Address = '192.0.2.10'
    }
    [ordered]@{
        Queue   = "$Prefix Canon iR-ADV C5560"
        Port    = "$Prefix-LPD-192.0.2.11"
        Kind    = 'Lpr'
        Address = '192.0.2.11'
    }
    [ordered]@{
        Queue   = "$Prefix Xerox WorkCentre 6515"
        Port    = "$Prefix-Local"
        Kind    = 'Local'
    }
)

function Get-TestDriver {
    <#
    .SYNOPSIS
        Returns the name of an installed driver that is NOT on the module's keep
        list, so the fixture queues classify as Remove rather than Keep-by-driver.
    #>
    [CmdletBinding()]
    param()

    $preferred = @(
        'Microsoft IPP Class Driver'
        'Universal Print Class Driver'
        'Microsoft Virtual Print Class Driver'
        'Remote Desktop Easy Print'
        'Microsoft enhanced Point and Print compatibility driver'
    )

    $installed = @(Get-PrinterDriver -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)

    foreach ($candidate in $preferred) {
        if ($installed -contains $candidate) { return $candidate }
    }

    throw 'No non-protected printer driver is installed; install one and retry.'
}

function Add-RpsPort {
    [CmdletBinding()]
    param([hashtable] $Fixture)

    switch ($Fixture.Kind) {
        'TcpIp' { Add-PrinterPort -Name $Fixture.Port -PrinterHostAddress $Fixture.Address -PortNumber 9100 }
        'Lpr'   { Add-PrinterPort -Name $Fixture.Port -LprHostAddress $Fixture.Address -LprQueueName 'lp' }
        'Local' { Add-PrinterPort -Name $Fixture.Port }
    }
}

function Remove-RpsPort {
    [CmdletBinding()]
    param([hashtable] $Fixture)

    if (Get-PrinterPort -Name $Fixture.Port -ErrorAction SilentlyContinue) {
        Remove-PrinterPort -Name $Fixture.Port -ErrorAction SilentlyContinue
    }
}

if ($List) {
    Write-Host ''
    Write-Host 'Add-TestPrinters - fixtures' -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor DarkGray
    foreach ($f in $Fixtures) {
        Write-Host ('  {0,-6}  {1,-30} {2}' -f $f.Kind, $f.Queue, $f.Port) -ForegroundColor DarkGray
    }
    Write-Host ''
    return
}

# Adding and removing printers both need elevation; -List is exempt because it
# only prints the fixture table. Guarded manually rather than with #Requires so
# the -List mode stays runnable from an unelevated shell.
$isAdmin = ([Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw 'This script must be run elevated to add or remove printers.'
}

$driver = Get-TestDriver
Write-Host ('Driver in use: {0}' -f $driver) -ForegroundColor DarkGray

foreach ($fixture in $Fixtures) {
    if ($Cleanup) {
        Write-Host ('Removing {0} ({1})' -f $fixture.Queue, $fixture.Kind) -ForegroundColor DarkGray
        if (Get-Printer -Name $fixture.Queue -ErrorAction SilentlyContinue) {
            Remove-Printer -Name $fixture.Queue -ErrorAction SilentlyContinue
        }
        Remove-RpsPort -Fixture $fixture
        continue
    }

    Write-Host ('Adding {0} ({1})' -f $fixture.Queue, $fixture.Kind) -ForegroundColor DarkGray
    try {
        Add-RpsPort -Fixture $fixture
        Add-Printer -Name $fixture.Queue -DriverName $driver -PortName $fixture.Port -ErrorAction Stop
        Write-Host '  done.' -ForegroundColor Green
    }
    catch {
        Write-Warning "  skipped: $($_.Exception.Message)"
    }
}

if (-not $Cleanup) {
    Write-Host ''
    Write-Host '  Now preview how they classify:' -ForegroundColor Cyan
    Write-Host '    Import-Module Restart-PrintStack; Get-PrintStackInventory' -ForegroundColor DarkGray
    Write-Host '  And remove them with the module:' -ForegroundColor Cyan
    Write-Host '    Restart-PrintStack -Force -NoScanners' -ForegroundColor DarkGray
    Write-Host '  Or revert with this script:' -ForegroundColor Cyan
    Write-Host '    pwsh -NoProfile -File .\Tests\Add-TestPrinters.ps1 -Cleanup' -ForegroundColor DarkGray
    Write-Host ''
}
