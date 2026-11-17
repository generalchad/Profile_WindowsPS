# -----------------------------------------------------------------------------
# Microsoft.PowerShell_profile.ps1 - The Optimized Loader
#
# Authored by Timothy W. Brown with the assistance of large language models,
# including Anthropic Claude, Google Gemini, and DeepSeek.
#
# Licensed under the Apache License, Version 2.0 (see LICENSE and NOTICE).
# -----------------------------------------------------------------------------
$ProfileLoadSw = [System.Diagnostics.Stopwatch]::StartNew()

$ProfileRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PROFILE) { Split-Path -Parent $PROFILE } else { $PSScriptRoot }
if (-not $ProfileRoot) { $ProfileRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

# -----------------------------------------------------------------------------
# 0. Optional load tracing.  Set $env:PROFILE_TRACE=1 before launching pwsh to
#    emit a per-stage breakdown.  Costs nothing when the variable is unset.
#      $env:PROFILE_TRACE=1; pwsh -NoLogo -Command exit
#      Get-Content $env:TEMP\pwsh-profile-trace.log -Tail 20
# -----------------------------------------------------------------------------
$ProfileTrace = [bool]$env:PROFILE_TRACE
if ($ProfileTrace) {
    # State lives in a hashtable so Mark can mutate it by reference regardless of
    # whether this profile is dot-sourced into global scope or re-sourced later.
    $ProfileTraceState = @{
        Sw    = $ProfileLoadSw
        Last  = 0.0
        Marks = [System.Collections.Generic.List[object]]::new()
    }
    function Mark {
        param([string]$Stage)
        $s = $ProfileTraceState
        $t = $s.Sw.Elapsed.TotalMilliseconds
        $s.Marks.Add([pscustomobject]@{
            Stage   = $Stage
            Ms      = [math]::Round($t - $s.Last, 1)
            TotalMs = [math]::Round($t, 1)
        })
        $s.Last = $t
    }
}

# 1. Load Settings (Theme, Editor, PSReadline)
$ConfigPath = Join-Path $ProfileRoot "Config"
if (Test-Path $ConfigPath) {
    # CommandCache.ps1 must be loaded FIRST: Settings.ps1 and Aliases.ps1 both
    # depend on Resolve-CachedCommand to avoid slow Get-Command probes.
    $CommandCacheFile = Join-Path $ConfigPath "CommandCache.ps1"
    if (Test-Path $CommandCacheFile) {
        try { . $CommandCacheFile } catch { Write-Warning "Failed to load command cache: $_" }
    }

    # Using high-performance .NET file enumeration to skip Get-ChildItem object overhead
    # Excluding Aliases.ps1 (loaded last in Step 3) and CommandCache.ps1 (loaded above).
    foreach ($File in [System.IO.Directory]::GetFiles($ConfigPath, "*.ps1")) {
        $Name = [System.IO.Path]::GetFileName($File)
        if ($Name -eq "Aliases.ps1" -or $Name -eq "CommandCache.ps1") { continue }
        try {
            . $File
        } catch {
            Write-Warning "Failed to load config $($File): $_"
        }
    }
}
if ($ProfileTrace) { Mark 'Config' }

# 2. Functions and utilities live in the ProfileTools module (Modules/ProfileTools).
#    Its manifest declares the exported commands, so they autoload on first use
#    instead of being dot-sourced eagerly at startup.

# 2.5 Register Custom Modules (Leveraging Lazy-Loading Autoload)
$LocalModulesPath = Join-Path $ProfileRoot "Modules"
if (Test-Path $LocalModulesPath) {
    $PathSeparator = [IO.Path]::PathSeparator
    $CurrentPaths  = $env:PSModulePath -split $PathSeparator
    if ($LocalModulesPath -notin $CurrentPaths) {
        $env:PSModulePath = "$LocalModulesPath$PathSeparator$env:PSModulePath"
    }
    # Modules are deliberately not imported here: each module's manifest declares
    # its exported commands, so PowerShell autoloads it on first use at no startup cost.
}
if ($ProfileTrace) { Mark 'PSModulePath' }

# 3. Load Aliases (Consolidated)
$AliasFile = Join-Path $ConfigPath "Aliases.ps1"
if (Test-Path $AliasFile) {
    try { . $AliasFile } catch { Write-Warning "Failed to load aliases: $_" }
}
if ($ProfileTrace) { Mark 'Aliases' }

# 4. Initialization (Zoxide, Oh-My-Posh)
# Terminal-Icons is intentionally not imported: it adds measurable startup cost
# for icons that aren't essential. Opt in with `Import-Module Terminal-Icons`.

# Oh-My-Posh (Optimized Caching - Regenerate if cache missing or stale)
$OmpTheme = Join-Path $HOME "Documents\PowerShell\Themes\amro.omp.json"
$OmpCache = Join-Path $ProfileCacheDirectory "omp.cache.ps1"
$OmpExe   = Resolve-CachedCommand 'oh-my-posh'

if ($OmpExe -and (Test-Path $OmpTheme)) {
    $themeTicks  = [System.IO.File]::GetLastWriteTimeUtc($OmpTheme).Ticks
    $exeTicks    = [System.IO.File]::GetLastWriteTimeUtc($OmpExe).Ticks
    $expectedKey = "# KEY:$themeTicks-$exeTicks"

    $regenerate = -not (Test-Path $OmpCache)
    if (-not $regenerate) {
        $firstLine = $null
        try {
            $reader = [System.IO.File]::OpenText($OmpCache)
            $firstLine = $reader.ReadLine()
            $reader.Dispose()
        } catch { $regenerate = $true }

        if ($firstLine -ne $expectedKey) {
            $regenerate = $true
        }
    }

    if ($regenerate) {
        $raw = & $OmpExe init pwsh --config "$OmpTheme"
        # Avoid static session ID locking all shells to the same ID; generate dynamically per session
        $content = $raw -replace '\$env:POSH_SESSION_ID\s*=\s*"[^"]+";', '$env:POSH_SESSION_ID = [System.Guid]::NewGuid().ToString();'
        [System.IO.File]::WriteAllText($OmpCache, "$expectedKey`r`n$content", [System.Text.Encoding]::UTF8)
    }

    if ($env:OMP_ASYNC -eq '1') {
        # Defer prompt init until after first prompt render when gated by OMP_ASYNC=1
        $global:_ompOriginalPromptFunction = $Function:prompt
        $Function:prompt = {
            if (-not $global:_ompInitialized) {
                $global:_ompAsyncInit = $true
                try { . $OmpCache } catch { Write-Warning "oh-my-posh async init: $_" }
            }
            if ($global:_ompPromptFunction) {
                & $global:_ompPromptFunction
            }
        }
    } else {
        if (Test-Path $OmpCache) {
            try {
                . $OmpCache
            } catch {
                # Self-healing: regenerate on error
                $raw = & $OmpExe init pwsh --config "$OmpTheme"
                $content = $raw -replace '\$env:POSH_SESSION_ID\s*=\s*"[^"]+";', '$env:POSH_SESSION_ID = [System.Guid]::NewGuid().ToString();'
                [System.IO.File]::WriteAllText($OmpCache, "$expectedKey`r`n$content", [System.Text.Encoding]::UTF8)
                . $OmpCache
            }
        }
    }
}
if ($ProfileTrace) { Mark 'oh-my-posh' }

# Zoxide (Optimized Caching - Only regenerate if cache missing)
$ZoxideCache = Join-Path $ProfileCacheDirectory "zoxide.cache.ps1"
$ZoxideExe   = Resolve-CachedCommand 'zoxide'

if ($ZoxideExe) {
    # Only regenerate if cache doesn't exist (eliminates 2 Get-Item calls on normal loads)
    if (-not (Test-Path $ZoxideCache)) {
        & $ZoxideExe init powershell | Out-File -FilePath $ZoxideCache -Encoding utf8 -Force
    }

    if (Test-Path $ZoxideCache) {
        try {
            . $ZoxideCache
        } catch {
            # Self-healing: regenerate on error
            & $ZoxideExe init powershell | Out-File -FilePath $ZoxideCache -Encoding utf8 -Force
            . $ZoxideCache
        }
    }
}
if ($ProfileTrace) { Mark 'zoxide' }

$ProfileLoadSw.Stop()
$loadMs = [int][math]::Round($ProfileLoadSw.Elapsed.TotalMilliseconds)

if ($ProfileTrace) {
    $total = [math]::Round($ProfileLoadSw.Elapsed.TotalMilliseconds, 1)
    $ProfileTraceState.Marks.Add([pscustomobject]@{ Stage = 'TOTAL'; Ms = $total; TotalMs = $total })
    $report = $ProfileTraceState.Marks | Format-Table Stage, Ms, TotalMs -AutoSize | Out-String
    $log = Join-Path $env:TEMP 'pwsh-profile-trace.log'
    "[$(Get-Date -Format o)] pid=$PID host=$($Host.Name)$report" | Add-Content -LiteralPath $log -Encoding utf8
    if (-not [Console]::IsOutputRedirected) { Write-Host $report -ForegroundColor DarkCyan }
}

if ($Host.UI.SupportsVirtualTerminal) {
    # 0-500ms: violet (138,43,226) -> bright green (0,255,0)
    # 500-1000ms: brightest green (0,255,0)
    # 1000-1750ms: green -> yellow (255,255,0); 1750-2500ms+: yellow -> red (255,0,0)
    if ($loadMs -lt 500) {
        $t = [math]::Clamp($loadMs / 500.0, 0.0, 1.0)
        $r = [int][math]::Round(138 * (1.0 - $t))
        $g = [int][math]::Round(43 + (255 - 43) * $t)
        $b = [int][math]::Round(226 * (1.0 - $t))
    } elseif ($loadMs -le 1000) {
        $r = 0; $g = 255; $b = 0
    } elseif ($loadMs -lt 1750) {
        $t = ($loadMs - 1000) / 750.0
        $r = [int][math]::Round(255 * $t)
        $g = 255
        $b = 0
    } else {
        $t = [math]::Clamp(($loadMs - 1750) / 750.0, 0.0, 1.0)
        $r = 255
        $g = [int][math]::Round(255 * (1.0 - $t))
        $b = 0
    }
    $esc = [char]27
    Write-Host "Profile Loaded (" -NoNewline -ForegroundColor DarkGray
    Write-Host "$esc[38;2;$r;$g;${b}m$loadMs ms$esc[0m" -NoNewline
    Write-Host ")." -ForegroundColor DarkGray
} else {
    $loadColor = if ($loadMs -lt 500) { 'DarkMagenta' } elseif ($loadMs -le 1000) { 'Green' } elseif ($loadMs -lt 1750) { 'Yellow' } else { 'Red' }
    Write-Host "Profile Loaded (" -NoNewline -ForegroundColor DarkGray
    Write-Host "$loadMs ms" -NoNewline -ForegroundColor $loadColor
    Write-Host ")." -ForegroundColor DarkGray
}
