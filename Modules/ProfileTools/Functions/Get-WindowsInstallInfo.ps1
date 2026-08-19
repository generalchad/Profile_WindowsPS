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