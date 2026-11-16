# PowerShell Profile — Context

## Purpose

This repo is the current-user PowerShell 7 profile. The primary goal is to keep
shell startup fast; everything here is organized so that nothing runs eagerly
unless it must.

- Shell: PowerShell 7 (pwsh)
- Entry point: `Microsoft.Powershell_profile.ps1` ("the loader")
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
| `Get-CustomModule` | Lists the profile's custom modules with their version, description, and exported commands. |
| `Get-NetworkDiagnostics` | One-shot site network triage: adapter state, DNS resolution, reachability, egress, and ticket export. |
| `Get-PrinterInfo` | SNMP query of a printer/MFP: model, serial, page count, status, supply levels. No external tools. |
| `Invoke-Elevation` | Relaunches the current Windows Terminal session elevated or unelevated (`-Unelevate`/`u`, via the UAC linked or desktop-shell filtered token, with a `runas /trustlevel` fallback), reusing the same profile and working directory; `Invoke-Unelevation`/`uel` is the unelevated counterpart. Falls back to a new PowerShell host outside Windows Terminal. |
| `New-CliCommandShortcut` | Creates a Desktop (or specified) `.lnk` that re-runs a recent non-destructive command from PSReadLine history. Defaults to the command before the invocation itself; `-Skip`/`-Scan`/`-Index` select an entry, `-List` inspects history, and a deny-list skips state-changing verbs and native tools (`-IncludeDestructive` opts out). |
| `New-QRCode` | Renders text, URLs, and preset payloads (Wi-Fi, vCard, email, SMS, phone, geo) to a QR code in the console, a PNG/SVG file, or via the `Show-QRCode` WinForms dialog (loaded only when opened). CSV batch mode; the QRCoder library is downloaded on demand (`Install-QRCoder`) into `%LOCALAPPDATA%\New-QRCode\lib` and is never tracked. |
| `New-ScanShare` | One-step SMB scan-to-folder setup (hardened local account locked to SMB network logon, folder, NTFS lockdown, `Everyone: Full Control` share, firewall), verified with a listener check and a credentialed write probe. Ships an optional `Show-ScanShare` WinForms dialog that drives it (loaded only when opened). Runs on PS 7 and Windows PowerShell 5.1; Windows 10/11/Server 2016+ (64-bit). |
| `Optimize-PSX` | Converts PS1/PS2, Saturn, and Dreamcast disc images to CHD, extracting archives first; targets folders, archives, or single images. |
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

Measured in November 2026: real console, warm disk cache, 65-entry `$env:PATH`.

| Stage          | ~ms | Notes |
|----------------|-----|-------|
| Config         | 245 | PSReadLine import and options ~145, command cache read ~30 |
| oh-my-posh     | 200 | ~95 of it is one synchronous `oh-my-posh print secondary` spawn |
| Aliases        | 42  | eager dynamic aliases only |
| zoxide         | 14  | |
| PSModulePath   | 14  | |
| **TOTAL**      | ~515 | in-profile, as reported by `$env:PROFILE_TRACE` |

The stage trace stops before the first prompt is drawn, so it is not what a
person waits for. End to end:

| Launch | ~ms |
|--------|-----|
| `pwsh -NoProfile -Command exit` (engine floor) | 285 |
| `pwsh -Command exit` (what `Measure-ProfileLoad` reports) | 890 |
| Interactive, to a usable prompt, `-NoProfile` | 480 |
| Interactive, to a usable prompt, in `$HOME` | 1,050 |
| Interactive, to a usable prompt, inside a git repo | 1,250 |

The first prompt render is one more `oh-my-posh` spawn: ~140 ms, or ~325 ms where
the git segment has a repository to inspect.

## Design notes

- **Approved verbs only.** Exported commands use PowerShell-approved verbs from
  `Get-Verb` (never invented verbs). See the rule in `AGENTS.md`.
- **Shells do not share one `$env:PATH`.** A process keeps the PATH its parent
  had when it started, so Windows Terminal, VS Code, and agent CLIs each hand
  pwsh a different snapshot; some of them run `pwsh -Command …` without
  `-NoProfile` for every command. Anything the profile derives from PATH is
  therefore recomputed differently by alternating shells. Startup state keyed on
  PATH must be cheap to rebuild, and persistent state must not be rewritten just
  because two shells disagree. Both rules below exist because breaking them cost
  3.6 s on every launch that followed a shell with a different PATH.
- **The `EDITOR` write is guarded by "still resolves", not "is equal".** A
  User/Machine-scope `[Environment]::SetEnvironmentVariable` broadcasts
  `WM_SETTINGCHANGE` to every top-level window and blocks on each: 2.5–7 s per
  write. A shell that finds the editor on PATH picks its bare name; one that
  reaches it through the install-path fallback picks the full path. Comparing the
  persisted value with the session's pick makes those two overwrite each other
  forever. `Config/Settings.ps1` writes only when the persisted value is unset or
  no longer resolves. Consequence: the persisted value does not follow a newly
  installed higher-priority editor (`$env:EDITOR` in each session still does). To
  re-pick it, run `[Environment]::SetEnvironmentVariable('EDITOR', $null, 'User')`
  and open a shell.
