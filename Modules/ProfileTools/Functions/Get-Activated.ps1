function Get-Activated {
<#
.SYNOPSIS
    Get-Activated - Invokes the Microsoft Activation Script (MAS) installer to solve activation issues.

.DESCRIPTION
    Get-Activated is a function that downloads and invokes the Microsoft Activation Script (MAS) installer to solve activation issues.

.PARAMETER MASInstallerPath
    The path to the MAS installer. Defaults to "https://get.activated.win".
#>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [Alias("path")]
        [string]$MASInstallerPath = "https://get.activated.win"
    )
    Write-Verbose "Get-Activated: Launching MAS installer..."
    try {
        Invoke-RestMethod $MASInstallerPath | Invoke-Expression
        Write-Verbose "Get-Activated: Successfully launched MAS installer."
    } catch [System.Net.WebException] {
        Write-Error "Get-Activated: Failed due to network error: $_"
    } catch {
        Write-Error "Get-Activated: Failed to launch MAS installer: $_"
    }
}
