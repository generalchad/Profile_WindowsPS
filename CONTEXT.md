# PowerShell Profile — Context & Optimization Notes

## Purpose

This repo is the current-user PowerShell 7 profile. The primary goal is to keep
shell startup fast; everything here is organized so that nothing runs eagerly
unless it must.

- Shell: PowerShell 7 (pwsh)
- Entry point: `Microsoft.PowerShell_profile.ps1` ("the loader")
- OS: Windows 11

## Layout

```
Microsoft.PowerShell_profile.ps1   Loader (orchestrates everything below)
Config/
  CommandCache.ps1                 PATH-keyed command-resolution cache
  Settings.ps1                     PSReadLine, editor detection, completers
  Aliases.ps1                      Dynamic / built-in-conflicting aliases ONLY
Modules/
  ProfileTools/                    Personal toolbox (functions + static aliases),
                                   autoloaded on first use via the manifest
  <other self-contained modules>   Compress-Video, Optimize-PSX, Restart-*, etc.
Themes/                            oh-my-posh theme JSON
```

### Load order (what actually happens at startup)

1. `Config/CommandCache.ps1` — defines `Resolve-CachedCommand`.
2. `Config/Settings.ps1` — PSReadLine options, editor detection, argument completers.
3. `Config/Aliases.ps1` — the small set of aliases that must be eager.
4. `$env:PSModulePath` — prepends `Modules/` so custom modules autoload.
5. oh-my-posh prompt init (cached).
6. zoxide init (cached).

`Modules/ProfileTools` is **not** imported at startup — its functions and static
aliases are listed in `ProfileTools.psd1` (`FunctionsToExport` / `AliasesToExport`),
so PowerShell loads the module the first time any of them is used.

## Load-time budget

Measured with `Measure-ProfileLoad` (10 cold starts, real console). Engine
baseline (`-NoProfile`) is ~280 ms on this machine.

| Milestone                     | Total | Profile overhead |
|-------------------------------|-------|------------------|
| Original (before any changes) | ~8.5s | ~8.2s |
| After HKCU write fix          | ~1.64s | ~1.36s |
| After command cache           | ~0.93s | ~0.65s |
| After ProfileTools module     | ~0.85s | ~0.56s |

Per-stage breakdown (after all current fixes):

| Stage          | ~ms | Notes |
|----------------|-----|-------|
| Config         | 240 | PSReadLine ~160, editor cache, completers |
| oh-my-posh     | 188 | prompt init |
| Aliases        | 37  | eager dynamic aliases only |
| zoxide         | 16  | |
| PSModulePath   | 14  | |
| **TOTAL**      | ~500 | in-profile; +~280 engine = ~780 total |

## Root causes found & fixed

1. **Per-shell registry write (~7.1s).** `Config/Settings.ps1` called
   `[Environment]::SetEnvironmentVariable('EDITOR', …, 'User')` unconditionally.
   A User/Machine-scope write broadcasts `WM_SETTINGCHANGE` to every top-level
   window and blocks on each. Now guarded: it only writes when the stored value
   actually differs (a ~25 ms read replaces a ~7 s write). This was the dominant
   cost and the reason startup felt "~3s" (variable, depending on open windows).

2. **`Get-Command` misses (~105 ms each, ~8 of them).** A single `Get-Command`
   miss scans every `$env:PATH` entry. The profile probed ~8 commands (most of
   which miss on this machine) on every launch — ~800 ms total. Replaced with
   `Resolve-CachedCommand` (see below).

3. **Eager dot-sourcing of Functions/Utilities (~85 ms + static aliases).**
   All loose scripts were dot-sourced at startup. Moved into the autoloading
   `ProfileTools` module, so they cost ~0 until first use.

4. **oh-my-posh init (~188 ms, remaining).** The prompt init is already cached,
   but running the init script still costs ~188 ms. See "Remaining work".

## Command-resolution cache

`Config/CommandCache.ps1` persists resolved command paths (hits **and** misses)
to `$env:TEMP\pwsh-env.cache.ps1`, keyed on a SHA-256 of `$env:PATH`. It
regenerates only when `$env:PATH` changes (e.g. after installing a tool), so a
miss costs ~0 on subsequent launches instead of ~105 ms.

- `Resolve-CachedCommand <name>` returns the absolute path, or `$null` on miss.
- To force a rebuild: `Remove-Item $env:TEMP\pwsh-env.cache.ps1`.

## Tooling

- `Measure-ProfileLoad [-Iterations N] [-Trace]` — cold-start timing (baseline vs
  profile) with optional per-stage breakdown.
- `$env:PROFILE_TRACE=1` before launching `pwsh` writes a per-stage breakdown to
  `$env:TEMP\pwsh-profile-trace.log`.

## Correctness bugs fixed along the way

- **PSReadLine aborted Settings.ps1** in redirected hosts (prediction requires a
  real VT console). `Set-PSReadLineOption` now drops prediction keys when output
  is redirected and is isolated in its own `try/catch`.
- **History secret filter never worked** — the `AddToHistoryHandler` returned
  `$null` in both branches (defaulting to "keep"). Now returns `$true`/`$false`
  against a regex (`password|secret|key|apikey|token|connectionstring`).
- **Duplicate `Invoke-Explorer`** — was defined in both `Core.ps1` and
  `FileSystem.ps1`. The `Core.ps1` copy was removed.
- **Dangling aliases** — `resetip`/`renewip`/`updateip` pointed to
  `Update-IPConfig`, which no longer exists. Removed.

## `code <target>` opens extra windows

Not a profile bug. `code` resolves to a single `code-insiders.cmd` (one process).
The extra windows come from two VS Code defaults:

- `window.restoreWindows` (default `all`) — a cold `code <target>` also restores
  the previous session.
- `window.openFoldersInNewWindow` (default `default`) — `code <folder>` opens a
  second window when one is already open.

Fixed by setting, in `Code - Insiders\User\settings.json` (outside this repo):

```json
"window.restoreWindows": "none",
"window.openFoldersInNewWindow": "off",
"window.openFilesInNewWindow": "off"
```

## Remaining work

- **oh-my-posh async init (~188 ms).** oh-my-posh 30.x init script supports a
  trampoline (`$global:_ompAsyncInit`) that defers the full init until after the
  first prompt renders. Worth evaluating; gate behind a flag.
- **`POSH_SESSION_ID` is frozen in `omp.cache.ps1`.** The cache bakes in a single
  session ID, so every shell shares one session (exit-code/timing cross-talk).
  Should be regenerated per session, and the cache invalidated when the theme or
  the `oh-my-posh --version` changes.
- **History-filter regex** is substring-based; it can drop innocent commands like
  `winget search token`. Consider tightening if that becomes annoying.

## Housekeeping

- `Modules/7Zip4Powershell` had 4 versions installed (~28 MB); pruned to `2.12.0`.
- This `CONTEXT.md` is tracked via an explicit `!CONTEXT.md` entry in `.gitignore`
  (the repo uses a deny-all/whitelist ignore policy).
