# -----------------------------------------------------------------------------
# Config/Aliases.ps1 - Dynamic and built-in-conflicting aliases only
# -----------------------------------------------------------------------------
# Static aliases and one-liner functions live in Modules/ProfileTools and are
# exported via its manifest, so they autoload on first use. Only the aliases
# that need eager, runtime resolution remain here:
#   - vim/vi -> $env:EDITOR and code -> resolved path (dynamic)
#   - top/grep/sed (conditional on whether a real binary exists in PATH)
#   - sp, md, mkdir, mkcd, pkill, kill, stop (shadow built-in aliases and must
#     be applied eagerly at load time)

# --- Core System ---
if (Resolve-CachedCommand 'ntop') { Set-Alias -Name top -Value ntop }

# Attempting to override 'sp' (Set-Property) alias safely
try { Set-Alias -Name sp -Value Sync-Profile -Force -ErrorAction Stop } catch {
    function sp { Sync-Profile @args }
}

# Set-Alias for 'grep' and 'sed' only if they aren't already binaries in PATH
if (-not (Resolve-CachedCommand 'grep')) { Set-Alias -Name grep -Value Find-Text }
if (-not (Resolve-CachedCommand 'sed'))  { Set-Alias -Name sed  -Value Replace-Text }

# --- Editors ---
# 1. Safety check: Only alias vi/vim if $env:EDITOR is actually set
if (-not [string]::IsNullOrEmpty($env:EDITOR)) {
    ("vim", "vi") | ForEach-Object { Set-Alias -Name $_ -Value $env:EDITOR -Force }
}

# 2. VS Code Logic - Optimized to check PATH and fallback to default install paths
$insidersPath = Resolve-CachedCommand 'code-insiders.cmd'
if (-not $insidersPath) { $insidersPath = Resolve-CachedCommand 'code-insiders' }
if (-not $insidersPath) {
    $p = "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders\bin\code-insiders.cmd"
    if (Test-Path $p) { $insidersPath = $p }
}

$stablePath = Resolve-CachedCommand 'code.cmd'
if (-not $stablePath) { $stablePath = Resolve-CachedCommand 'code' }
if (-not $stablePath) {
    $p = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
    if (Test-Path $p) { $stablePath = $p }
}

if ($insidersPath -and -not $stablePath) {
    # If only Insiders is installed, alias 'code' to Insiders
    Set-Alias -Name code -Value $insidersPath -Force
} elseif ($stablePath) {
    Set-Alias -Name code -Value $stablePath -Force
}

# --- Filesystem (shadow built-in mkdir/md) ---
("mkcd", "mkdir", "md") | ForEach-Object {
    $aliasName = $_
    # Remove existing alias if it exists
    if (Test-Path "Alias:$aliasName") {
        Remove-Item "Alias:$aliasName" -Force -ErrorAction SilentlyContinue
    }
    # Set new alias (Shadows function if present)
    Set-Alias -Name $aliasName -Value New-Folder -Force
}

# --- Process Management (shadow built-in kill) ---
# Overwrite aliases where possible, fallback to wrapper function for AllScope aliases
("pkill", "kill", "stop") | ForEach-Object {
    try {
        Set-Alias -Name $_ -Value Stop-ProcessByName -Force -ErrorAction Stop
    } catch {
        Set-Item -Path "Function:$_" -Value { param($param) Stop-ProcessByName @args } -Force -ErrorAction SilentlyContinue
    }
}
