function Get-CustomModule {
    <#
    .SYNOPSIS
        Lists the profile's custom modules and their exported commands.

    .DESCRIPTION
        Enumerates the modules in the profile's Modules directory and reports each
        one's version, description, exported commands, and aliases, read straight from
        its manifest. Nothing is imported, so this costs no more than the manifest reads.

        Third-party modules that ship alongside the profile (7Zip4Powershell,
        Microsoft.PowerToys.Configure) are excluded because they are not profile code.

    .PARAMETER Name
        Filters modules by name. Accepts wildcards.

    .EXAMPLE
        Get-CustomModule

    .EXAMPLE
        Get-CustomModule -Name '*Print*' | Format-List *
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [SupportsWildcards()]
        [string[]]$Name = '*'
    )

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    if (-not $moduleRoot) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.IO.DirectoryNotFoundException]::new('Could not resolve the profile Modules directory.'),
            'ModulesDirectoryNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    # Not profile code; shipped for external tools. Kept in Modules/ so autoload finds them.
    $ignored = @('7Zip4Powershell', 'Microsoft.PowerToys.Configure')

    $wildcardPatterns = [System.Management.Automation.WildcardPattern[]]@($Name)
    if ($wildcardPatterns.Count -eq 0) { return }

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($dir in [System.IO.Directory]::GetDirectories($moduleRoot)) {
        $moduleName = [System.IO.Path]::GetFileName($dir)
        if ($moduleName -in $ignored) { continue }
        if (-not ($wildcardPatterns | Where-Object { $_.IsMatch($moduleName) })) { continue }

        $manifest = Get-ChildItem -LiteralPath $dir -Filter '*.psd1' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $manifest) { continue }

        $data = Import-PowerShellDataFile -LiteralPath $manifest.FullName -ErrorAction SilentlyContinue
        if (-not $data) { continue }

        # New-ModuleManifest defaults CmdletsToExport to '*' even for pure-script
        # modules, so drop the wildcard rather than report it as a command.
        $commands = @($data.FunctionsToExport) + @($data.CmdletsToExport) |
            Where-Object { $_ -is [string] -and $_ -ne '*' }
        $aliases = @($data.AliasesToExport) | Where-Object { $_ -is [string] }

        $results.Add([PSCustomObject]@{
            Name        = $moduleName
            Version     = $data.ModuleVersion
            Commands    = ($commands -join ', ')
            Aliases     = ($aliases -join ', ')
            Description = $data.Description
            Path        = $dir
        })
    }

    $results
}
