### PowerShell Profile Refactor
### Version 1.03 - Refactored

# Initial GitHub.com connectivity check with 1 second timeout
function Test-GitHubConnection {
    param (
        [string]$ComputerName = "github.com",
        [int]$Port = 443,
        [int]$Timeout = 1000
    )

    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $client.BeginConnect($ComputerName, $Port, $null, $null)
        $success = $asyncResult.AsyncWaitHandle.WaitOne($Timeout, $false)
        $client.Close()
        return $success
    } catch {
        return $false
    }
}
$global:canConnectToGitHub = Test-GitHubConnection

# Import Modules and External Profiles
# Ensure Terminal-Icons module is installed before importing
if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
    Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module -Name Terminal-Icons
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
    Import-Module "$ChocolateyProfile"
}

function Update-PowerShell {
    if (-not $global:canConnectToGitHub) {
        Write-Host "Skipping PowerShell update check due to GitHub.com not responding within 1 second." -ForegroundColor Yellow
        return
    }

    try {
        Write-Host "Checking for PowerShell updates..." -ForegroundColor Cyan
        $updateNeeded = $false
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $gitHubApiUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $latestReleaseInfo = Invoke-RestMethod -Uri $gitHubApiUrl
        $latestVersion = $latestReleaseInfo.tag_name.Trim('v')
        if ($currentVersion -lt $latestVersion) {
            $updateNeeded = $true
        }

        if ($updateNeeded) {
            Write-Host "Updating PowerShell..." -ForegroundColor Yellow
            winget upgrade "Microsoft.PowerShell" --accept-source-agreements --accept-package-agreements
            Write-Host "PowerShell has been updated. Please restart your shell to reflect changes" -ForegroundColor Magenta
        } else {
            Write-Host "Your PowerShell is up to date." -ForegroundColor Green
        }
    } catch {
        Write-Error "Failed to update PowerShell. Error: $_"
    }
}
Update-PowerShell 

# Admin Check and Prompt Customization
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
function prompt {
    if ($isAdmin) { "[" + (Get-Location) + "] # " } else { "[" + (Get-Location) + "] $ " }
}
$adminSuffix = if ($isAdmin) { " [ADMIN]" } else { "" }
$Host.UI.RawUI.WindowTitle = "PowerShell {0}$adminSuffix" -f $PSVersionTable.PSVersion.ToString()

# Utility Functions
function Test-CommandExists {
    param($command)
    $exists = $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
    return $exists
}

# Editor Configuration
$EDITOR = if (Test-CommandExists nvim) { 'nvim' }
          elseif (Test-CommandExists pvim) { 'pvim' }
          elseif (Test-CommandExists vim) { 'vim' }
          elseif (Test-CommandExists vi) { 'vi' }
          elseif (Test-CommandExists code) { 'code' }
          elseif (Test-CommandExists notepad++) { 'notepad++' }
          elseif (Test-CommandExists sublime_text) { 'sublime_text' }
          else { 'notepad' }
Set-Alias -Name vim -Value $EDITOR

function Edit-Profile {
    vim $PROFILE.CurrentUserAllHosts
}

function Sync-Profile {
    . $profile
}

function touch($file) {
    New-Item -ItemType File -Path $file -Force | Out-Null
}

function ff($name) {
    Get-ChildItem -recurse -filter "*${name}*" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output "$($_.directory)\$($_)"
    }
}

