function Get-WindowsInstallInfo {
    <#
    .SYNOPSIS
        Reports Windows version, install date, drive space, RAM and CPU.
    .DESCRIPTION
        Reads the install date and current build from the registry, then gathers
        drive, RAM and CPU details via CIM. Runs several CIM queries and is
        therefore slow; avoid calling it from a hot path.
    .PARAMETER AsObject
        Outputs a structured PSCustomObject instead of formatted console text.
    .EXAMPLE
        Get-WindowsInstallInfo
    .EXAMPLE
        Get-WindowsInstallInfo -AsObject
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$AsObject
    )

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

    $driveReport = [System.Collections.Generic.List[object]]::new()
    foreach ($Drive in ($Drives | Where-Object {
        $_.Name -match '^[A-Z]$' -and $_.Provider.Name -eq 'FileSystem' -and $_.Root -notlike "\\*" -and $null -ne $_.Used
    })) {
        if ($Drive.Free -and ($Drive.Used -or $Drive.Free)) {
            $FreeSpace = [math]::Round($Drive.Free / 1GB, 2)
            $TotalSpace = [math]::Round(($Drive.Used + $Drive.Free) / 1GB, 2)
            $driveReport.Add([pscustomobject]@{
                Drive       = $Drive.Name
                FreeGB      = $FreeSpace
                TotalGB     = $TotalSpace
                UsedPercent = [math]::Round((($TotalSpace - $FreeSpace) / $TotalSpace) * 100, 1)
            })
        }
    }

    if ($AsObject) {
        return [pscustomobject]@{
            PSTypeName      = 'System.WindowsInstallInfo'
            WindowsVersion  = $WindowsVersion
            BuildNumber     = $BuildNumber
            FullBuildNumber = $FullBuildNumber
            InstallDate     = $InstallDate
            OperationalDays = [math]::Round($OperationalTime.TotalDays, 1)
            UptimeHours     = [math]::Round($Uptime.TotalHours, 1)
            Drives          = $driveReport.ToArray()
            TotalRamGB      = [math]::Round($RAM.Sum / 1GB, 2)
            CPU             = "$($CPU.Name) ($($CPU.NumberOfCores) cores)"
        }
    }

    Write-Output ("Windows Version: {0} (Build {1})" -f $WindowsVersion, $FullBuildNumber)
    Write-Output ("Install Date: {0}" -f $InstallDate)
    Write-Output ("Operational Time: {0:N0} days, {1} hours, {2} minutes" -f $OperationalTime.TotalDays, $OperationalTime.Hours, $OperationalTime.Minutes)
    Write-Output ("System Uptime: {0:N0} days, {1} hours, {2} minutes" -f $Uptime.TotalDays, $Uptime.Hours, $Uptime.Minutes)
    Write-Output "`nDrive Space:"
    foreach ($d in $driveReport) {
        Write-Output ("Drive {0}: {1:N2} GB free of {2:N2} GB" -f $d.Drive, $d.FreeGB, $d.TotalGB)
    }
    Write-Output ("`nTotal RAM: {0:N2} GB" -f ($RAM.Sum / 1GB))
    Write-Output ("CPU: {0} ({1} cores)" -f $CPU.Name, $CPU.NumberOfCores)
}