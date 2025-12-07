# -----------------------------------------------------------------------------
# Config/Aliases.ps1 - Shortcuts and One-Liners
# -----------------------------------------------------------------------------

# --- Core System ---
if (Get-Command ntop -ErrorAction SilentlyContinue) { Set-Alias -Name top -Value ntop }
Set-Alias -Name ep  -Value Edit-Profile
Set-Alias -Name grep -Value Find-Text
Set-Alias -Name sed  -Value Replace-Text
Set-Alias -Name which -Value Get-Command

# --- Clipboard ---
Set-Alias -Name clearclipboard -Value Clear-Clipboard
Set-Alias -Name clearclip -Value Clear-Clipboard
Set-Alias -Name clrclip -Value Clear-Clipboard
function cpy { Set-Clipboard $args[0] }
function pst { Get-Clipboard }

# --- Editors ---
("vim", "vi") | ForEach-Object { Set-Alias -Name $_ -Value $env:EDITOR }
if (-not (Get-Command code-insiders -ErrorAction SilentlyContinue)) { Set-Alias -Name code-insiders -Value code }

# --- Filesystem ---
("ff", "find") | ForEach-Object { Set-Alias -Name $_ -Value Find-File }
("newfile", "nf", "touch") | ForEach-Object { Set-Alias -Name $_ -Value New-File }
("mkcd", "mkdir") | ForEach-Object { Set-Alias -Name $_ -Value New-Folder }
("extract", "unzip") | ForEach-Object { Set-Alias -Name $_ -Value Extract-Archive }
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
("explore", "explorer", "open", "openfolder") | ForEach-Object { Set-Alias -Name $_ -Value Invoke-Explorer }
function docs { Set-Location -Path $HOME\Documents }
function dtop { Set-Location -Path $HOME\Desktop }
function dl   { Set-Location -Path $HOME\Downloads }
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
("pkill", "kill", "stop") | ForEach-Object { Set-Alias -Name $_ -Value Stop-ProcessByName }
function pgrep($name) { Get-Process $name }

# --- System Info/Utils ---
("up", "uptime") | ForEach-Object { Set-Alias -Name $_ -Value Get-Uptime }
("instime", "installtime") | ForEach-Object { Set-Alias -Name $_ -Value Get-WindowsInstallInfo }
function sysinfo { Get-ComputerInfo }
Set-Alias -Name hb -Value New-Hastebin
function export($name, $value) { Set-Item -Force -Path "env:$name" -Value $value }
function quit { exit }
function py { try { python @args } catch { Write-Error "Python error: $_" } }