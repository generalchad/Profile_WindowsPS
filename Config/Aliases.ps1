# -----------------------------------------------------------------------------
# Config/Aliases.ps1 - Shortcuts and One-Liners
# -----------------------------------------------------------------------------

# --- Core System ---
if (Resolve-CachedCommand 'ntop') { Set-Alias -Name top -Value ntop }
Set-Alias -Name ep  -Value Edit-Profile
# Attempting to override 'sp' (Set-Property) alias safely
try { Set-Alias -Name sp -Value Sync-Profile -Force -ErrorAction Stop } catch {
    function sp { Sync-Profile @args }
}

# Set-Alias for 'grep' and 'sed' only if they aren't already binaries in PATH
if (-not (Resolve-CachedCommand 'grep')) { Set-Alias -Name grep -Value Find-Text }
if (-not (Resolve-CachedCommand 'sed'))  { Set-Alias -Name sed  -Value Replace-Text }

# Using -Force to overwrite the default 'which' (Get-Command) alias
Set-Alias -Name which -Value Get-Command -Force

# --- Clipboard ---
("clearclipboard", "clearclip", "clrclip") | ForEach-Object { Set-Alias -Name $_ -Value Clear-Clipboard }
function cpy { Set-Clipboard $args[0] }
function pst { Get-Clipboard }

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

# --- Filesystem ---
("ff", "find")          | ForEach-Object { Set-Alias -Name $_ -Value Find-File }
("nf", "touch")         | ForEach-Object { Set-Alias -Name $_ -Value New-File }

# Fix for 'md' and 'mkdir'
("mkcd", "mkdir", "md") | ForEach-Object {
    $aliasName = $_
    # Remove existing alias if it exists
    if (Test-Path "Alias:$aliasName") {
        Remove-Item "Alias:$aliasName" -Force -ErrorAction SilentlyContinue
    }
    # Set new alias (Shadows function if present)
    Set-Alias -Name $aliasName -Value New-Folder -Force
}

("unzip", "extract")    | ForEach-Object { Set-Alias -Name $_ -Value Extract-Archive }
function head($Path, $n=10) { Get-Content $Path -Head $n }
function tail($Path, $n=10) { Get-Content $Path -Tail $n }
function df { get-volume }

# --- Git ---
function gs { git status }
function ga { git add . }
function gp { git push }
function g { z Github }
function gcom { param([string[]]$Message) git add .; git commit -m "$Message" }
function lazyg { param([string[]]$Message) git add .; git commit -m "$Message"; git push }

# --- Navigation ---
("explore", "open") | ForEach-Object { Set-Alias -Name $_ -Value Invoke-Explorer }
function docs { Set-Location -Path $HOME\Documents }
function dtop { Set-Location -Path $HOME\Desktop }
function dl   { Set-Location -Path $HOME\Downloads }
Set-Alias -Name downloads -Value dl
function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }
function ll { Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize }

# --- Networking ---
("testsmtp", "testmail", "checksmtp") | ForEach-Object { Set-Alias -Name $_ -Value Test-SmtpRelay }
("resetip", "renewip", "updateip")    | ForEach-Object { Set-Alias -Name $_ -Value Update-IPConfig }
("myip", "getmyip", "showmyip")       | ForEach-Object { Set-Alias -Name $_ -Value Show-MyIP }
("speed", "speedtest")                | ForEach-Object { Set-Alias -Name $_ -Value Test-NetSpeed }
function flushdns { Clear-DnsClientCache }
function Get-PublicIP { (Invoke-WebRequest http://ifconfig.me/ip).Content }

# --- Process Management ---
# Overwrite aliases where possible, fallback to wrapper function for AllScope aliases
("pkill", "kill", "stop") | ForEach-Object {
    try {
        Set-Alias -Name $_ -Value Stop-ProcessByName -Force -ErrorAction Stop
    } catch {
        Set-Item -Path "Function:$_" -Value { param($param) Stop-ProcessByName @args } -Force -ErrorAction SilentlyContinue
    }
}
function pgrep($name) { Get-Process $name }

# --- System Info/Utils ---
("up", "uptime")           | ForEach-Object { Set-Alias -Name $_ -Value Get-Uptime }
("instime", "installtime") | ForEach-Object { Set-Alias -Name $_ -Value Get-WindowsInstallInfo }
function sysinfo { Get-ComputerInfo }
Set-Alias -Name hb -Value New-Hastebin
function export($name, $value) { Set-Item -Force -Path "env:$name" -Value $value }
function quit { exit }

# Python wrapper - Simplified to allow interactive mode
function py {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        python @args
    } else {
        Write-Warning "Python not found."
    }
}
