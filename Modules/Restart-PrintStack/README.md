# Restart-PrintStack

Returns the Windows printing system to its default state.

A technician's laptop collects a print queue, a driver and a TCP/IP port for every
site it has ever visited. Windows never cleans any of it up. This module removes
that accumulation while keeping the printers Windows expects to have - Microsoft
Print to PDF, the XPS writer, OneNote, Fax, Adobe - and it shows you exactly what
it is about to do before it does it.

## Commands

| Command | Purpose |
| --- | --- |
| `Restart-PrintStack` | Plan, review and remove. Requires elevation (except `-WhatIf`). |
| `Get-PrintStackInventory` | Read-only view of the same plan. Changes nothing. |

## Quick start

```powershell
# What is on this machine, and what would be removed?
Get-PrintStackInventory

# Preview without elevation, without touching anything.
Restart-PrintStack -WhatIf

# The real thing: interactive review, then removal.
Restart-PrintStack
```

## What gets removed

By default:

- Print queues that do not match a keep rule
- Printer ports left behind with no queue referencing them
- Imaging devices (scanners) discovered over the network - WSD and eSCL entries

By default **not**:

- The built-in virtual printers (PDF, XPS, OneNote, Fax, Adobe)
- `\\server\queue` network connections - Group Policy recreates them, so removing
  them breaks printing for a few minutes and achieves nothing (`-IncludeNetwork`
  to override)
- RDP-redirected session printers - the remote session owns them
  (`-IncludeRedirected`)
- USB-attached scanners - they re-enumerate the instant they are reconnected
  (`-IncludeLocalScanners`)
- Ports Windows needs: `LPT*`, `COM*`, `FILE:`, `nul:`, `PORTPROMPT:`,
  `SHRFAX:`, `XPSPort:`
- Print drivers. Nothing removes drivers in this version; the inventory reports
  which ones are unused so you can decide for yourself.

## The review screen

The default run is interactive. The whole print state appears numbered, with a
verdict and a reason for every row, and you amend it before anything is deleted:

```
    #  Action  Type     Name                    Port / Address   Reason
  ---------------------------------------------------------------------------------
    1  KEEP    Printer  Microsoft Print to PDF  PORTPROMPT:      [default] Allow-list name...
    2  REMOVE  Printer  HP LaserJet 400 (Acme)  192.168.14.50    Not protected by any keep rule.
    3  REMOVE  Port     192.168.14.50           192.168.14.50    Orphaned - no printer uses it.

  [Enter] proceed   [k 3,5-7] keep this run   [p 4] pin permanently   [r 4] remove
  [a] keep all      [n] cancel                [?] help
```

Two commands that look similar and are not:

- **`k`** keeps a row for **this run only**. Nothing is written to disk.
- **`p`** pins a row: kept now, and kept by **every future run**, because the name
  is appended to your allow-list file.

The distinction is the point. If every "don't delete that one" were persisted,
six months of site visits would leave an allow-list that protects everything and
a sweep that cleans nothing.

Pins are written only after you confirm. Cancelling the review leaves the
allow-list exactly as it was.

## The allow-list

`%APPDATA%\Restart-PrintStack\allowlist.json`, created on first run. Plain JSON,
meant to be hand-edited:

```json
{
  "version": 1,
  "keepPrinters": ["Brother HL-L2340D*", "Shop Floor Label Printer"],
  "keepPorts": ["192.168.10.*"],
  "keepDrivers": [],
  "removePrinters": ["Adobe PDF"]
}
```

Every entry is a wildcard pattern, matched case-insensitively.
`removePrinters` outranks every keep rule including the built-in defaults, which
is how you get rid of something like a stale `Adobe PDF` queue without editing
the module.

The file is updated atomically and additively: unknown keys and your own comments
are read back and rewritten intact.

## Safety

- **Elevation required.** The spooler rejects deletions otherwise. `-WhatIf`
  is exempt, because previewing the plan changes nothing and you shouldn't need
  an admin window to find out whether you need one.
- **Backup first.** A JSON snapshot of every queue, port and device - names,
  drivers, IP addresses - is written to `%TEMP%\Restart-PrintStack_<timestamp>\`
  before anything is deleted. Enough to recreate a queue by hand without phoning
  the customer for the printer's IP again. `-NoBackup` to skip.
- **Ports are never orphaned.** A port in use by a surviving queue is never
  removed, and keeping a queue in the review screen automatically re-protects its
  port. Printer pooling is handled: a pooled `PortName` lists several ports and
  all of them are treated as referenced.
- **The default printer is preserved.** If the sweep removes the current default,
  a survivor is nominated - Microsoft Print to PDF by preference, since it cannot
  accidentally print to someone else's hardware. `-SetDefault` to choose.
- **Nothing aborts the run.** A queue that refuses to delete is reported in the
  summary; the other twenty still get cleaned.

## Parameters worth knowing

| Parameter | Effect |
| --- | --- |
| `-Keep 'HP*'` | Protect for this run only. |
| `-Remove 'Adobe PDF'` | Force removal, overriding every keep rule. |
| `-Pin 'Shop Printer'` | Write straight to the allow-list, no review screen. |
| `-NoPortSweep` | Leave all ports alone. |
| `-NoScanners` | Leave all imaging devices alone. |
| `-SetDefault 'Microsoft Print to PDF'` | Nominate the default afterwards. |
| `-NonInteractive` | Single yes/no prompt instead of the review screen. |
| `-Force` | No prompting at all. For scripted builds. |
| `-PassThru` | Emit step-result objects as well as the summary. |

## Examples

```powershell
# Preview, keeping the HP queues and also dropping server connections.
Restart-PrintStack -WhatIf -Keep 'HP LaserJet*' -IncludeNetwork

# Unattended: queues and ports only, no prompts.
Restart-PrintStack -Force -NoScanners

# Which ports are orphaned?
Get-PrintStackInventory -Type Port -AsObject | Where-Object Action -eq 'Remove'

# Pin the shop printer permanently, then clean up.
Restart-PrintStack -Pin 'Shop Floor Label Printer'
```

## Recovering something you didn't mean to delete

Open the snapshot:

```powershell
Get-ChildItem $env:TEMP -Filter 'Restart-PrintStack_*' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
```

`print-inventory.json` inside it has the name, driver, port and host address of
everything that was there. Recreate with `Add-PrinterPort` and `Add-Printer`.

## Tests

```powershell
pwsh -NoProfile -File .\Tests\Plan.Probe.ps1
```

48 read-only checks covering the selection parser, pattern matching, port
splitting, allow-list merge behaviour and the planner's invariants - including
the one that matters most, that no port in use by a surviving printer is ever
planned for removal. The probe deletes nothing, touches no service, and exercises
the allow-list through a temporary path so your real one is never modified.

## Implementation notes

Every Windows API here has a version where it is missing or refuses, so each
operation has a fallback chain: `PrintManagement` cmdlets → CIM → `printui.dll` /
`pnputil`. Scanners are PnP devices in the `Image` class rather than spooler
objects, so they go through `Remove-PnpDevice`; pnputil's exit code 3010 means
"removed, reboot to finish" and is treated as success.

Removal order is load-bearing: jobs, then queues, then ports, then scanners. The
spooler will not release a port while a queue still references it. A port that
was freed moments ago can still report as in use because the spooler caches the
handle, so failed ports are collected and retried once behind a single spooler
restart rather than bouncing the service per port.
