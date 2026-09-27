# PowerShell Profile — Context

## Purpose

This repo is the current-user PowerShell 7 profile. The primary goal is to keep
shell startup fast; everything here is organized so that nothing runs eagerly
unless it must.

- Shell: PowerShell 7 (pwsh)
- Entry point: `Microsoft.PowerShell_profile.ps1` ("the loader")
- OS: Windows 11

Agent rules and conventions live in `AGENTS.md`; planned modules in `ROADMAP.md`.

## Layout

```
Microsoft.PowerShell_profile.ps1   Loader (orchestrates everything below)
Config/
  CommandCache.ps1                 PATH-keyed command-resolution cache
  Settings.ps1                     PSReadLine, editor detection, completers
  Aliases.ps1                      Dynamic / built-in-conflicting aliases ONLY
Modules/                           Self-contained modules (see below)
Themes/                            oh-my-posh theme JSON
```

### Load order (what actually happens at startup)

1. `Config/CommandCache.ps1` — defines `Resolve-CachedCommand`.
2. `Config/Settings.ps1` — PSReadLine options, editor detection, argument completers.
3. `$env:PSModulePath` — prepends `Modules/` so custom modules autoload.
4. `Config/Aliases.ps1` — the small set of aliases that must be eager.
5. oh-my-posh prompt init (cached).
6. zoxide init (cached).

No module is imported at startup. Each manifest lists its commands in
`FunctionsToExport` / `AliasesToExport`, so PowerShell loads the module the first
time one of them is used.

## Modules

| Module | Purpose |
|--------|---------|
| `Compress-Video` | Batch FFmpeg compression with GPU acceleration, resume/skip detection, and throttled parallelism. |
| `Export-SiteReport` | Aggregates machine specs, print stack inventory, network printers, and network triage into a single job ticket document. |
| `Find-NetworkDevice` | Subnet sweep discovery: MAC/OUI resolution, printer port probes, and pipeline to Get-PrinterInfo. |
| `Format-UsbDrive` | Formats removable USB drives (<70 GB) to FAT32/exFAT/NTFS, with MFD firmware-upgrade profiles. |
| `Get-NetworkDiagnostics` | One-shot site network triage: adapter state, DNS resolution, reachability, egress, and ticket export. |
| `Get-PrinterInfo` | SNMP query of a printer/MFP: model, serial, page count, status, supply levels. No external tools. |
| `New-ScanShare` | One-step SMB scan-to-folder setup (account, folder, ACLs, share, firewall), verified with Test-FileShare. |
| `Optimize-PSX` | Extracts disc-image archives and compresses PS1/PS2, Saturn, and Dreamcast images to CHD. |
| `Optimize-VMX` | Tunes VMware `.vmx` files for network stability and legacy-OS compatibility. |
| `ProfileTools` | Personal toolbox: functions, utilities, and static aliases, including `Measure-ProfileLoad`. |
| `Rename-MediaFile` | Renames media, subtitles, and folders to Plex/Jellyfin standards. |
| `Restart-NetworkStack` | Resets the Windows network stack (DNS, DHCP, Winsock, TCP/IP, firewall, proxy, and more). |
| `Restart-PrintStack` | Removes accumulated print queues, orphaned ports, and stale scanners. See its `README.md`. |
| `Test-FileShare` | SMB and FTP/SFTP/FTPS connectivity checks for MFP scan-to-folder troubleshooting. |
| `Test-SmtpRelay` | SMTP connectivity, banner, and alias checks for common mail relays. |
| `Test-UdpPort` | UDP connectivity probes with built-in game-server query packets. |

`Modules/` also contains third-party modules that are **not** tracked and must not
be edited as repo code: `7Zip4Powershell` and `Microsoft.PowerToys.Configure`.

## Load-time budget

Measured with `Measure-ProfileLoad` (10 cold starts, real console) in August 2026.
Engine baseline (`-NoProfile`) is ~280 ms on this machine.

| Stage          | ~ms | Notes |
|----------------|-----|-------|
| Config         | 240 | PSReadLine ~160, editor cache, completers |
| oh-my-posh     | 188 | prompt init |
| Aliases        | 37  | eager dynamic aliases only |
| zoxide         | 16  | |
| PSModulePath   | 14  | |
| **TOTAL**      | ~500 | in-profile; +~280 engine = ~780 total |

## Design notes

- **The `EDITOR` write is guarded.** A User/Machine-scope
  `[Environment]::SetEnvironmentVariable` broadcasts `WM_SETTINGCHANGE` to every
  top-level window and blocks on each — it once cost ~7 s per launch.
  `Config/Settings.ps1` only writes when the stored value actually differs. Do not
  make that write unconditional.
- **Command lookups go through `Resolve-CachedCommand`.** A `Get-Command` miss
  scans every `$env:PATH` entry (~105 ms each). `Config/CommandCache.ps1` persists
  hits **and** misses to `$env:TEMP\pwsh-env.cache.ps1`, keyed on a SHA-256 of
  `$env:PATH`, and regenerates only when `$env:PATH` changes. Returns the absolute
  path, or `$null` on miss. Use it instead of `Get-Command` anywhere in the startup
  path.
- **PSReadLine prediction needs a real VT console.** `Set-PSReadLineOption` drops
  the prediction keys when output is redirected and is isolated in its own
  `try/catch`, so a redirected host cannot abort `Settings.ps1`.
- **History secret filter.** `AddToHistoryHandler` returns `$false` for commands
  matching `password|secret|key|apikey|token|connectionstring`.
- **Terminal-Icons is not imported** — measurable startup cost for non-essential
  icons. Opt in with `Import-Module Terminal-Icons`.

## Tooling

- `Measure-ProfileLoad [-Iterations N] [-Trace]` — cold-start timing (baseline vs
  profile) with optional per-stage breakdown.
- `$env:PROFILE_TRACE=1` before launching `pwsh` writes a per-stage breakdown to
  `$env:TEMP\pwsh-profile-trace.log`.

## Remaining work

- None currently pending. Profile optimizations (dynamic POSH_SESSION_ID per shell, theme/binary timestamp cache invalidation, OMP_ASYNC trampoline support, and tightened history filter regex) are resolved.

## Environment notes

- **`code <target>` opening extra windows** is VS Code behavior, not the profile:
  set `window.restoreWindows: "none"`, `window.openFoldersInNewWindow: "off"`, and
  `window.openFilesInNewWindow: "off"` in `Code - Insiders\User\settings.json`.

## Housekeeping

- `.gitignore` is deny-all/whitelist: `AGENTS.md`, `CONTEXT.md`, `ROADMAP.md`, and
  each tracked module need an explicit `!` entry (use `/**` so subfolders are included).
