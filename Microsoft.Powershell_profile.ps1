#region Core Setup
<# PSFeedbackProvider #>
# This fixes issues with feedback prompts in PowerShell 7.3+
if (-not (Get-ExperimentalFeature -Name PSFeedbackProvider -ErrorAction SilentlyContinue)) {
    Write-Host "Experimental feature PSFeedbackProvider is not enabled. Enabling it now." -ForegroundColor Yellow
    try {
        Enable-ExperimentalFeature PSFeedbackProvider
    }
    catch {
        Write-Warning "Failed to enable PSFeedbackProvider: $_"
    }
}

<# ntop #>
if (Get-Command ntop -ErrorAction SilentlyContinue) {
    Set-Alias -Name top -Value ntop
}
#endregion

#region PSReadLine & Theming
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

<# Command History Configuration #>
Set-PSReadLineOption -AddToHistoryHandler {
    param($Line)
    $sensitive = @("password", "secret", "key", "apikey", "token", "connectionstring")
    $hasSensitive = $sensitive | Where-Object { $Line -like "*$_*" }
    if ($hasSensitive) {
        return
    }
}

<# Custom Autocompletes #>
$completionCommands = @{
    docker = @('run', 'build', 'push', 'pull')
    git    = @('add', 'commit', 'push', 'pull')
    npm    = @('install', 'run', 'test')
}

Register-ArgumentCompleter -CommandName $completionCommands.Keys -ScriptBlock {
    param($word, $command)
    $completionCommands[$command] | Where-Object { $_ -like "$word*" }
}
#endregion

#region Core Utilities
<#
    .SYNOPSIS
    Checks if a command exists in the current PowerShell session.

    .PARAMETER Command
    The name of the command to check for.
#>
function Test-CommandExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    $exists = $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
    return $exists
}

<#
    .SYNOPSIS
    Checks if the user is connected to GitHub.
#>
function Test-GithubConnection {
    [CmdletBinding()]
    param()

    $Connected = $false
    try {
        $null = Invoke-RestMethod -Uri "https://github.com" -ConnectionTimeoutSeconds 1
        Write-Debug "Test-GithubConnection: Connected to GitHub successfully."
        $Connected = $true
    }
    catch [System.Net.WebException] {
        Write-Debug "Test-GithubConnection: Network error: $($_.Exception.Message)"
    }
    catch {
        Write-Debug "Test-GithubConnection: An unexpected error occurred: $($_.Exception.Message)"
    }
    return $Connected
}
#endregion

#region Clipboard Utilities
<#
    .SYNOPSIS
    Clears the Windows clipboard.
#>
function Clear-Clipboard {
    [CmdletBinding()]
    param()

    Set-Clipboard -Value $null
}
("clearclipboard", "clearclip", "clrclip") | ForEach-Object {
    Set-Alias -Name $_ -Value Clear-Clipboard
}

function cpy { Set-Clipboard $args[0] }

function pst { Get-Clipboard }
#endregion

#region Editor Config
if (-not $env:EDITOR) {
    # For better performance, consider setting this as a persistent user environment variable once.
    $editorPriority = 'nvim', 'vim', 'vi', 'code', 'notepad++'
    $foundEditor = ($editorPriority | ForEach-Object {
        Get-Command $_ -ErrorAction SilentlyContinue
    } | Select-Object -First 1).Name

    # Set the environment variable for future sessions
    $env:EDITOR = if ($foundEditor) { $foundEditor } else { 'notepad' }
}
("vim", "vi") | ForEach-Object { 
    Set-Alias -Name $_ -Value $env:EDITOR
}

if (-not (Test-CommandExists code-insiders)) {
    Set-Alias -Name code-insiders -Value code
}
else {
    Set-Alias -Name code -Value code-insiders
}

<#
    .SYNOPSIS
    Opens the PowerShell profile in the user's preferred editor.
#>
function Edit-Profile {
    & $env:EDITOR $PROFILE
}
Set-Alias -Name ep -Value Edit-Profile