- **Command lookups go through `Resolve-CachedCommand`.** A `Get-Command` miss
  costs ~105 ms (PATH scan plus module auto-discovery). `Config/CommandCache.ps1`
  persists hits **and** misses to
  `$env:LOCALAPPDATA\PowerShell\ProfileCache\pwsh-env.cache.ps1` (not `$env:TEMP`,
  since every shell dot-sources it), keyed on a SHA-256 of `$env:PATH` and
  `$env:PATHEXT`. Returns the absolute path, or `$null` on miss. Use it instead of
  `Get-Command` anywhere in the startup path. Only the names listed in
  `$script:PwshEnvCommandNames` are resolved; any other name returns `$null`.
- **Cache regeneration is on the hot path.** The cache is a single slot, so shells
  with different PATH snapshots evict each other. `Find-PathApplication` rebuilds
  it with one directory listing per PATH entry (~25 ms, ~100 ms in a cold shell)
  and matches `Get-Command`'s precedence: PATH order, then `$env:PATHEXT` order,
  then the bare name. Never route regeneration back through `Get-Command` (~1.1 s
  for the 13 names).
- **PSReadLine prediction needs a real VT console.** `Set-PSReadLineOption` drops
  the prediction keys when output is redirected and is isolated in its own
  `try/catch`, so a redirected host cannot abort `Settings.ps1`.
- **History secret filter.** `AddToHistoryHandler` returns `$false` for commands
  that look like they carry a secret: `passw`/`secret`/`apikey`/`connectionstring`,
  key/token flags and assignments, `net user <name> <pw>`, `-AsPlainText`, HTTP
  `Bearer`/`Authorization:` headers, and `New-ScanShare … -w`. The pattern lives in
  `Config/Settings.ps1`.
- **Terminal-Icons is not imported** — measurable startup cost for non-essential
  icons. Opt in with `Import-Module Terminal-Icons`.

## Tooling

- `Measure-ProfileLoad [-Iterations N] [-Trace]` — cold-start timing (baseline vs
  profile) with optional per-stage breakdown.
- `$env:PROFILE_TRACE=1` before launching `pwsh` writes a per-stage breakdown to
  `$env:TEMP\pwsh-profile-trace.log`.
- **Both tools have two blind spots.** They launch `pwsh -Command exit`, which
  never draws a prompt, and they launch the same environment repeatedly (with a
  discarded warm-up), which hides any cost paid only on the first launch after a
  shell with a different PATH. Check that case explicitly; `Config` should stay
  near 350 ms:

  ```powershell
  $p = $env:PATH; $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
  pwsh -NoLogo -Command exit; $env:PATH = $p
  $env:PROFILE_TRACE = 1; pwsh -NoLogo -Command exit; $env:PROFILE_TRACE = $null
  ```

- `Modules/New-ScanShare/Deploy/New-ScanSharePackage.ps1` builds
  `Dist\New-ScanShare-Portable-<version>.zip`: a double-click bundle whose
  `Install-ScanShare.cmd` installs `New-ScanShare`/`Show-ScanShare` per-user for
  both PowerShell 7 and Windows PowerShell 5.1 and drops a Desktop shortcut.
  `Dist/` is git-ignored; the `Deploy/` sources are tracked.

## Remaining work

- The profile optimizations (dynamic POSH_SESSION_ID per shell, theme/binary timestamp cache invalidation, OMP_ASYNC trampoline support, and tightened history filter regex) are resolved. Module standardization work is tracked in `ROADMAP.md` rather than here.
- oh-my-posh is now the largest remaining cost (~200 ms init plus the first
  prompt). Its generated init runs `oh-my-posh print secondary` synchronously on
  every launch (~95 ms) for a value that only changes with the theme or the
  binary, which the `omp.cache.ps1` key already tracks.
- Non-interactive hosts (`pwsh -Command …` from agent CLIs and scripts) pay the
  full profile, prompt init included, for a prompt they never draw.

## Environment notes

- **`code <target>` opening extra windows** is VS Code behavior, not the profile:
  set `window.restoreWindows: "none"`, `window.openFoldersInNewWindow: "off"`, and
  `window.openFilesInNewWindow: "off"` in `Code - Insiders\User\settings.json`.

## Authorship

Authored by **Timothy W. Brown** with the assistance of large language models,
including Anthropic Claude, Google Gemini, and DeepSeek. AI assistance covers
implementation, review, and documentation; the author reviews and owns every
change.

## License

Released under the [Apache License, Version 2.0](LICENSE). The grant is
perpetual, worldwide, royalty-free, and irrevocable: individuals and
organizations may use, modify, and redistribute the code, provided the
copyright and attribution notices are retained (see `NOTICE`). Copyright
remains with the author.

## Housekeeping

- `.gitignore` is deny-all/whitelist: `AGENTS.md`, `CONTEXT.md`, `ROADMAP.md`, and
  each tracked module need an explicit `!` entry (use `/**` so subfolders are included).
