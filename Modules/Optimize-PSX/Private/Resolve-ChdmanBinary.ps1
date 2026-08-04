function Resolve-ChdmanBinary {
    <#
    .SYNOPSIS
        Locates the chdman executable and probes its version.
    .DESCRIPTION
        Accepts a bare command name resolved through PATH or an explicit path to
        the executable. The reported version determines whether the createdvd
        subcommand is available.

        Version probing runs chdman with no arguments, which prints the banner
        and usage to stdout and exits non-zero. A non-zero exit is therefore
        expected and not treated as failure.
    .PARAMETER Path
        Command name or full path to chdman.
    .OUTPUTS
        PSCustomObject:
          Found          whether the executable was located
          Path           resolved executable path
          Version        parsed version, or $null when unparseable
          SupportsDvd    whether createdvd is available
          Banner         first line of chdman's own output
          Error          failure detail when Found is false
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    $result = [pscustomobject]@{
        PSTypeName  = 'Optimize-PSX.ChdmanInfo'
        Found       = $false
        Path        = $null
        Version     = $null
        SupportsDvd = $false
        Banner      = $null
        Error       = $null
    }

    # An explicit path is tested directly; anything else goes through PATH
    # resolution so 'chdman' keeps working as a bare command name.
    if ($Path -match '[\\/]' -or [System.IO.Path]::IsPathRooted($Path)) {
        if ([System.IO.File]::Exists($Path)) {
            $result.Path = [System.IO.Path]::GetFullPath($Path)
            $result.Found = $true
        } else {
            $result.Error = "Executable not found at '$Path'."
            return $result
        }
    } else {
        $command = Get-Command -Name $Path -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command) {
            $result.Path = $command.Source
            $result.Found = $true
        } else {
            $result.Error = "'$Path' was not found on PATH."
            return $result
        }
    }

    try {
        $output = & $result.Path 2>&1 | Select-Object -First 3
        $banner = ($output | Where-Object { $_ -match 'chdman' } | Select-Object -First 1)

        if ($banner) {
            $result.Banner = $banner.ToString().Trim()
            $match = [regex]::Match($result.Banner, $script:RegexChdmanVersion)
            if ($match.Success) {
                $result.Version = [version]$match.Groups['Version'].Value
                $result.SupportsDvd = ($result.Version -ge $script:ChdmanMinVersionForDvd)
            }
        }
    } catch {
        # Version detection is advisory. A binary that cannot be probed is still
        # usable for createcd, which covers every CD-based platform.
        Write-OpsxLog "Could not determine chdman version: $($_.Exception.Message)" -Level Detail
    }

    return $result
}
