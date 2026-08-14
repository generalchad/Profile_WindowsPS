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
# Only pass supported parameters to avoid errors on older PSReadLine versions
$supportedParams = (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue).Parameters
if ($supportedParams) {
    $filteredOptions = @{}
    foreach ($key in $PSReadLineOptions.Keys) {
        if ($supportedParams.ContainsKey($key)) {
            $filteredOptions[$key] = $PSReadLineOptions[$key]
        }
    }
    Set-PSReadLineOption @filteredOptions
}

# --- History Handler (Secrets) ---
Set-PSReadLineOption -AddToHistoryHandler {
    param($Line)
    $sensitive = @("password", "secret", "key", "apikey", "token", "connectionstring")
    if ($sensitive | Where-Object { $Line -ilike "*$_*" }) { return }
}

# --- Editor Config ---
$editorPriority = 'nvim', 'vim', 'vi', 'code-insiders.cmd', 'code-insiders', 'code.cmd', 'code', 'notepad++'
$script:foundEditor = $null
foreach ($editor in $editorPriority) {
    $cmd = Get-Command $editor -CommandType Application -ErrorAction SilentlyContinue
    if ($cmd) {
        $script:foundEditor = $cmd.Name
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
[System.Environment]::SetEnvironmentVariable('EDITOR', $env:EDITOR, 'User')

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
