# AGENTS.md

> **Core directive:** Code explains *how*; comments explain *why*. If code can be refactored to be self-explanatory, refactor it — do not comment it.

Personal PowerShell 7 profile. For architecture, load order, the load-time budget, and known gotchas, read `CONTEXT.md`.

---

## 1. Comment principles (intent over mechanics)

- **Document rationale, not mechanics.** Explain business constraints, algorithm choices, trade-offs, and non-obvious domain logic. Assume the reader knows PowerShell.
- **Prefer self-documenting code.** Descriptive names, focused helpers, and named constants before adding a comment.
- **No syntax echoes.** Never restate what a line literally does.
- **Highlight gotchas.** Third-party quirks, PS-version/platform workarounds, performance trade-offs, and why a value must not change.
- **Action tags:** `TODO` / `FIXME` / `HACK`. A ticket id is optional here (no issue tracker) — add one only when one exists.

## 2. Maintenance & hygiene

- **No commented-out code.** Rely on Git history instead.
- **Update comments with the code**, in the same commit. Stale comments are worse than none.
- **Public-API help.** Use PowerShell comment-based help (`<# .SYNOPSIS #>`) for exported functions/modules — parameters, inputs/outputs, side effects, and error conditions.

## 3. LLM / AI generation guardrails

- **No change narration.** Keep commit messages/changelogs out of source comments (e.g. no "// Added by AI" or "// Updated for v2").
- **No conversational filler.** No step-by-step narration or token-filler.
- **No placeholder stubs.** Never leave `TODO: implement this`; write it or throw.
- **Validate inferred contracts.** Cross-check generated help against the actual parameter types and behavior.
- **Preserve existing rationale.** During refactors, keep human-authored warnings, edge-case rationale, and domain notes unless the requirement is actually gone.

## 4. Repo-specific rules

- **`.gitignore` is deny-all/whitelist.** New files are ignored by default — add an explicit `!` entry before committing anything new.
- **Module autoload.** Export via `FunctionsToExport`/`AliasesToExport` in the `.psd1` instead of eager dot-sourcing (keeps startup fast).
- **Comment only for non-obvious rationale.** No explanatory or narrative comments.

## 5. Conventions

- **Target: PowerShell 7 only.** Modern syntax (`??`, `?.`, ternary) is fine.
  - *Exception:* `New-ScanShare` must also run on Windows PowerShell 5.1 (it is copied onto client PCs). No `??`, `?.`, `?:`, `&&`/`||` or other 7-only syntax there; run its tests under both `pwsh` and `powershell.exe -ExecutionPolicy Bypass`. Beware `$var?.Prop`: both versions parse it as a variable literally named `var?`.
- **Cmdlet verbs:** every exported command must use a PowerShell-approved verb (from `Get-Verb`). Never invent a verb (`Do-`, `Run-`, `Load-`, …); choose the correct approved form (`Get-`, `Set-`, `New-`, `Test-`, `Invoke-`, …) so autoload, `Get-Command` discovery, and `-WhatIf`/`-Confirm` support stay consistent. Aliases are exempt.
- **Errors:** use `$PSCmdlet.ThrowTerminatingError()` with an `ErrorRecord` instead of a raw `throw`. For missing elevation, warn and tell the user how to relaunch rather than throwing.
- **Commits:** conventional commits scoped to the module or component (e.g. `feat(Test-UdpPort): …`, `fix(Settings): …`, `perf(profile): …`). Commits must be common-sense and granular:
  - *Atomic and focused:* one logical feature, fix, or optimization per commit. Never bundle unrelated modules, config changes, or refactors into a single catch-all commit.
  - *Common-sense boundaries:* keep a module's implementation, manifest, and its corresponding `.gitignore` whitelist entry together in the same commit so each commit represents a functional, valid state without excessive micro-fragmentation.
- **Caches:** `omp.cache.ps1`, `zoxide.cache.ps1`, and `pwsh-env.cache.ps1` live in `$env:TEMP`. Delete them to force a rebuild after changing the theme, the tools, or `$env:PATH`.

## 6. Verification

- **Parse:** `$t = $e = $null; [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e); $e`
- **Load:** `Import-Module .\Modules\<Name>\<Name>.psd1 -Force`
- **Startup cost** (after touching the loader or `Config/`): `Measure-ProfileLoad`, or `$env:PROFILE_TRACE=1; pwsh -NoLogo -Command exit` and read `$env:TEMP\pwsh-profile-trace.log`.
- **Restart-PrintStack:** `pwsh -NoProfile -File .\Modules\Restart-PrintStack\Tests\Plan.Probe.ps1` (read-only).

## 7. Reference contrasts

### Narration vs. rationale

```powershell
# BAD: echoes syntax mechanics
# Filter to active users
$active = $users | Where-Object Status -eq 'ACTIVE'

# GOOD: self-documenting (no comment needed)
$activeUsers = $users | Where-Object { Test-UserActive $_ }
```

### Workarounds vs. noise

```powershell
# BAD: changelog/author commentary inside source
# Fixed null pointer bug found during testing by Alex
if ($config.Timeout) { ... }

# GOOD: documents an external constraint
# PSReadLine prediction needs a real VT console; drop it when output is redirected
if (-not $Host.UI.SupportsVirtualTerminal) { ... }
```

### Action tags

```powershell
# BAD: ambiguous
# TODO: fix this later

# GOOD: specific (ticket id optional in this repo)
# FIXME: history filter drops 'winget search token' (substring match)
```
