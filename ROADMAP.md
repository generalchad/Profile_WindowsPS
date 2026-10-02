# Roadmap

Planned modules and upcoming architecture ideas not yet built. When proposing
or designing new modules, adhere to the architectural guidelines in `AGENTS.md`
and `CONTEXT.md`: self-contained (private helpers copied, not shared),
PowerShell 7 native, structured object output, lazy-loading via module autoload,
and explicit whitelist entries in `.gitignore`.

## Feature roadmap

- **`New-QRCode` - split `Text / URL` into `Text` and `URL`.** Both keep the same
  field size. In `URL`, more than one URL can be pasted (one per line) and the
  dialog generates a code for each, with small `<` / `>` buttons beneath the
  preview to step through them.

### FTP/SFTP scan destinations (planned)

Let a copier scan to this PC over FTP (IIS) or SFTP (OpenSSH) alongside the
existing SMB-only `New-ScanShare`. Not implemented yet; the design decisions are
locked so the eventual work does not reopen them.

- **Shape: new sibling modules, not a `-Protocol` parameter on
  `New-ScanShare`.** Planned `New-FtpScanShare` and `New-SftpScanShare`, each
  self-contained (private helpers copied, not shared). `New-ScanShare` stays
  SMB-only, 5.1-compatible, and portable; its tested SMB path and the `Deploy`
  bundle are not touched.
- **Protocols: plain FTP via IIS and SFTP via OpenSSH.** FTPS (explicit/implicit
  TLS) is deferred until a cert story is worthwhile.
- **Hardening differs per protocol.** The current SMB-only hardening (deny
  interactive/RDP/batch/service; allow SMB network logon) is wrong for both:
  IIS FTP does not authenticate over SMB, and OpenSSH SFTP needs a chroot split.
  Each module gets its own logon-rights model.
- **FTP (IIS) notes.** Prereqs `IIS-FTPServer`, `IIS-FTPExtensibility`, and
  `Web-Server` (elevated, may need a reboot). Configure through
  `Microsoft.Web.Administration.ServerManager` - it works in both PowerShell 7
  and 5.1, whereas `WebAdministration` is 5.1-only. Basic auth for a dedicated
  local account, anonymous disabled, a passive data-channel port range with
  matching inbound firewall rules, and the folder/NTFS lockdown pattern reused
  from `New-ScanShare`.
- **SFTP (OpenSSH) notes.** Prereq `OpenSSH.Server~~~~0.0.1.0`; generate host
  keys (`ssh-keygen -A`) and set `sshd` to Automatic. A `Match User` block uses
  `ForceCommand internal-sftp` with `ChrootDirectory`, password auth, and
  forwarding disabled. The chroot directory must be admin-owned and non-writable
  by the account, so the layout is two-level (admin-owned root, writable child)
  and therefore conflicts with `New-ScanShare`'s "Modify on the destination
  root". Validate with `sshd -t`, restart `sshd`, open TCP 22.
- **GUI.** `Show-ScanShare` gains a protocol selector that dispatches only when
  the backing command exists; SMB stays the default.
- **`Test-FileShare` extension (separate, lower risk).** Grow it from a banner
  grab to credentialed checks: FTP login, `PWD`/list, and a write probe; an SFTP
  probe needs an SSH library (SSH.NET, downloaded on demand like `New-QRCode`'s
  QRCoder) or key-based `sftp`. Ports 21/22/990 are already probed.

## Standardization backlog (module review, September 2026)

A full audit of the custom modules against `AGENTS.md` / `CONTEXT.md` produced
the items below. The correctness pass (Phase 1) is complete; the rest is
deferred and listed in rough priority order.

### Decisions locked in

- **PS version floor:** every PowerShell 7-only module targets **7.2**. The
  current `7.6` floors in `Optimize-PSX`/`Rename-MediaFile` are copy-paste
  artifacts (no 7.6-only construct is used), and `Test-UdpPort`'s `5.1` is
  wrong for its declared intent.
- **5.1 compatibility retained** for `New-ScanShare`, `Format-UsbDrive`, and
  `Invoke-Elevation` (copied onto client PCs). All other modules are PS7 only.
- **ProfileTools one-liners** (`cpy`, `head`, `tail`, `export`, `quit`, `py`,
  ...) become `Set-Alias` entries over approved-verb functions; only aliases
  are exempt from the approved-verb rule.
- **Shared helpers stay self-contained.** Duplicating `Test-Elevation`,
  `Invoke-NativeCommand`, the Recycle-Bin wrapper, etc. does not affect prompt
  init (nothing imports at startup); sharing would add a first-use import
  dependency and break client-side portability. Only purely in-profile
  formatters (the HTML/CSS renderer) are candidates for dedup.

### Phase 2 - verbs and naming