<#
    .SYNOPSIS
    Reloads the PowerShell profile.
#>
function Sync-Profile {
    Write-Debug "Reloading PowerShell profile..."
    $startTime = Get-Date
    . $PROFILE
    $endTime = Get-Date
    $loadTime = ($endTime - $startTime).TotalMilliseconds
    Write-Host "Profile reloaded in $([math]::Round($loadTime))ms." -ForegroundColor Green
}
("Refresh-Profile", "refresh", "Reload-Profile", "reload", "reset") | ForEach-Object {
    Set-Alias -Name $_ -Value Sync-Profile
}
#endregion

#region Filesystem Utilities
function Find-File {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Write-Debug "Find-File: Searching for files matching '$Name'"

    Get-ChildItem -Recurse -Filter "*$Name*" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
}
("ff", "find") | ForEach-Object {
    Set-Alias -Name $_ -Value Find-File
}

function Find-Text {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Regex,

        [Parameter(ValueFromPipeline)]
        [string[]]$Path = @()
    )

    Write-Debug "Find-Text: Searching for text matching '$Regex' in $Path"

    if ($Path.Count -eq 0) {
        $input | Select-String $Regex
    }
    else {
        Get-ChildItem $Path | Select-String $Regex
    }
}
Set-Alias -Name grep -Value Find-Text

function New-File {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [string]$Path = ".\New file",

        [Parameter(Position = 1)]
        [switch]$Hidden,

        [Parameter(Position = 2)]
        [switch]$System
    )

    process {
        try {
            Write-Debug "New-File: Creating new file at $Path"
            $NewItem = New-Item -Path $Path -ItemType File -Force
            if ($Hidden) { $NewItem.Attributes += "Hidden" }
            if ($System) { $NewItem.Attributes += "System" }
            Write-Debug "New-File: Created new file at $Path"
        }
        catch [System.UnauthorizedAccessException] {
            Write-Error "New File: You do not have the correct permissions: $_"
        }
        catch {
            Write-Error "New File: An unexpected error occurred: $_"
        }
    }
}
("newfile", "nf", "touch") | ForEach-Object {
    Set-Alias -Name $_ -Value New-File
}

function New-Folder {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [string]$Path = ".\New folder",
        [Parameter(Position = 1)]
        [switch]$Hidden,
        [Parameter(Position = 2)]
        [switch]$System
    )

    process {
        try {
            Write-Debug "New-Folder: Creating new folder at $Path"
            $NewFolder = New-Item -Path $Path -ItemType Directory -Force
            if ($Hidden) { $NewFolder.Attributes += "Hidden" }
            if ($System) { $NewFolder.Attributes += "System" }
            Write-Debug "New-Folder: Created new folder at $Path"
        }
        catch [System.UnauthorizedAccessException] {
            Write-Error "New-Folder: You do not have the correct permissions: $_" -ErrorAction Continue
            return
        }
        catch {
            Write-Error "New-Folder: An unexpected error occurred: $_" -ErrorAction Continue
            return
        }

        if ($MyInvocation.InvocationName -eq "mkcd") {
            Set-Location $Path
        }
    }
}
("mkcd", "mkdir") | ForEach-Object { 
    Set-Alias -Name $_ -Value New-Folder 
}

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

<#
    .SYNOPSIS
    Quickly extracts archive files to a specified destination, or the current directory if none is specified.

    .DESCRIPTION
    The Extract-Archive function extracts the contents of an archive file (e.g., .zip) to a specified destination directory.
    If the destination directory does not exist, it will be created. 
    If no destination is specified, the current directory will be used.

    .PARAMETER Path
    The path to the archive file to extract.

    .PARAMETER DestinationPath
    The path to extract the archive file to. If not specified, the current directory will be used.

    .PARAMETER Force
    If specified, the archive file will be overwritten if it already exists in the destination directory.

    .EXAMPLE
    Extract-Archive -Path "C:\path\to\archive.zip"
    Extracts the contents of "archive.zip" to the current directory.

    .EXAMPLE
    unzip .\archive.zip
    Extracts the contents of "archive.zip" to the current directory.
