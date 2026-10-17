function Get-ScanSharePathRestriction {
    <#
    .SYNOPSIS
        Returns why a folder must not become a scan share, or $null when it may.

    .DESCRIPTION
        New-ScanShare breaks NTFS inheritance on the target, strips the broad
        identities (Users, Authenticated Users, ...) and grants the scan account
        Modify, which flows down to every child that inherits. On a system or
        profile folder that would lock out normal users and hand a never-expiring
        network credential write access to OS binaries or a user's whole profile,
        so those locations are refused outright:

          * anything at or inside the Windows, Program Files, and ProgramData folders
          * the profiles directory itself (C:\Users) and any of its ancestors
          * a profile root (C:\Users\<name>) or a folder directly inside it
            (Documents, Desktop, Downloads, AppData, ...)
          * anything inside a profile's AppData

        A dedicated folder deeper in a profile (C:\Users\<name>\Documents\Scans) or
        anywhere else on a data drive is allowed.

    .PARAMETER Path
        Fully resolved folder path, without a trailing separator.

    .PARAMETER SystemRoot
        Folders that may not contain the share. Defaults to the Windows, Program
        Files, and ProgramData folders of this machine.

    .PARAMETER ProfilesRoot
        The folder that holds user profiles. Defaults to the ProfileList
        ProfilesDirectory value (normally C:\Users).

    .OUTPUTS
        System.String. The refusal reason, or $null when the path is allowed.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string[]]$SystemRoot,
        [Parameter()][string]$ProfilesRoot
    )

    if (-not $PSBoundParameters.ContainsKey('SystemRoot')) {
        $SystemRoot = @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramData)
    }
    if (-not $PSBoundParameters.ContainsKey('ProfilesRoot')) {
        $ProfilesRoot = $null
        try {
            $profileList = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -Name ProfilesDirectory -ErrorAction Stop
            $ProfilesRoot = [System.Environment]::ExpandEnvironmentVariables($profileList.ProfilesDirectory)
        }
        catch {
            if ($env:USERPROFILE) { $ProfilesRoot = Split-Path -Path $env:USERPROFILE -Parent }
        }
    }

    $separators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $normalize = { param([string]$p) [System.IO.Path]::GetFullPath($p).TrimEnd($separators) }
    $isWithin = {
        param([string]$child, [string]$parent)
        $child.Equals($parent, [System.StringComparison]::OrdinalIgnoreCase) -or
        $child.StartsWith($parent + '\', [System.StringComparison]::OrdinalIgnoreCase)
    }

    $target = & $normalize $Path

    foreach ($root in @($SystemRoot | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $rootPath = & $normalize $root
        if (& $isWithin $target $rootPath) {
            return "'$target' is inside the protected system folder '$rootPath'."
        }
        if (& $isWithin $rootPath $target) {
            return "'$target' contains the protected system folder '$rootPath'."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ProfilesRoot)) {
        $profilesPath = & $normalize $ProfilesRoot
        if (& $isWithin $profilesPath $target) {
            return "'$target' contains the user profiles folder '$profilesPath'."
        }
        if (& $isWithin $target $profilesPath) {
            $relative = $target.Substring($profilesPath.Length).TrimStart($separators)
            $segments = @($relative -split '\\' | Where-Object { $_ })
            if ($segments.Count -eq 1) {
                return "'$target' is a user profile folder."
            }
            if ($segments.Count -eq 2) {
                return "'$target' is a top-level folder of a user profile; use a dedicated subfolder such as '$target\Scans'."
            }
            if ($segments[1] -eq 'AppData') {
                return "'$target' is inside a user profile's AppData folder."
            }
        }
    }

    return $null
}