# Network Utilities
function Get-PublicIP { (Invoke-WebRequest http://ifconfig.me/ip).Content }

# System Utilities
function Get-Uptime {
    $os = Get-CimInstance Win32_OperatingSystem
    $lastBootUpTime = $os.LastBootUpTime
    $uptime = (Get-Date) - $lastBootUpTime
    Write-Output ("Last Boot Time: {0}" -f $lastBootUpTime)
    Write-Output ("System Uptime: {0} days, {1} hours, {2} minutes" -f `
        [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes)
}
Set-Alias -Name up -Value Get-Uptime
Set-Alias -Name uptime -Value Get-Uptime

function unzip ($file) {
    Write-Output("Extracting", $file, "to", $pwd)
    $fullFile = Get-ChildItem -Path $pwd -Filter $file | ForEach-Object { $_.FullName }
    Expand-Archive -Path $fullFile -DestinationPath $pwd
}
function hb {
    if ($args.Length -eq 0) {
        Write-Error "No file path specified."
        return
    }
    
    $FilePath = $args[0]
    
    if (Test-Path $FilePath) {
        $Content = Get-Content $FilePath -Raw
    } else {
        Write-Error "File path does not exist."
        return
    }
    
    $uri = "http://bin.christitus.com/documents"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body $Content -ErrorAction Stop
        $hasteKey = $response.key
        $url = "http://bin.christitus.com/$hasteKey"
        Write-Output $url
    } catch {
        Write-Error "Failed to upload the document. Error: $_"
    }
}
function grep($regex, $dir) {
    if ( $dir ) {
        Get-ChildItem $dir | select-string $regex
        return
    }
    $input | select-string $regex
}

function df {
    get-volume
}

function sed($file, $find, $replace) {
    (Get-Content $file).replace("$find", $replace) | Set-Content $file
}

function which($name) {
    Get-Command $name | Select-Object -ExpandProperty Definition
}

function export($name, $value) {
    set-item -force -path "env:$name" -value $value;
}

function pkill($name) {
    Get-Process $name -ErrorAction SilentlyContinue | Stop-Process
}

function pgrep($name) {
    Get-Process $name
}

function head {
  param($Path, $n = 10)
  Get-Content $Path -Head $n
}

function tail {
  param($Path, $n = 10)
  Get-Content $Path -Tail $n
}

# Quick File Creation
function nf { param($name) New-Item -ItemType "file" -Path . -Name $name }

# Directory Management
function mkcd { param($dir) mkdir $dir -Force; Set-Location $dir }

### Quality of Life Aliases

# Navigation Shortcuts
function docs { Set-Location -Path $HOME\Documents }

function dtop { Set-Location -Path $HOME\Desktop }

# Quick Access to Editing the Profile
function ep { vim $PROFILE }

# Simplified Process Management
function k9 { Stop-Process -Name $args[0] }

# Enhanced Listing
function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }
function ll { Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize }

# Git Shortcuts
function gs { git status }

function ga { git add . }

function gc { param($m) git commit -m "$m" }

function gp { git push }

function g { z Github }

function gcom {
    git add .
    git commit -m "$args"
}
function lazyg {
    git add .
    git commit -m "$args"
    git push
}

# Quick Access to System Information
function sysinfo { Get-ComputerInfo }

# Networking Utilities
function flushdns { Clear-DnsClientCache }

# Clipboard Utilities
function cpy { Set-Clipboard $args[0] }

function pst { Get-Clipboard }

function py { python @args }

function quit { exit }

function reset {
    param(
        [switch]$NoWinfetch
    )
    Clear-Host
    if (-not $NoWinfetch) {
        try {
            winfetch
        } catch {
            Write-Host "winfetch failed to run: $_"
        }
    }
    try {
        z ~
    } catch {
        Write-Host "Failed to navigate to home directory: $_"
    }
}

function vi { nvim @args }

function vim { nvim @args }

# Enhanced PowerShell Experience
# Define Gruvbox-inspired custom colors using ANSI escape codes
# TODO: Modularize this later
$GruvboxYellow = "`e[38;2;250;189;47m"   # Gruvbox yellow for commands
$GruvboxGreen = "`e[38;2;152;151;26m"    # Gruvbox green for parameters
$GruvboxCyan = "`e[38;2;131;165;152m"    # Gruvbox cyan for strings
$GruvboxOrange = "`e[38;2;214;93;14m"    # Gruvbox orange for variables
$GruvboxMagenta = "`e[38;2;177;98;134m"  # Gruvbox magenta for operators
$GruvboxRed = "`e[38;2;204;36;29m"       # Gruvbox red for errors
$GruvboxBlue = "`e[38;2;69;133;136m"     # Gruvbox blue for types

Set-PSReadLineOption -Colors @{
    ContinuationPrompt        = "$GruvboxCyan"
    Emphasis                  = "$GruvboxYellow"
    Error                     = "$GruvboxRed"
    Selection                 = "$GruvboxMagenta"
    Default                   = "$GruvboxBlue"
    Comment                   = "$GruvboxGreen"
    Keyword                   = "$GruvboxYellow"
    String                    = "$GruvboxCyan"
    Operator                  = "$GruvboxMagenta"
    Variable                  = "$GruvboxOrange"
    Command                   = "$GruvboxYellow"
    Parameter                 = "$GruvboxGreen"
    Type                      = "$GruvboxBlue"
    Number                    = "$GruvboxOrange"
    Member                    = "$GruvboxYellow"
    InlinePrediction          = "$GruvboxCyan"
    ListPrediction            = "$GruvboxYellow"
    ListPredictionSelected    = "$GruvboxOrange"
}

## Final Line to set prompt
try {
    oh-my-posh init pwsh --config "$HOME\Documents\PowerShell\Themes\gruvbox.omp.json" | Invoke-Expression
}
catch {
    Write-Host "oh-my-posh failed to run: $_"
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
} else {
    Write-Host "zoxide command not found. Attempting to install via winget..."
    try {
        winget install -e --id ajeetdsouza.zoxide
        Write-Host "zoxide installed successfully. Initializing..."
        Invoke-Expression (& { (zoxide init powershell | Out-String) })
    } catch {
        Write-Error "Failed to install zoxide. Error: $_"
    }
}