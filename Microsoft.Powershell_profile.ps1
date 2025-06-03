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

#region Colors & Theming
$PSReadLineOptions = @{
    Colors = @{
        Command            = "#fabd2f"
        Parameter          = "#98971a"
        String             = "#83a598"
        Variable           = "#d65d0e"
    }
    PredictionSource      = "History"
    PredictionViewStyle   = "InlineView"
    HistoryNoDuplicates   = $true
    MaximumHistoryCount   = 10000
}
Set-PSReadLineOption @PSReadLineOptions
#endregion

#region Console Configuration
<# Command History Configuration #>
Set-PSReadLineOption -AddToHistoryHandler {
    param($Line)
    $sensitive = @( "password", "secret", "key", "apikey", "token", "connectionstring" )
    $hasSensitive = $sensitive | Where-Object { $Line -like "*$_*" }
    if ($hasSensitive) {
        return
    }
}

<# Custom Autocompletes #>
$completionCommands = @{
    docker = @('run','build','push','pull')
    git    = @('add','commit','push','pull')
    npm    = @('install','run','test')
}

Register-ArgumentCompleter -CommandName $completionCommands.Keys -ScriptBlock {
    param($word, $command)
    $completionCommands[$command] | Where-Object { $_ -like "$word*" }
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
$editorCommands = @{
    nvim          = 'nvim'
    vim           = 'vim'
    vi            = 'vi'
    code          = 'code'
    'notepad++'   = 'notepad++'
}
$EDITOR = $editorCommands.Keys | Where-Object { Test-CommandExists $_ } | Select-Object -First 1
if (-not $EDITOR) { $EDITOR = 'notepad' }
Set-Alias -Name edit -Value $EDITOR            
Set-Alias -Name vim -Value $EDITOR
Set-Alias -Name vi -Value $EDITOR

if (-not (Test-CommandExists code-insiders)) {
    Set-Alias -Name code-insiders -Value code
} else {
    Set-Alias -Name code -Value code-insiders
}

function Edit-Profile {
    vim $PROFILE
}
Set-Alias -Name ep -Value Edit-Profile

function Sync-Profile {
    Write-Debug "Reloading PowerShell profile..."
    $startTime = Get-Date
    . $PROFILE
    $endTime = Get-Date
    $loadTime = ($endTime - $startTime).TotalMilliseconds
    Write-Host "Profile reloaded in $([math]::Round($loadTime))ms." -ForegroundColor Green
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
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position=0, ValueFromPipeline)]
        [string]$Path = ".\New file",

        [Parameter(Position=1)]
        [switch]$Hidden,

        [Parameter(Position=2)]
        [switch]$System
    )

    process {
        try {
            Write-Debug "New-File: Creating new file at $Path"
            Write-Debug "Hidden? $Hidden"
            Write-Debug "System? $System"
            
            $NewItem = New-Item -Path $Path -ItemType File -Force

            if ($Hidden) { $NewItem.Attributes += "Hidden" }
            if ($System) { $NewItem.Attributes += "System" }

            Write-Debug "New-File: Created new file at $Path"
        } catch [System.UnauthorizedAccessException] {
            Write-Error "New File: You do not have the correct permissions: $_"
        } catch {
            Write-Error "New File: An unexpected error occurred: $_"
        }
    }

}
Set-Alias -Name touch -Value New-File
Set-Alias -Name nf -Value New-File

function New-Folder {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, ValueFromPipeline)]
        [string]$Path = ".\New folder",

        [Parameter(Position=1)]
        [switch]$Hidden,

        [Parameter(Position=2)]
        [switch]$System
    )
    
    process {
    try {
        Write-Debug "New-Folder: Creating new folder at $Path"
        Write-Debug "Hidden? $Hidden"
        Write-Debug "System? $System"

        $NewFolder = New-Item -Path $Path -ItemType Directory -Force

        if ($Hidden) { $NewFolder.Attributes += "Hidden" }
        if ($System) { $NewFolder.Attributes += "System" }

        Write-Debug "New-Folder: Created new folder at $Path"
    } catch [System.UnauthorizedAccessException] {
        Write-Error "New-Folder: You do not have the correct permissions: $_" -ErrorAction Continue
        return
    } catch {
        Write-Error "New-Folder: An unexpected error occurred: $_" -ErrorAction Continue
        return
    }

    <# !!! Warning: Nonstandard nonsense !!! #>

    # If the function is invoked as `mkcd`, change the location to the new folder after creation
    if ($MyInvocation.InvocationName -eq "mkcd") {
        Set-Location $Path
    }

    <# !!! /Warning: Nonstandard nonsense !!! #>
    }
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
    if (-not (Test-Path $file)) {
        Write-Error "unzip: File not found: $file" -ErrorAction Continue
        return 
    }

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
        Write-Error "Test-NetSpeed: librespeed-cli is not installed."
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
    [CmdletBinding()]
    param()

    $LatestVersion = Get-LatestPowerShellVersion
    if ($null -eq $LatestVersion) {
        Write-Host "Unable to check for PowerShell updates at this time." -ForegroundColor Yellow
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
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())::IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Write-Error "Update-PowerShell: This function must be run as an administrator." -ErrorAction Continue
                return
            }
            winget upgrade -e --id="Microsoft.PowerShell" --accept-source-agreements --accept-package-agreements
            Write-Host "PowerShell has been updated to version $LatestVersion" -ForegroundColor Green
        }
    }
}
#Update-PowerShell
#endregion

