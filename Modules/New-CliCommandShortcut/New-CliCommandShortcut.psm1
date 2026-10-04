#Requires -Version 7.2

Set-StrictMode -Version Latest

# Classification is a deny-list rather than an allow-list: an unrecognised
# command (git, npm, docker, a user function) is allowed. Only commands known
# to mutate or destroy state are rejected, and the search walks further back
# through history until a safe entry is found.
$script:DestructiveVerbs = @(
    'Remove', 'Delete', 'Erase', 'Format', 'Clear', 'Reset', 'Restart',
    'Stop', 'Disable', 'Uninstall', 'Destroy', 'Drop', 'Kill', 'Terminate',
    'Revoke', 'Deny', 'Block', 'Suspend'
)

$script:DestructiveCommands = @(
    'rm', 'ri', 'rd', 'rmdir', 'del', 'erase', 'format', 'diskpart',
    'shutdown', 'logoff', 'kill', 'taskkill', 'reg', 'cipher'
)

# Harmless members of the denied verb families (and their aliases). Without
# these every Format-Table or Clear-Host would force the search further back.
$script:SafeExceptions = @(
    'Clear-Host', 'cls', 'clear', 'Clear-History',
    'Format-Table', 'Format-List', 'Format-Wide', 'Format-Custom', 'Format-Hex',
    'Stop-Transcript'
)

# PSReadLine rewrites the whole file on exit, so only the tail is relevant and
# a bounded read keeps the cmdlet fast on a multi-megabyte history.
$script:HistoryTailLines = 500

function New-CliShortcutError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string]$ErrorId,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorCategory]$Category
    )

    return [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new($Message),
        $ErrorId,
        $Category,
        $null
    )
}

function Resolve-CliHistoryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Override
    )

    if ($Override) { return $Override }

    if (Get-Module -Name PSReadLine -ErrorAction SilentlyContinue) {
        try {
            $savePath = (Get-PSReadLineOption).HistorySavePath
            if ($savePath) { return $savePath }
        }
        catch {
            # Fall through to the default location when the option is unavailable.
        }
    }

    return Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt'
}

function Get-CliShortcutFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $safe = $Command -replace '[<>:"/\\|?*\x00-\x1F]', '_'
    $safe = ($safe -replace '\s+', ' ').Trim().TrimEnd('.')
    if ($safe.Length -gt 80) { $safe = $safe.Substring(0, 80).Trim() }
    if (-not $safe) { $safe = 'Cli command' }

    return "$safe.lnk"
}

function Resolve-CliShortcutPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$LeafName
    )

    if (-not $Path) {
        return Join-Path ([Environment]::GetFolderPath('Desktop')) $LeafName
    }

    $isContainer = Test-Path -LiteralPath $Path -PathType Container
    $looksLikeDirectory = -not $isContainer -and ($Path -match '[\\/]\s*$')
    if ($isContainer -or $looksLikeDirectory) {
        return Join-Path $Path $LeafName
    }

    if ([System.IO.Path]::GetExtension($Path) -eq '.lnk') { return $Path }
    return "$Path.lnk"
}

function Test-CliDestructiveCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string[]]$ExtraPatterns
    )

    if ($Name -in $script:SafeExceptions) { return $false }

    foreach ($pattern in $script:DestructiveCommands) {
        if ($Name -like $pattern) { return $true }
    }

    foreach ($pattern in $ExtraPatterns) {
        if ($Name -like $pattern) { return $true }
    }

    # [regex] rather than -match so the caller's automatic $Matches is untouched.
    $verbMatch = [regex]::Match($Name, '^(?<verb>[A-Za-z]+)-')
    if ($verbMatch.Success -and ($verbMatch.Groups['verb'].Value -in $script:DestructiveVerbs)) {
        return $true
    }

    return $false
}