- Convert the ProfileTools one-liner functions to aliases (see decision above).
- Rename `Extract-Archive` (non-approved `Extract`) and `Replace-Text`
  (non-approved `Replace`) to approved forms; keep the old names as aliases.
- Fix casing: `Test-SmtpRelay` `$HOSTNAME`/`$PORT`, `Update-M365`
  `$C2R_args`, `Format-UsbDrive` `$FileSystem`, Optimize-VMX Pascal/camel mix.
- Drop redundant `[Parameter(Mandatory = $false)]` noise (Rename-MediaFile).
- Give `Set-Alias ep` `-Force` for consistency with `which`.

### Phase 3 - error handling

- Replace raw `throw` in public functions with
  `$PSCmdlet.ThrowTerminatingError()` + `ErrorRecord` (Find-NetworkDevice,
  Restart-NetworkStack DHCP, Rename-MediaFile, Format-UsbDrive, Test-FileShare,
  Test-SmtpRelay, Get-PrinterInfo SNMP).
- Replace non-terminating `Write-Error` + `return` where termination is
  intended (Compress-Video, Optimize-VMX, Format-UsbDrive, Export-SiteReport).
- Standardize on `ThrowTerminatingError` models already in
  `Invoke-Elevation`, `Optimize-PSX`, `Get-CustomModule`, `Test-UdpPort`.
- Keep module-loader `throw` as the one sanctioned exception (no `$PSCmdlet`).

### Phase 4 - help and comments

- Add `.OUTPUTS` and `.EXAMPLE` (and side-effect notes for deletes, `.bak`
  writes, process kills) to every exported function: Optimize-VMX,
  Compress-Video (including `Get-CompressVideoConfig`/`Set-CompressVideoConfig`),
  Rename-MediaFile, Invoke-Elevation/Invoke-Unelevation, Test-FileShare,
  Test-UdpPort, Get-CustomModule, Get-NetworkDiagnostics, Find-NetworkDevice,
  and the ProfileTools short-help functions.
- Remove step/section narration comments (`# ---- N. X ----`,
  `# ==== PHASE N ====`, numbered banners) while preserving rationale comments.
- Strip the one-off benchmark numbers embedded in
  `Optimize-PSX/Private/Start-ChdmanProcess.ps1`.

### Phase 5 - manifest standardization

- Use array form for `FunctionsToExport`/`AliasesToExport` everywhere
  (Optimize-PSX, Rename-MediaFile, Test-* use strings).
- Remove wildcard exports (`Rename-MediaFile` `CmdletsToExport`/
  `VariablesToExport = '*'`).
- Add `PrivateData` (`Tags`, `ProjectUri`) and `FileList` where missing
  (Export-SiteReport, Find-NetworkDevice, Get-NetworkDiagnostics,
  Get-CustomModule, ProfileTools, Get-PrinterInfo, all `Test-*`).
- Fix `FileList` drift: Compress-Video omits `Test-OutputIntegrity.ps1`;
  Optimize-PSX omits `_StreamPump.ps1`.
- Apply the 7.2 floor and correct `CompatiblePSEditions` per the decisions
  above; point `Get-PrinterInfo`'s `ProjectUri` at this repo.

### Phase 6 - loader and StrictMode

- Collapse the two loader shapes into one canonical template.
- Add `#Requires -Version` and `Set-StrictMode -Version Latest` to the modules
  missing them (Export-SiteReport, Find-NetworkDevice, Get-NetworkDiagnostics,
  Get-CustomModule, Test-FileShare, Test-SmtpRelay, Test-UdpPort,
  ProfileTools, and Rename-MediaFile's loader).

### Phase 7 - dead code and dedup

- Delete tracked dead artifact
  `Modules/Rename-MediaFile/Private/Show-RenamePreview.ps1.old`.
- Remove unused helpers: `Get-ElevationHint` in Invoke-Elevation, unreachable
  `-DryRun` parameters in Restart-PrintStack, `-IncludeDisconnected` in
  Restart-NetworkStack, and `Add-PrintStackAllowListEntry`'s unused `$Driver`.
- Reconcile `Restart-PrintStack/README.md` with `_Config.ps1` and the plan
  reason strings.
- Consider hashing/regenerating duplicated helper files rather than sharing
  them, if drift becomes a problem (see the self-contained decision).

### Phase 8 - robustness and coverage

- Replace cleartext HTTP and confirm `Invoke-Expression` of remote content in
  `Get-PublicIP`, `New-Hastebin`, `Get-Activated`, and `Invoke-Titus`.
- Centralize scattered magic numbers into `_Config.ps1` (size caps, scoring
  weights, timeouts, MAX_PATH, Win32 error 1223).
- Add regression coverage for modules that currently have none; prioritize the
  pure/testable helpers (Get-CustomModule and ProfileTools Find-Text now have
  tests under `Tests/`).
