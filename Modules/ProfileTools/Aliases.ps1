# -----------------------------------------------------------------------------
# ProfileTools/Aliases.ps1 - Static aliases and one-liner functions
# -----------------------------------------------------------------------------
# Everything in this file is static (no runtime PATH/editor resolution), so it
# can live inside the module and be exported via the manifest. Typing any of
# these triggers module autoload, keeping startup cost near zero.
#
# Aliases that depend on runtime resolution (vim/vi -> $env:EDITOR, code -> path)
# or that conflict with built-in aliases (sp, md, mkdir, kill, ...) stay in the
# profile at Config/Aliases.ps1 where they can be applied eagerly.

# --- Aliases ---
Set-Alias -Name ep  -Value Edit-Profile
Set-Alias -Name which -Value Get-Command -Force

("clearclipboard", "clearclip", "clrclip") | ForEach-Object { Set-Alias -Name $_ -Value Clear-Clipboard }

("ff", "find")          | ForEach-Object { Set-Alias -Name $_ -Value Find-File }
("nf", "touch")         | ForEach-Object { Set-Alias -Name $_ -Value New-File }
("unzip", "extract")    | ForEach-Object { Set-Alias -Name $_ -Value Extract-Archive }
("explore", "open")     | ForEach-Object { Set-Alias -Name $_ -Value Invoke-Explorer }
Set-Alias -Name downloads -Value dl

("testsmtp", "testmail", "checksmtp") | ForEach-Object { Set-Alias -Name $_ -Value Test-SmtpRelay }
("myip", "getmyip", "showmyip")       | ForEach-Object { Set-Alias -Name $_ -Value Show-MyIP }
("speed", "speedtest")                | ForEach-Object { Set-Alias -Name $_ -Value Test-NetSpeed }
("up", "uptime")                      | ForEach-Object { Set-Alias -Name $_ -Value Get-Uptime }
("instime", "installtime")            | ForEach-Object { Set-Alias -Name $_ -Value Get-WindowsInstallInfo }
Set-Alias -Name hb -Value New-Hastebin

# --- One-liner functions ---
function cpy { Set-Clipboard $args[0] }
function pst { Get-Clipboard }

function head($Path, $n = 10) { Get-Content $Path -Head $n }
function tail($Path, $n = 10) { Get-Content $Path -Tail $n }
function df { Get-Volume }

function gs { git status }
function ga { git add . }
function gp { git push }
function g  { z Github }
function gcom { param([string[]]$Message) git add .; git commit -m "$Message" }
function lazyg { param([string[]]$Message) git add .; git commit -m "$Message"; git push }

function docs { Set-Location -Path "$HOME\Documents" }
function dtop { Set-Location -Path "$HOME\Desktop" }
function dl   { Set-Location -Path "$HOME\Downloads" }

function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }
function ll { Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize }

function flushdns { Clear-DnsClientCache }
function Get-PublicIP { (Invoke-WebRequest http://ifconfig.me/ip).Content }

function pgrep($name) { Get-Process $name }
function sysinfo { Get-ComputerInfo }
function export($name, $value) { Set-Item -Force -Path "env:$name" -Value $value }
function quit { exit }

function py {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        python @args
    } else {
        Write-Warning "Python not found."
    }
}