function Find-CliLastSafeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Lines,

        [Parameter(Mandatory = $false)]
        [string[]]$Exclude
    )

    if (-not $Lines) { return $null }

    for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
        $candidate = $Lines[$i].Trim()
        if (-not $candidate -or $candidate.StartsWith('#')) { continue }

        # A multi-line command is stored across several lines; only the final
        # line is seen here, and it usually does not parse on its own. Requiring
        # a clean parse skips those fragments rather than building a broken link.
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($candidate, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { continue }

        $commandAsts = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        if ($commandAsts.Count -eq 0) { continue }

        $isDestructive = $false
        foreach ($commandAst in $commandAsts) {
            $name = $commandAst.GetCommandName()
            if (-not $name) { continue }
            $leaf = ($name -split '\\')[-1]
            if (Test-CliDestructiveCommand -Name $leaf -ExtraPatterns $Exclude) {
                $isDestructive = $true
                break
            }
        }
        if ($isDestructive) { continue }

        return $candidate
    }

    return $null
}

function New-CliShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShortcutPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [string]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $shell = $null
    $link = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($ShortcutPath)
        $link.TargetPath = $TargetPath
        $link.Arguments = $Arguments
        $link.WorkingDirectory = $WorkingDirectory
        $link.Description = $Description
        $link.IconLocation = "$TargetPath,0"
        $link.Save()
    }
    finally {
        if ($link) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($link) }
        if ($shell) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    }
}

