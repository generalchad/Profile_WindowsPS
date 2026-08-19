function Set-WinTargetVersion {
    <#
    .SYNOPSIS
        Locks the target version for Windows 11 feature updates.

    .DESCRIPTION
        This script sets the target version for Windows 11 updates using registry keys.
        It requires administrative privileges to modify the HKLM registry hive.

    .PARAMETER TargetVersion
        The target version to set. Valid values are "23H2", "24H2", or "25H2".

    .EXAMPLE
        Set-WinTargetVersion -TargetVersion "24H2"
        Locks the local machine's feature update target to Windows 11 24H2.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("23H2", "24H2", "25H2")]
        [string]$TargetVersion
    )

    $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $registrySettings = @{
        'ProductVersion'           = @{ Type = 'String'; Value = 'Windows 11' }
        'TargetReleaseVersion'     = @{ Type = 'DWord';  Value = 1 }
        'TargetReleaseVersionInfo' = @{ Type = 'String'; Value = $TargetVersion }
    }

    try {
        # Test for admin rights
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
        if (-not $isAdmin) {
            Write-Error "Administrator privileges are required to modify HKLM registry paths."
            return
        }

        # Create registry path if it doesn't exist
        if (-not (Test-Path $registryPath)) {
            if ($PSCmdlet.ShouldProcess($registryPath, "Create registry key")) {
                New-Item -Path $registryPath -Force | Out-Null
            }
        }

        # Set registry values using New-ItemProperty for PS5.1/PS7 cross-compatibility
        foreach ($setting in $registrySettings.GetEnumerator()) {
            if ($PSCmdlet.ShouldProcess("$registryPath\$($setting.Key)", "Set to '$($setting.Value.Value)' ($($setting.Value.Type))")) {
                New-ItemProperty -Path $registryPath -Name $setting.Key -Value $setting.Value.Value -PropertyType $setting.Value.Type -Force | Out-Null
            }
        }

        Write-Host "Successfully set Windows 11 target version to $TargetVersion" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to set target version: $_"
    }
}