#>
function Extract-Archive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,

        [Parameter(Position=1)]
        [string]$DestinationPath = $pwd,

        [switch]$Force
    )

    $resolvedPath = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        Write-Error "unzip: File not found at '$Path'"
        return
    }

    if (-not (Test-Path $DestinationPath)) {
        Write-Verbose "Destination '$DestinationPath' not found. Creating it."
        New-Item -Path $DestinationPath -ItemType Directory | Out-Null
    }

    Write-Host "Extracting '$($resolvedPath.ProviderPath)' to '$DestinationPath'..."
    Expand-Archive -LiteralPath $resolvedPath.ProviderPath -DestinationPath $DestinationPath -Force:$Force
}
("extract", "unzip") | ForEach-Object {
    Set-Alias -Name $_ -Value Extract-Archive
}

<#
    .SYNOPSIS
    Replaces text in files or input strings using regex patterns.

    .DESCRIPTION
    The Replace-Text function allows you to replace text in files or input strings using regular expressions.

    .PARAMETER Pattern
    The regex pattern to match and replace.

    .PARAMETER Replacement
    The text to replace the matched pattern with.

    .PARAMETER Path
    The path to the file(s) to replace text in.

    .PARAMETER InputObject
    The input string to replace text in.

    .PARAMETER InPlace
    If specified, the file(s) will be modified in-place.

    .EXAMPLE
    Replace-Text -Pattern "Hello" -Replacement "World" -Path .\file.txt
    Replaces all occurrences of "Hello" with "World" in file.txt.

    .EXAMPLE
    Replace-Text -Pattern "Hello" -Replacement "World" -InputObject "Hello World"
    Replaces "Hello" with "World" in the input string "Hello World".
#>
function Replace-Text {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Pattern,

        [Parameter(Mandatory, Position = 1)]
        [string]$Replacement,

        [Parameter(Position = 2, ValueFromPipelineByPropertyName)]
        [string[]]$Path,

        [Parameter(ValueFromPipeline)]
        [string]$InputObject,

        [Parameter()]
        [switch]$InPlace
    )

    begin {
        Write-Debug "Replace-Text: Pattern='$Pattern', Replacement='$Replacement', InPlace=$InPlace, Path=$Path"
    }

    process {
        if ($PSBoundParameters.ContainsKey('Path')) {
            foreach ($file in $Path) {
                $resolvedPath = Resolve-Path -LiteralPath $file
                if ($InPlace) {
                    if ($PSCmdlet.ShouldProcess($resolvedPath, "Replace text ('$Pattern' -> '$Replacement')")) {
                        $tempFile = [System.IO.Path]::GetTempFileName()
                        $reader = [System.IO.File]::OpenText($resolvedPath)
                        $writer = [System.IO.File]::CreateText($tempFile)
                        while ($null -ne ($line = $reader.ReadLine())) {
                            $writer.WriteLine($line -replace $Pattern, $Replacement)
                        }
                        $reader.Close()
                        $writer.Close()
                        Move-Item -Path $tempFile -Destination $resolvedPath -Force
                    }
                }
                else {
                    Get-Content -Path $resolvedPath | ForEach-Object { $_ -replace $Pattern, $Replacement }
                }
            }
        }
        else {
            $InputObject -replace $Pattern, $Replacement
        }
    }
}
Set-Alias -Name sed -Value Replace-Text
#endregion

#region Git Operations
function gs { git status }
function ga { git add . }
function gp { git push }
function g { z Github }

function gcom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromRemainingArguments)]
        [string[]]$Message
    )
    git add .
    git commit -m "$Message"
}

function lazyg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromRemainingArguments)]
        [string[]]$Message
    )
    git add .
    git commit -m "$Message"
    git push
}
#endregion