#region Process Management
function Stop-ProcessByName {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromRemainingArguments)]
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

    $Drives = Get-PSDrive -PSProvider FileSystem
    $RAM = Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
    $CPU = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1

    Write-Output ("Windows Version: {0} (Build {1})" -f $WindowsVersion, $FullBuildNumber)
    Write-Output ("Install Date: {0}" -f $InstallDate)
    Write-Output ("Operational Time: {0:N0} days, {1} hours, {2} minutes" -f 
        $OperationalTime.TotalDays, $OperationalTime.Hours, $OperationalTime.Minutes)
    Write-Output ("System Uptime: {0:N0} days, {1} hours, {2} minutes" -f 
        $Uptime.TotalDays, $Uptime.Hours, $Uptime.Minutes)
    
    Write-Output "`nDrive Space:"
    foreach ($Drive in ($Drives | Where-Object { 
        $_.Name -match '^[A-Z]$' -and               # Single letter drive name
        $_.Provider.Name -eq 'FileSystem' -and      # Must be a filesystem drive
        $_.Root -notlike "\\*" -and                 # Must not be a network drive
        $null -ne $_.Used                           # Must have used space value
    })) {
        if ($Drive.Free -and ($Drive.Used -or $Drive.Free)) {
            $FreeSpace = [math]::Round($Drive.Free / 1GB, 2)
            $TotalSpace = [math]::Round(($Drive.Used + $Drive.Free) / 1GB, 2)
            Write-Output ("Drive {0}: {1:N2} GB free of {2:N2} GB" -f 
                $Drive.Name, $FreeSpace, $TotalSpace)
        }
    }
    
    Write-Output ("`nTotal RAM: {0:N2} GB" -f ($RAM.Sum / 1GB))
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
$PS_PROFILE = Join-Path $PSScriptRoot "Profile.ps1"
if (Test-Path $PS_PROFILE) {
    Write-Debug "Loading custom profile from $PS_PROFILE"
    . $PS_PROFILE

    # Determine OMP theme file extension (.omp.json or .omp.yaml)
    $themeBase = "$HOME\Documents\PowerShell\Themes\$OMP_THEME.omp"
    if (Test-Path "$themeBase.json") {
        $themePath = "$themeBase.json"
    } elseif (Test-Path "$themeBase.yaml") {
        $themePath = "$themeBase.yaml"
    } else {
        $themePath = "$themeBase.json" # fallback, may error
    }

    if (-not (Test-CommandExists oh-my-posh)) {
        try {
            oh-my-posh.exe init pwsh --config "$themePath" | Out-String | Invoke-Expression
        } catch {
            Write-Host "Oh-My-Posh failed: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Oh-My-Posh is not installed. Please install it to use custom themes." -ForegroundColor Yellow
    }
} else {
    Write-Debug "No custom profile found at $PS_PROFILE"
    try {
        oh-my-posh init pwsh --config "$HOME\Documents\PowerShell\Themes\gruvbox.omp.json" | Out-String | Invoke-Expression
    }
    catch {
        Write-Host "Oh-My-Posh failed: $_" -ForegroundColor Yellow
    }
}

if (-not (Test-CommandExists fastfetch)) {
    Write-Host "fastfetch is not installed. Please install it to use fastfetch commands." -ForegroundColor Yellow
} else {
    try {
        & fastfetch
    } catch {
        Write-Host "fastfetch failed: $_" -ForegroundColor Yellow
    }
}

if (-not (Test-CommandExists zoxide)) {
    Write-Host "zoxide is not installed. Please install it to use zoxide commands." -ForegroundColor Yellow
} else {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
#endregion
