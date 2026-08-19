# -----------------------------------------------------------------------------
# Config/Settings.ps1 - Core Configuration & Theming
# -----------------------------------------------------------------------------

# --- PSFeedbackProvider ---
# Removed for performance - Enable experimental features manually with:
# Enable-ExperimentalFeature PSFeedbackProvider

# --- PSReadLine & Colors ---
$PSReadLineOptions = @{
    Colors = @{
        Command   = "#fabd2f"
        Parameter = "#98971a"
        String    = "#83a598"
        Variable  = "#d65d0e"
    }
    PredictionSource    = "History"
    PredictionViewStyle = "InlineView"
    HistoryNoDuplicates = $true
    MaximumHistoryCount = 10000
}

# Prediction requires a real VT-capable console. In a redirected / non-interactive
# host (pwsh -Command with piped output, CI, subprocess capture) Set-PSReadLineOption
# throws, and because the loader wraps the whole dot-source in a single try/catch
# that would silently abandon the REST of this file - editor detection, $env:EDITOR
# and the argument completers would never run. Drop the prediction keys instead.
if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) {
    $PSReadLineOptions.Remove('PredictionSource')
    $PSReadLineOptions.Remove('PredictionViewStyle')
}

# Only pass supported parameters to avoid errors on older PSReadLine versions
$supportedParams = (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue).Parameters
if ($supportedParams) {
    $filteredOptions = @{}
    foreach ($key in $PSReadLineOptions.Keys) {
        if ($supportedParams.ContainsKey($key)) {
            $filteredOptions[$key] = $PSReadLineOptions[$key]
        }
    }
    # Isolated so a PSReadLine failure can never abort the remainder of this file.
    try { Set-PSReadLineOption @filteredOptions } catch { Write-Warning "PSReadLine options: $_" }
}

# --- History Handler (Secrets) ---
# Must return $true to keep a line and $false to drop it; returning nothing made
# PSReadLine fall back to its default (keep) for BOTH branches, so secrets were
# never actually being filtered.
$script:SensitiveHistoryPattern = 'password|secret|key|apikey|token|connectionstring'
try {
    Set-PSReadLineOption -AddToHistoryHandler {
        param($Line)
        return ($Line -notmatch $script:SensitiveHistoryPattern)
    }
} catch { Write-Warning "PSReadLine history handler: $_" }

# --- Editor Config ---
$editorPriority = 'nvim', 'vim', 'vi', 'code-insiders.cmd', 'code-insiders', 'code.cmd', 'code', 'notepad++'
$script:foundEditor = $null
foreach ($editor in $editorPriority) {
    if (Resolve-CachedCommand $editor) {
        $script:foundEditor = $editor
        break
    }
}
if (-not $script:foundEditor) {
    if (Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders\bin\code-insiders.cmd") {
        $script:foundEditor = "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders\bin\code-insiders.cmd"
    } elseif (Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd") {
        $script:foundEditor = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
    }
}
$env:EDITOR = if ($script:foundEditor) { $script:foundEditor } else { 'notepad' }

# Persist to the User scope ONLY when the stored value is actually stale.
#
# PERF: a User/Machine-scope SetEnvironmentVariable writes HKCU\Environment and
# then broadcasts WM_SETTINGCHANGE to every top-level window, waiting on each one.
# Measured on this machine at ~7,100 ms - it was single-handedly responsible for
# ~84% of profile load time, on every shell, to rewrite a value that never changed.
# The guarding read costs ~25 ms.
if ([System.Environment]::GetEnvironmentVariable('EDITOR', 'User') -ne $env:EDITOR) {
    [System.Environment]::SetEnvironmentVariable('EDITOR', $env:EDITOR, 'User')
}

# --- Argument Completers ---
$completionCommands = @{
    docker = @('run', 'build', 'push', 'pull')
    npm    = @('install', 'run', 'test')
}
Register-ArgumentCompleter -CommandName $completionCommands.Keys -ScriptBlock {
    param($word, $command)
    $completionCommands[$command] | Where-Object { $_ -like "$word*" }
}
# Note: Git completion is better handled by the 'posh-git' module if you install it.
