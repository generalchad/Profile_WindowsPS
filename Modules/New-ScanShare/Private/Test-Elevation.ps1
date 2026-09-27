function Test-Elevation {
    <#
    .SYNOPSIS
        Returns $true when the current session is running elevated (Administrator).

    .DESCRIPTION
        Uses the Windows principal of the current identity. On non-Windows platforms
        (where this module has nothing useful to do anyway) it returns $false.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
        return $false
    }

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        Write-Verbose "Elevation check failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-ElevationHint {
    <#
    .SYNOPSIS
        Builds a copy/paste-ready command that relaunches the current host elevated.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $hostExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    "Start-Process $hostExe -Verb RunAs"
}