function New-CliCommandShortcut {
    <#
    .SYNOPSIS
        Creates a .lnk that re-runs the most recent non-destructive CLI command.

    .DESCRIPTION
        Reads the PSReadLine history file, walks backwards from the newest entry,
        and bakes the first command that is both parseable and non-destructive
        into a Windows shortcut. Double-clicking the shortcut launches pwsh and
        re-runs that command in the captured working directory, with the normal
        profile loaded.

        Destructive commands are filtered by a deny-list of verbs (Remove, Format,
        Clear, Reset, Stop, Restart, Disable, Uninstall, ...) and native tools
        (rm, del, rmdir, format, diskpart, shutdown, taskkill, ...), with harmless
        members such as Format-Table and Clear-Host excepted. Multi-line and
        unparseable history fragments are skipped. Use -Exclude to extend the
        deny-list.

    .PARAMETER Path
        Where to write the shortcut: either a directory (an existing one, or a
        path ending in a slash) or a full .lnk path. Defaults to the current
        user's Desktop.

    .PARAMETER Name
        The shortcut file name. Defaults to the selected command, sanitised and
        truncated. A .lnk extension is added when missing.

    .PARAMETER HistoryPath
        The PSReadLine history file to read. Defaults to the configured
        HistorySavePath, or the standard ConsoleHost_history.txt.

    .PARAMETER Exclude
        Additional command-name wildcard patterns to treat as destructive and
        skip, e.g. 'Invoke-Deploy*'.

    .PARAMETER WorkingDirectory
        The shortcut's start-in directory. Defaults to the current location.

    .PARAMETER CloseWhenDone
        Close the console when the command finishes. By default the window stays
        open so the output is visible.

    .PARAMETER Force
        Overwrite an existing shortcut at the target path.

    .OUTPUTS
        PSCustomObject with ShortcutPath, Command, TargetPath, Arguments,
        WorkingDirectory, and HistoryPath.

    .EXAMPLE
        New-CliCommandShortcut

        Creates a Desktop shortcut to the last non-destructive command.

    .EXAMPLE
        New-CliCommandShortcut -Path . -Name 'last-run' -Force

        Writes .\last-run.lnk next to the current directory, overwriting it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias('Destination')]
        [string]$Path,

        [Parameter(Position = 1)]
        [string]$Name,

        [Parameter()]
        [string]$HistoryPath,

        [Parameter()]
        [string[]]$Exclude,

        [Parameter()]
        [string]$WorkingDirectory,

        [Parameter()]
        [switch]$CloseWhenDone,

        [Parameter()]
        [switch]$Force
    )

    $historyFile = Resolve-CliHistoryPath -Override $HistoryPath
    if (-not (Test-Path -LiteralPath $historyFile -PathType Leaf)) {
        $PSCmdlet.ThrowTerminatingError((New-CliShortcutError `
            -Message "PSReadLine history file not found: $historyFile" `
            -ErrorId 'HistoryFileNotFound' `
            -Category ([System.Management.Automation.ErrorCategory]::ObjectNotFound)))
    }

    $lines = @(Get-Content -LiteralPath $historyFile -Tail $script:HistoryTailLines -ErrorAction Stop)
    $command = Find-CliLastSafeCommand -Lines $lines -Exclude $Exclude
    if (-not $command) {
        $PSCmdlet.ThrowTerminatingError((New-CliShortcutError `
            -Message "No non-destructive command was found in the last $($script:HistoryTailLines) history entries." `
            -ErrorId 'NoSafeCommandFound' `
            -Category ([System.Management.Automation.ErrorCategory]::ObjectNotFound)))
    }

    $leafName = if ($Name) {
        if ($Name -match '\.lnk$') { $Name } else { "$Name.lnk" }
    }
    else {
        Get-CliShortcutFileName -Command $command
    }
    $shortcutPath = Resolve-CliShortcutPath -Path $Path -LeafName $leafName

    $parent = Split-Path -Path $shortcutPath -Parent
    if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) {
        $PSCmdlet.ThrowTerminatingError((New-CliShortcutError `
            -Message "The shortcut's parent directory does not exist: $parent" `
            -ErrorId 'ShortcutDirectoryNotFound' `
            -Category ([System.Management.Automation.ErrorCategory]::ObjectNotFound)))
    }

    if ((Test-Path -LiteralPath $shortcutPath) -and -not $Force) {
        $PSCmdlet.ThrowTerminatingError((New-CliShortcutError `
            -Message "A shortcut already exists at '$shortcutPath'. Use -Force to overwrite it." `
            -ErrorId 'ShortcutAlreadyExists' `
            -Category ([System.Management.Automation.ErrorCategory]::ResourceExists)))
    }

    $pwsh = (Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) { $pwsh = Join-Path $PSHOME 'pwsh.exe' }
    if (-not (Test-Path -LiteralPath $pwsh -PathType Leaf)) {
        $PSCmdlet.ThrowTerminatingError((New-CliShortcutError `
            -Message "Could not locate pwsh.exe to target the shortcut." `
            -ErrorId 'PwshNotFound' `
            -Category ([System.Management.Automation.ErrorCategory]::ObjectNotFound)))
    }

    if ($PSBoundParameters.ContainsKey('WorkingDirectory')) {
        if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
            $PSCmdlet.ThrowTerminatingError((New-CliShortcutError `
                -Message "WorkingDirectory is not an existing directory: $WorkingDirectory" `
                -ErrorId 'WorkingDirectoryNotFound' `
                -Category ([System.Management.Automation.ErrorCategory]::ObjectNotFound)))
        }
        $workDir = (Resolve-Path -LiteralPath $WorkingDirectory).ProviderPath
    }
    else {
        $workDir = $PWD.ProviderPath
    }

    # -EncodedCommand avoids the quoting hazards of embedding an arbitrary
    # command line in a .lnk's Arguments field.
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
    $argumentParts = @('-NoLogo')
    if (-not $CloseWhenDone) { $argumentParts += '-NoExit' }
    $argumentParts += @('-EncodedCommand', $encodedCommand)
    $arguments = $argumentParts -join ' '

    $description = "Runs the last non-destructive CLI command: $command"
    if ($description.Length -gt 260) { $description = $description.Substring(0, 257) + '...' }

    New-CliShortcut -ShortcutPath $shortcutPath -TargetPath $pwsh -Arguments $arguments `
        -WorkingDirectory $workDir -Description $description

    [PSCustomObject]@{
        ShortcutPath     = $shortcutPath
        Command          = $command
        TargetPath       = $pwsh
        Arguments        = $arguments
        WorkingDirectory = $workDir
        HistoryPath      = $historyFile
    }
}

Export-ModuleMember -Function 'New-CliCommandShortcut'
