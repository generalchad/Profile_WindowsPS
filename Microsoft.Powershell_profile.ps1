#region Imports
<# Terminal Icons #>
if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
    Install-Module -Name Terminal-Icons -Repository PSGallery
}
Import-Module -Name Terminal-Icons

<# ntop #>
if (Get-Command ntop -ErrorAction SilentlyContinue) {
    Set-Alias -Name top -Value ntop
}

<# zoxide #>
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
#endregion

#region Color & Theme
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
#endregion

#region Core Utilities
function Test-CommandExists {
    param($command)
    $exists = $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
    return $exists
}

function Test-GithubConnection {
    [CmdletBinding()]
    param()

    $Connected = $false
    try {
        $null = Invoke-RestMethod -Uri "https://github.com" -ConnectionTimeoutSeconds 1
        Write-Debug "Test-GithubConnection: Connected to GitHub successfully."
        $Connected = $true
    } catch [System.Net.WebException] {
        Write-Debug "Test-GithubConnection: Network error: $($_.Exception.Message)"
    } catch {
        Write-Debug "Test-GithubConnection: An unexpected error occurred: $($_.Exception.Message)"
    }
    return $Connected
}
#endregion

#region Clipboard Utilities
function Clear-Clipboard {
    [CmdletBinding()]
    param()

    Set-Clipboard -Value $null
}
Set-Alias -Name clearclipboard  -Value Clear-Clipboard
Set-Alias -Name clrclip -Value Clear-Clipboard

function cpy { Set-Clipboard $args[0] }

function pst { Get-Clipboard }
#endregion

#region Editor Config
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
    vim $PROFILE
}
Set-Alias -Name ep -Value Edit-Profile

function Sync-Profile {
    . $PROFILE
}
Set-Alias -Name Reload-Profile -Value Sync-Profile
Set-Alias -Name reload -Value Sync-Profile
Set-Alias -Name reset -Value Sync-Profile

function vi { nvim @args }

function vim { nvim @args }
#endregion

#region Filesystem Utilities
function Find-File {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    Write-Debug "Find-File: Searching for files matching '$Name'"

    Get-ChildItem -Recurse -Filter "*$Name*" -ErrorAction SilentlyContinue | 
        Select-Object -ExpandProperty FullName
}
Set-Alias -Name ff -Value Find-File
Set-Alias -Name find -Value Find-File

function Find-Text {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Regex,

        [Parameter(ValueFromPipeline)]
        [string[]]$Path = @()
    )

    Write-Debug "Find-Text: Searching for text matching '$Regex' in $Path"

    if ($Path.Count -eq 0) {
        $input | Select-String $Regex
    } else {
        Get-ChildItem $Path | Select-String $Regex
    }
}
Set-Alias -Name grep -Value Find-Text

function New-File {
    [CmdletBinding()]
    param(
        [string]$Path = ".\New file"
    )

    New-Item -Path $Path -ItemType File | Out-Null
}
Set-Alias -Name touch -Value New-File
Set-Alias -Name nf -Value New-File

function New-Folder {
    [CmdletBinding()]
    param(
        [string]$Path = ".\New folder"
    )

    New-Item -Path $Path -ItemType Directory | Out-Null

    <# !!! Warning: Nonstandard nonsense !!! #>

    # If the function is invoked as `mkcd`, change the location to the new folder after creation
    if ($MyInvocation.InvocationName -eq "mkcd") {
        Set-Location $Path
    }

    <# !!! /Warning: Nonstandard nonsense !!! #>
}
Set-Alias -Name mkcd -Value New-Folder
Set-Alias -Name mkdir -Value New-Folder

function head {
  param($Path, $n = 10)
  Get-Content $Path -Head $n
}

function tail {
  param($Path, $n = 10)
  Get-Content $Path -Tail $n
}

function df {
    get-volume
}

function sed($file, $find, $replace) {
    (Get-Content $file).replace("$find", $replace) | Set-Content $file
}

function unzip ($file) {
    Write-Output("Extracting", $file, "to", $pwd)
    $fullFile = Get-ChildItem -Path $pwd -Filter $file | ForEach-Object { $_.FullName }
    Expand-Archive -Path $fullFile -DestinationPath $pwd
}
#endregion

#region Git Operations
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
#endregion

