function Invoke-Titus {
<#
.SYNOPSIS
    Invoke-Titus - Invokes the Chris Titus Tech Windows Utility installer.

.DESCRIPTION
    Invoke-Titus is a function that downloads and invokes the Chris Titus Tech Windows Utility installer.
    By default, it launches the stable version. Use the -Unstable switch to launch the development version.

.PARAMETER Unstable
    When specified, launches the unstable/development version of the utility from https://christitus.com/windev.
    Otherwise, launches the stable version from https://christitus.com/win.

.EXAMPLE
    Invoke-Titus
    Launches the stable version of the Chris Titus Tech Windows Utility.

.EXAMPLE
    Invoke-Titus -Unstable
    Launches the unstable/development version of the Chris Titus Tech Windows Utility.
#>
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]$Unstable
    )

    $url = if ($Unstable) {
        "https://christitus.com/windev"
    } else {
        "https://christitus.com/win"
    }

    $version = if ($Unstable) { "unstable" } else { "stable" }

    Write-Verbose "Invoke-Titus: Launching Chris Titus Tech Windows Utility ($version version)..."
    try {
        Invoke-RestMethod $url | Invoke-Expression
        Write-Verbose "Invoke-Titus: Successfully launched Chris Titus Tech Windows Utility."
    } catch [System.Net.WebException] {
        Write-Error "Invoke-Titus: Failed due to network error: $_"
    } catch {
        Write-Error "Invoke-Titus: Failed to launch Chris Titus Tech Windows Utility: $_"
    }
}
