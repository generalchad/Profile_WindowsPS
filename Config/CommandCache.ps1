# -----------------------------------------------------------------------------
# Config/CommandCache.ps1 - PATH-keyed command resolution cache
# -----------------------------------------------------------------------------
# A single Get-Command miss costs ~105ms: after scanning $env:PATH it falls through
# to module auto-discovery. This profile probes 13 commands at startup, most of
# which miss on any given machine.
#
# Instead we resolve every command we care about ONCE, persist the results (hits
# AND misses) to a cache file, and on subsequent loads just read the file back.
# The cache is invalidated when $env:PATH changes, so installing a new tool
# self-heals on the next shell.
#
# The cache is a single slot, and shells do NOT all share one PATH: a long-lived
# parent (Windows Terminal, VS Code, an agent harness) keeps the PATH it started
# with. Two such shells evict each other on every launch, so regeneration has to
# be cheap too - it must never go back through Get-Command.

$script:PwshEnvCommandNames = @(
    'nvim', 'vim', 'vi',
    'code-insiders.cmd', 'code-insiders', 'code.cmd', 'code', 'notepad++',
    'ntop', 'grep', 'sed',
    'oh-my-posh', 'zoxide'
)

# Every shell, elevated ones included, dot-sources the startup caches, so they stay
# out of %TEMP%: it is the usual drop zone for installers and malware and far less
# watched than LOCALAPPDATA. The loader and ProfileTools read this same folder.
$script:ProfileCacheDirectory = Join-Path $env:LOCALAPPDATA 'PowerShell\ProfileCache'
[void][System.IO.Directory]::CreateDirectory($script:ProfileCacheDirectory)
$script:PwshEnvCacheFile = Join-Path $script:ProfileCacheDirectory 'pwsh-env.cache.ps1'

function Get-PwshEnvPathHash {
    $searchSpace = $env:PATH + [IO.Path]::PathSeparator + $env:PATHEXT
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($searchSpace)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

function Find-PathApplication {
    <#
    .SYNOPSIS
        Resolves command names against $env:PATH without Get-Command.

    .DESCRIPTION
        Applies Get-Command's precedence for applications: the first PATH directory
        holding a match wins; within it, $env:PATHEXT order, then the bare name.
        A name that already carries a PATHEXT extension is matched exactly.

    .OUTPUTS
        Hashtable of name -> absolute path. An empty string means "not on PATH".
    #>
    param([Parameter(Mandatory = $true)][string[]]$Name)

    $extensions = @($env:PATHEXT -split ';' | Where-Object { $_ })
    $candidateFileNames = @{}
    $resolved = @{}
    foreach ($requested in $Name) {
        $resolved[$requested] = ''
        $candidateFileNames[$requested] =
            if ($extensions -contains [System.IO.Path]::GetExtension($requested)) { @($requested) }
            else { @($extensions | ForEach-Object { "$requested$_" }) + $requested }
    }

    # PATH holds thousands of files and a PowerShell loop over them costs ~30us per
    # file. One regex pass per directory leaves only the few plausible files for
    # the precedence check below.
    $escapedNames = ($Name | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $plausibleFile = "[\\/](?:$escapedNames)(?:\.[^.\\/]+)?$"

    foreach ($directory in $env:PATH -split [System.IO.Path]::PathSeparator) {
        if (-not $directory) { continue }
        # PATH routinely carries stale or unreadable entries.
        try { $files = [System.IO.Directory]::GetFiles($directory) } catch { continue }

        $pathByFileName = @{}
        foreach ($file in $files -match $plausibleFile) {
            $pathByFileName[[System.IO.Path]::GetFileName($file)] = $file
        }
        if ($pathByFileName.Count -eq 0) { continue }

        foreach ($requested in $Name) {
            if ($resolved[$requested]) { continue }
            foreach ($fileName in $candidateFileNames[$requested]) {
                if ($pathByFileName.ContainsKey($fileName)) {
                    $resolved[$requested] = $pathByFileName[$fileName]
                    break
                }
            }
        }
    }

    return $resolved
}

function Update-PwshEnvCache {
    $hash = Get-PwshEnvPathHash
    # Empty string == "not found" (a miss is a first-class, cached result).
    $data = Find-PathApplication -Name $script:PwshEnvCommandNames

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("`$global:PwshEnvCacheHash = '$hash'")
    [void]$sb.AppendLine('$global:PwshEnvCache = @{')
    foreach ($name in $script:PwshEnvCommandNames) {
        $v = ($data[$name]).Replace("'", "''")
        [void]$sb.AppendLine("    '$name' = '$v'")
    }
    [void]$sb.AppendLine('}')
    [System.IO.File]::WriteAllText($script:PwshEnvCacheFile, $sb.ToString(), [System.Text.Encoding]::UTF8)

    $global:PwshEnvCacheHash = $hash
    $global:PwshEnvCache = $data
}

function Resolve-CachedCommand {
    <#
    .SYNOPSIS
        Returns the absolute Source path for a command, or $null if it is not on
        $env:PATH. Results (including misses) are cached and invalidated only when
        $env:PATH changes.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    $hash = Get-PwshEnvPathHash

    # Populate from the persisted cache file once per session (if we haven't yet).
    if (-not $global:PwshEnvCacheHash) {
        if (Test-Path -LiteralPath $script:PwshEnvCacheFile) {
            try { . $script:PwshEnvCacheFile } catch { $global:PwshEnvCache = $null }
        }
    }

    # Regenerate only if absent or stale ($env:PATH changed).
    if (-not $global:PwshEnvCache -or $global:PwshEnvCacheHash -ne $hash) {
        Update-PwshEnvCache
    }

    $value = $global:PwshEnvCache[$Name]
    if ([string]::IsNullOrEmpty($value)) { return $null }
    return $value
}
