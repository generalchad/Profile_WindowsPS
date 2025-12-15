# -----------------------------------------------------------------------------
# Config/Aliases.ps1 - Shortcuts and One-Liners
# -----------------------------------------------------------------------------

# --- Core System ---
if (Get-Command ntop -ErrorAction SilentlyContinue) { Set-Alias -Name top -Value ntop }
Set-Alias -Name ep  -Value Edit-Profile
# Using -Force to overwrite the default 'sp' (Set-Property) alias
Set-Alias -Name sp  -Value Sync-Profile -Force  # Source Profile

# NOTE: The alias '.' (dot) is the built-in PowerShell Dot-Sourcing operator
# and cannot be reliably overwritten. Removed to prevent breakage.

Set-Alias -Name grep -Value Find-Text
Set-Alias -Name sed  -Value Replace-Text
# Using -Force to overwrite the default 'which' (Get-Command) alias
Set-Alias -Name which -Value Get-Command -Force

# --- Clipboard ---
("clearclipboard", "clearclip", "clrclip") | ForEach-Object { Set-Alias -Name $_ -Value Clear-Clipboard }
function cpy { Set-Clipboard $args[0] }
function pst { Get-Clipboard }

# --- Editors ---
# Using -Force to overwrite the default 'vi' alias
("vim", "vi") | ForEach-Object { Set-Alias -Name $_ -Value $env:EDITOR -Force }
if (-not (Get-Command code-insiders -ErrorAction SilentlyContinue)) { Set-Alias -Name code-insiders -Value code }

# --- Filesystem ---
("ff", "find")          | ForEach-Object { Set-Alias -Name $_ -Value Find-File }
("nf", "touch")         | ForEach-Object { Set-Alias -Name $_ -Value New-File }

# Fix for 'md' and 'mkdir': Remove the existing immutable aliases first, then set the new one.
("mkcd", "mkdir", "md") | ForEach-Object {
    $aliasName = $_
    
    # Attempt to remove the existing, protected alias
    try {
        Remove-Item "Alias:$aliasName" -Force -ErrorAction SilentlyContinue
    } catch {}

    # Now, set the new alias
    Set-Alias -Name $aliasName -Value New-Folder -Force
}

("unzip", "extract")    | ForEach-Object { Set-Alias -Name $_ -Value Extract-Archive }
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
function dl   { Set-Location -Path $HOME\Downloads }
Set-Alias -Name downloads -Value dl
function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }
function ll { Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize }

# --- Networking ---
("testsmtp", "testmail", "checksmtp") | ForEach-Object { Set-Alias -Name $_ -Value Test-SmtpRelay }
("resetip", "renewip", "updateip") | ForEach-Object { Set-Alias -Name $_ -Value Update-IPConfig }
("myip", "getmyip", "showmyip") | ForEach-Object { Set-Alias -Name $_ -Value Show-MyIP }
("speed", "speedtest") | ForEach-Object { Set-Alias -Name $_ -Value Test-NetSpeed }
function flushdns { Clear-DnsClientCache }
function Get-PublicIP { (Invoke-WebRequest http://ifconfig.me/ip).Content }

# --- Process Management ---
# Using -Force to overwrite the default 'kill' (Stop-Process) alias
("pkill", "kill", "stop") | ForEach-Object { Set-Alias -Name $_ -Value Stop-ProcessByName -Force }
function pgrep($name) { Get-Process $name }

# --- System Info/Utils ---
("up", "uptime") | ForEach-Object { Set-Alias -Name $_ -Value Get-Uptime }
("instime", "installtime") | ForEach-Object { Set-Alias -Name $_ -Value Get-WindowsInstallInfo }
function sysinfo { Get-ComputerInfo }
Set-Alias -Name hb -Value New-Hastebin
function export($name, $value) { Set-Item -Force -Path "env:$name" -Value $value }
function quit { exit }
function py { try { python @args } catch { Write-Error "Python error: $_" } }