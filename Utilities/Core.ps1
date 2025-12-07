function Test-CommandExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    $exists = $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
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
    }
    catch [System.Net.WebException] {
        Write-Debug "Test-GithubConnection: Network error: $($_.Exception.Message)"
    }
    catch {
        Write-Debug "Test-GithubConnection: An unexpected error occurred: $($_.Exception.Message)"
    }
    return $Connected
}

function Clear-Clipboard {
    [CmdletBinding()]
    param()
    Set-Clipboard -Value $null
}

function Edit-Profile {
    & $env:EDITOR $PROFILE
}

function Sync-Profile {
    Write-Debug "Reloading PowerShell profile..."
    $startTime = Get-Date
    . $PROFILE
    $endTime = Get-Date
    $loadTime = ($endTime - $startTime).TotalMilliseconds
    Write-Host "Profile reloaded in $([math]::Round($loadTime))ms." -ForegroundColor Green
}

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
                $processInfo = $processes | Select-Object ProcessName, Id, Path, StartTime 

                # 2. Use ShouldProcess for safety
                if ($PSCmdlet.ShouldProcess("Processes matching '$item'", "Stop")) {
                    Write-Host "Attempting to stop processes matching '$item'..." -ForegroundColor Cyan
                    
                    Write-Output $processInfo | Format-Table -AutoSize | Out-String | Write-Host

                    try {
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

function Invoke-Explorer {
    [CmdletBinding()]
    param(
        [string]$Path = "."
    )
    Start-Process -FilePath explorer.exe -ArgumentList $Path
}

function Invoke-PeriodicTable {
    if (Test-CommandExists "periodic-table-cli") {
        periodic-table-cli
    }
    else {
        Write-Error "periodic-table-cli is not installed."
    }
}

# --- PowerShell Updates ---
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