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
- **No comments unless asked.** Default to clean code; comment only for non-obvious rationale.

## 5. Reference contrasts

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