#region Miscellaneous Shortcuts & Utilities
function Invoke-PeriodicTable {
    if (Test-CommandExists "periodic-table-cli") {
        periodic-table-cli
    } else {
        Write-Error "periodic-table-cli is not installed."
    }
}
Set-Alias -Name pt -Value Invoke-PeriodicTable
Set-Alias -Name ptable -Value Invoke-PeriodicTable
Set-Alias -Name ptoe -Value Invoke-PeriodicTable
#endregion

#region Navigation Shortcuts
function Invoke-Explorer {
    [CmdletBinding()]
    param(
        [string]$Path = "."
    )

    Start-Process -FilePath explorer.exe -ArgumentList $Path
}
Set-Alias -Name explore -Value Invoke-Explorer
Set-Alias -Name explorer -Value Invoke-Explorer

function docs { Set-Location -Path $HOME\Documents }

function dtop { Set-Location -Path $HOME\Desktop }

function dl { Set-Location -Path $HOME\Downloads }

function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }

function ll { Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize }
#endregion

#region Networking Utilities
function Test-NetSpeed {
    if (Test-CommandExists librespeed-cli) {
        librespeed-cli $args[0]
    } else {
        Write-Error "librespeed-cli is not installed."
    }
}
Set-Alias -Name speed -Value Test-NetSpeed
Set-Alias -Name speedtest -Value Test-NetSpeed

function flushdns { Clear-DnsClientCache }

