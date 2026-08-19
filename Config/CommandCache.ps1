# -----------------------------------------------------------------------------
# Config/CommandCache.ps1 - PATH-keyed command resolution cache
# -----------------------------------------------------------------------------
# A single Get-Command miss scans every directory on $env:PATH and costs ~105ms.
# This profile probes ~8 commands at startup, most of which miss on any given
# machine, so those misses were responsible for ~800ms of load time.
#
# Instead we resolve every command we care about ONCE, persist the results (hits
# AND misses) to a cache file, and on subsequent loads just read the file back.
# The cache is invalidated only when $env:PATH changes, so installing a new tool
# self-heals on the next shell. Regeneration is the one ~700ms path, and it runs
# roughly once per PATH change rather than on every single launch.

$script:PwshEnvCommandNames = @(
    'nvim', 'vim', 'vi',
    'code-insiders.cmd', 'code-insiders', 'code.cmd', 'code', 'notepad++',
    'ntop', 'grep', 'sed',
    'oh-my-posh', 'zoxide'
)

$script:PwshEnvCacheFile = Join-Path $env:TEMP 'pwsh-env.cache.ps1'

function Get-PwshEnvPathHash {
    $input = $env:PATH + [IO.Path]::PathSeparator + $env:PATHEXT
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($input)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

function Update-PwshEnvCache {
    $hash = Get-PwshEnvPathHash
    $data = @{}
    foreach ($name in $script:PwshEnvCommandNames) {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        # Empty string == "not found" (a miss is a first-class, cached result).
        $data[$name] = if ($cmd) { $cmd.Source } else { '' }
    }

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
