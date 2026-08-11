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
Set-PSReadLineOption @PSReadLineOptions

# --- History Handler (Secrets) ---
Set-PSReadLineOption -AddToHistoryHandler {
    param($Line)
    $sensitive = @("password", "secret", "key", "apikey", "token", "connectionstring")
    if ($sensitive | Where-Object { $Line -ilike "*$_*" }) { return }
}

# --- Editor Config ---
if (-not $env:EDITOR) {
    $editorPriority = 'nvim', 'vim', 'vi', 'code', 'notepad++'
    $foundEditor = $null
    # Use early exit loop instead of pipeline for better performance
    foreach ($editor in $editorPriority) {
        if (Get-Command $editor -ErrorAction SilentlyContinue) {
            $foundEditor = $editor
            break  # Exit immediately after finding first match
        }
    }
    # Persist for future sessions to save startup time
    $env:EDITOR = if ($foundEditor) { $foundEditor } else { 'notepad' }
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