#region Miscellaneous Shortcuts & Utilities
function Invoke-PeriodicTable {
    if (Test-CommandExists "periodic-table-cli") {
        periodic-table-cli
    }
    else {
        Write-Error "periodic-table-cli is not installed."
    }
}
("pt", "ptable", "ptoe") | ForEach-Object {
    Set-Alias -Name $_ -Value Invoke-PeriodicTable
}
#endregion

#region Navigation Shortcuts
function Invoke-Explorer {
    [CmdletBinding()]
    param(
        [string]$Path = "."
    )
    Start-Process -FilePath explorer.exe -ArgumentList $Path
}
("explore", "explorer", "open", "openfolder") | ForEach-Object {
    Set-Alias -Name $_ -Value Invoke-Explorer
}

function docs { Set-Location -Path $HOME\Documents }
function dtop { Set-Location -Path $HOME\Desktop }
function dl { Set-Location -Path $HOME\Downloads }
Set-Alias -Name downloads -Value dl

function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }
function ll { Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize }
#endregion

#region Networking Utilities
function Test-NetSpeed {
    if (Test-CommandExists librespeed-cli) {
        librespeed-cli $args[0]
    }
    else {
        Write-Error "Test-NetSpeed: librespeed-cli is not installed."
    }
}
("speed", "speedtest", "testspeed") | ForEach-Object {
    Set-Alias -Name $_ -Value Test-NetSpeed
}

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
    }
    catch {
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
    }
    else {
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
        [Parameter(Mandatory, ValueFromRemainingArguments, ValueFromPipeline)]
        [string[]]$NameOrPid
    )

    Begin {
        Write-Debug "Stop-ProcessByName: NameOrPid=$NameOrPid"
    }

    Process {
        foreach ($item in $NameOrPid) {
            # 1. Get the processes based on name or PID
            if ($item -match '^\d+$') {
                $processes = Get-Process -Id $item -ErrorAction SilentlyContinue
            }
            else {
                $processes = Get-Process -Name $item -ErrorAction SilentlyContinue
            }

            if ($processes) {
                $processInfo = $processes | Select-Object ProcessName, Id, Path, StartTime # Added StartTime for safety

                # 2. Use ShouldProcess for safety
                if ($PSCmdlet.ShouldProcess("Processes matching '$item'", "Stop")) {
                    Write-Host "Attempting to stop processes matching '$item'..." -ForegroundColor Cyan
                    
                    # 3. Output details BEFORE stopping (for better logging/piping)
                    Write-Output $processInfo | Format-Table -AutoSize | Out-String | Write-Host

                    try {
                        # 4. Stop the processes
                        $processes | Stop-Process -ErrorAction Stop
                        Write-Host "SUCCESS: Processes matching '$item' were stopped." -ForegroundColor Green
                    } 
                    catch {
                        Write-Host "FAILED to stop one or more processes matching '$item': $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
            else {
                Write-Warning "No active processes matching '$item' found."
            }
        }
    }
}
("pkill", "kill", "stop") | ForEach-Object {
    Set-Alias -Name $_ -Value Stop-ProcessByName
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
("up", "uptime", "get-uptime") | ForEach-Object {
    Set-Alias -Name $_ -Value Get-Uptime
}

function Get-WindowsInstallInfo {
    [CmdletBinding()]
    param()

    $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $regProps = Get-ItemProperty -Path $RegistryPath
    $InstallDateValue = $regProps.InstallDate
    $InstallDate = [System.DateTime]::UnixEpoch.AddSeconds($InstallDateValue)
    $OperationalTime = (Get-Date) - $InstallDate
    $WindowsVersion = $regProps.ProductName
    $BuildNumber = $regProps.CurrentBuildNumber
    $UBR = $regProps.UBR
    $FullBuildNumber = "$BuildNumber.$UBR"
    $Uptime = (Get-Date) - (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $Drives = Get-PSDrive -PSProvider FileSystem
    $RAM = Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
    $CPU = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1

    Write-Output ("Windows Version: {0} (Build {1})" -f $WindowsVersion, $FullBuildNumber)
    Write-Output ("Install Date: {0}" -f $InstallDate)
    Write-Output ("Operational Time: {0:N0} days, {1} hours, {2} minutes" -f $OperationalTime.TotalDays, $OperationalTime.Hours, $OperationalTime.Minutes)
    Write-Output ("System Uptime: {0:N0} days, {1} hours, {2} minutes" -f $Uptime.TotalDays, $Uptime.Hours, $Uptime.Minutes)
    Write-Output "`nDrive Space:"
    foreach ($Drive in ($Drives | Where-Object {
        $_.Name -match '^[A-Z]$' -and $_.Provider.Name -eq 'FileSystem' -and $_.Root -notlike "\\*" -and $null -ne $_.Used
    })) {
        if ($Drive.Free -and ($Drive.Used -or $Drive.Free)) {
            $FreeSpace = [math]::Round($Drive.Free / 1GB, 2)
            $TotalSpace = [math]::Round(($Drive.Used + $Drive.Free) / 1GB, 2)
            Write-Output ("Drive {0}: {1:N2} GB free of {2:N2} GB" -f $Drive.Name, $FreeSpace, $TotalSpace)
        }
    }
    Write-Output ("`nTotal RAM: {0:N2} GB" -f ($RAM.Sum / 1GB))
    Write-Output ("CPU: {0} ({1} cores)" -f $CPU.Name, $CPU.NumberOfCores)
}
("instime", "installtime") | ForEach-Object {
    Set-Alias -Name $_ -Value Get-WindowsInstallInfo
}

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
    }
    catch [System.Net.WebException] {
        Write-Error "New-Hastebin: Unexpected network error: $($_.Exception.Message)" -ErrorAction Continue
    }
    catch {
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
    }
    catch {
        Write-Error "Failed to run Python: $_" -ErrorAction Continue
    }
}

function quit { exit }
#endregion

#region Session Initialization
<# Terminal Icons (Deferred) #>
Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    Import-Module Terminal-Icons
    Unregister-Event -SourceIdentifier PowerShell.OnIdle
} | Out-Null

<# Oh-My-Posh with Caching #>
# Define theme path here
$OmpTheme = Join-Path $HOME "Documents\PowerShell\Themes\gruvbox.omp.json"
$OmpCache = Join-Path $env:TEMP "omp.cache.ps1"

# Regenerate the cache if it doesn't exist or the theme file is newer
if ((Test-Path $OmpTheme) -and ((!(Test-Path $OmpCache)) -or ((Get-Item $OmpTheme).LastWriteTime -gt (Get-Item $OmpCache).LastWriteTime))) {
    Write-Host "Generating Oh-My-Posh cache..." -ForegroundColor Yellow
    oh-my-posh init pwsh --config "$OmpTheme" | Out-File -FilePath $OmpCache -Encoding utf8
}

if (Test-Path $OmpCache) {
    . $OmpCache # Source the cache file
} else {
    Write-Warning "Oh-My-Posh theme not found at $OmpTheme. Prompt will not be customized."
}

<# Zoxide with Caching #>
if (Test-CommandExists zoxide) {
    $ZoxideCache = Join-Path $env:TEMP "zoxide.cache.ps1"

    # Regenerate the cache only if it doesn't exist (it rarely changes)
    if (-not (Test-Path $ZoxideCache)) {
        Write-Host "Generating Zoxide cache..." -ForegroundColor Yellow
        zoxide init powershell | Out-File -FilePath $ZoxideCache -Encoding utf8
    }
    . $ZoxideCache # Source the cache file
} else {
    Write-Warning "zoxide is not installed. Navigation shortcuts like 'z' will not work."
}

<# Custom Profile Loading (if it exists) #>
$CustomProfilePath = Join-Path $PSScriptRoot "Profile.ps1"
if (Test-Path $CustomProfilePath) {
    Write-Debug "Loading custom profile from $CustomProfilePath"
    . $CustomProfilePath
}
#endregion
