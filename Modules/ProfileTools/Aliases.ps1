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
<#
.SYNOPSIS
    Copies the given text to the clipboard.
#>
function cpy { Set-Clipboard $args[0] }

<#
.SYNOPSIS
    Reads the current clipboard contents.
#>
function pst { Get-Clipboard }

<#
.SYNOPSIS
    Prints the first N lines of a file.
#>
function head($Path, $n = 10) { Get-Content $Path -Head $n }

<#
.SYNOPSIS
    Prints the last N lines of a file.
#>
function tail($Path, $n = 10) { Get-Content $Path -Tail $n }

<#
.SYNOPSIS
    Lists available volumes and free space.
#>
function df { Get-Volume }

<#
.SYNOPSIS
    Runs git status.
#>
function gs { git status }

<#
.SYNOPSIS
    Stages all changes.
#>
function ga { git add . }

<#
.SYNOPSIS
    Pushes the current branch.
#>
function gp { git push }

<#
.SYNOPSIS
    Jumps to the Github directory via zoxide.
#>
function g  { z Github }

<#
.SYNOPSIS
    Stages all changes and commits with the given message.
#>
function gcom { param([string[]]$Message) git add .; git commit -m "$Message" }

<#
.SYNOPSIS
    Stages all changes, commits, and pushes in one step.
#>
function lazyg { param([string[]]$Message) git add .; git commit -m "$Message"; git push }

<#
.SYNOPSIS
    Changes to the Documents directory.
#>
function docs { Set-Location -Path "$HOME\Documents" }

<#
.SYNOPSIS
    Changes to the Desktop directory.
#>
function dtop { Set-Location -Path "$HOME\Desktop" }

<#
.SYNOPSIS
    Changes to the Downloads directory.
#>
function dl   { Set-Location -Path "$HOME\Downloads" }

<#
.SYNOPSIS
    Lists all items in the current directory, including hidden.
#>
function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }

<#
.SYNOPSIS
    Lists only hidden items in the current directory.
#>
function ll { Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize }

<#
.SYNOPSIS
    Clears the DNS client cache.
#>
function flushdns { Clear-DnsClientCache }

<#
.SYNOPSIS
    Returns the machine's public IP address.
#>
function Get-PublicIP { (Invoke-WebRequest http://ifconfig.me/ip).Content }

<#
.SYNOPSIS
    Lists processes by name.
#>
function pgrep($name) { Get-Process $name }

<#
.SYNOPSIS
    Runs Get-ComputerInfo.
#>
function sysinfo { Get-ComputerInfo }

<#
.SYNOPSIS
    Sets an environment variable in the current session.
#>
function export($name, $value) { Set-Item -Force -Path "env:$name" -Value $value }

<#
.SYNOPSIS
    Exits the shell.
#>
function quit { exit }

<#
.SYNOPSIS
    Runs Python, warning if it is not installed.
#>
function py {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        python @args
    } else {
        Write-Warning "Python not found."
    }
}