function Get-PublicIP { (Invoke-WebRequest http://ifconfig.me/ip).Content }
#endregion

#region PowerShell Updates
function Get-LatestPowerShellVersion {
    [CmdletBinding()]
    param()

    Write-Verbose "Checking for PowerShell updates..."
    if (-not (Test-GithubConnection)) {
        Write-Warning "Unable to connect to perform PowerShell update at this time."
        return
    }
    try {
        $GitHubApiUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $LatestReleaseInfo = Invoke-RestMethod -Uri $GitHubApiUrl
        $LatestVersionString = $LatestReleaseInfo.tag_name.TrimStart('v')
        $LatestVersion = [Version]$LatestVersionString
        return $LatestVersion
    } catch {
        Write-Debug Get-LatestPowerShellVersion
        return $null
    }
}

function Update-PowerShell {
    $LatestVersion = Get-LatestPowerShellVersion
    if ($null -eq $LatestVersion) {
        Write-Error "Unable to check for PowerShell updates. Please check your internet connection." -ErrorAction Continue
        return
    }
    $CurrentVersion = $PSVersionTable.PSVersion
    if ($CurrentVersion -ge $LatestVersion) {
        Write-Host "PowerShell is up to date." -ForegroundColor Green
        Write-Debug "Current version: $CurrentVersion"
        return
    } else {
        Write-Host "PowerShell is out of date. Current version: $CurrentVersion. Latest version: $LatestVersion" -ForegroundColor Yellow
        $ConfirmUpdate = Read-Host "Do you want to update PowerShell? (Y/N)"
        if ($ConfirmUpdate.ToLower() -eq "y") {
            winget upgrade -e --id="Microsoft.PowerShell" --accept-source-agreements --accept-package-agreements
            Write-Host "PowerShell has been updated to version $LatestVersion" -ForegroundColor Green
        }
    }
}
Update-PowerShell
#endregion

#region Process Management
function Stop-ProcessByName {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
        [string[]]$NameOrPid
    )

    foreach ($item in $NameOrPid) {
        if ($item -match '^\d+$') {
            $processes = Get-Process -Id $item -ErrorAction SilentlyContinue
        } else {
            $processes = Get-Process -Name $item -ErrorAction SilentlyContinue
        }

        if ($processes) {
            if ($PSCmdlet.ShouldProcess("Processes matching '$item'","Stop")) {
                $processInfo = $processes | Select-Object ProcessName, Id, Path
                $processes | Stop-Process

                Write-Host "Stopped all processes matching '$item'" -ForegroundColor Green
                Write-Host "Details of stopped processes:" -ForegroundColor Cyan
                
                $processInfo | ForEach-Object {
                    Write-Host ("Process: {0} (PID: {1})" -f $_.ProcessName, $_.Id) -ForegroundColor Yellow
                    if ($_.Path) {
                        Write-Host ("Path: {0}" -f $_.Path) -ForegroundColor Gray
                    }
                }
            }
        } else {
            Write-Warning "No processes matching '$item' found."
        }
    }
}
Set-Alias -Name kill -Value Stop-ProcessByName
Set-Alias -Name stop -Value Stop-ProcessByName

function pkill($name) {
    Get-Process $name -ErrorAction SilentlyContinue | Stop-Process
}

function pgrep($name) {
    Get-Process $name
}
#endregion

#region System Information
function Get-Uptime {
    [CmdletBinding()]
    param()
    
    $OS = Get-CimInstance Win32_OperatingSystem
    $LastBootUpTime = $OS.LastBootUpTime
    $Uptime = (Get-Date) - $LastBootUpTime

    Write-Output ("Last Boot Time: {0}" -f $LastBootUpTime)
    Write-Output ("System Uptime: {0} days, {1} hours, {2} minutes" -f `
        [int]$Uptime.TotalDays, $Uptime.Hours, $Uptime.Minutes)
}
Set-Alias -Name up -Value Get-Uptime
Set-Alias -Name uptime -Value Get-Uptime

function Get-WindowsInstallInfo {
    [CmdletBinding()]
    param()

    $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    
    $InstallDateValue = Get-ItemProperty -Path $RegistryPath -Name "InstallDate"
    $InstallDate = [System.DateTime]::UnixEpoch.AddSeconds($InstallDateValue.InstallDate)
    $OperationalTime = (Get-Date) - $InstallDate

    $WindowsVersion = (Get-ItemProperty -Path $RegistryPath -Name "ProductName").ProductName
    $BuildNumber = (Get-ItemProperty -Path $RegistryPath -Name "CurrentBuildNumber").CurrentBuildNumber
    $UBR = (Get-ItemProperty -Path $RegistryPath -Name "UBR").UBR
    $FullBuildNumber = "$BuildNumber.$UBR"

    $Uptime = (Get-Date) - (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime

    $DiskSpace = Get-PSDrive C | Select-Object -ExpandProperty Free
    $RAM = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
    $CPU = Get-CimInstance -ClassName Win32_Processor

    Write-Output ("Windows Version: {0} (Build {1})" -f $WindowsVersion, $FullBuildNumber)
    Write-Output ("Install Date: {0}" -f $InstallDate)
    Write-Output ("Operational Time: {0:N0} days, {1} hours, {2} minutes" -f 
        $OperationalTime.TotalDays, $OperationalTime.Hours, $OperationalTime.Minutes)
    Write-Output ("System Uptime: {0:N0} days, {1} hours, {2} minutes" -f 
        $Uptime.TotalDays, $Uptime.Hours, $Uptime.Minutes)
    Write-Output ("Available Disk Space: {0:N2} GB" -f ($DiskSpace / 1GB))
    Write-Output ("Total RAM: {0:N2} GB" -f ($RAM.Sum / 1GB))
    Write-Output ("CPU: {0} ({1} cores)" -f $CPU.Name, $CPU.NumberOfCores)
}
Set-Alias -Name instime -Value Get-WindowsInstallInfo
Set-Alias -Name installtime -Value Get-WindowsInstallInfo

function sysinfo { Get-ComputerInfo }
#endregion

#region System Utilities
function New-Hastebin {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Error "File path does not exist." -ErrorAction Continue
        return
    }
    
    $Content = Get-Content $FilePath -Raw
    $uri = "http://bin.christitus.com/documents"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body $Content -ErrorAction Stop
        $hasteKey = $response.key
        $url = "http://bin.christitus.com/$hasteKey"
        Write-Output $url
    } catch [System.Net.WebException] {
        Write-Error "New-Hastebin: Unexpected network error: $($_.Exception.Message)" -ErrorAction Continue
    } catch {
        Write-Error "New-Hastebin: An unexpected error occurred: $($_.Exception.Message)" -ErrorAction Continue
    }
}
Set-Alias -Name hb -Value New-Hastebin

function which($name) {
    Get-Command $name | Select-Object -ExpandProperty Definition
}

function export($name, $value) {
    Set-Item -Force -Path "env:$name" -Value $value;
}

function py { 
    try {
        python @args
    } catch {
        Write-Error "Failed to run Python: $_" -ErrorAction Continue
    }
}

function quit { exit }
#endregion

#region Initialization
try {
    oh-my-posh init pwsh --config "$HOME\Documents\PowerShell\Themes\gruvbox.omp.json" | Invoke-Expression
    & winfetch
}
catch {
    Write-Host "oh-my-posh failed to run: $_"
}
#endregion