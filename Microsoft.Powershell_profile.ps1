# -----------------------------------------------------------------------------
# Microsoft.PowerShell_profile.ps1 - The Optimized Loader
# -----------------------------------------------------------------------------
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
        Sw    = [System.Diagnostics.Stopwatch]::StartNew()
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

# 2. Load Functions & Utilities (Loose Script Blocks)
foreach ($Folder in "Functions", "Utilities") {
    $Path = Join-Path $ProfileRoot $Folder
    if (Test-Path $Path) {
        foreach ($File in [System.IO.Directory]::GetFiles($Path, "*.ps1")) {
            try {
                . $File
            } catch {
                Write-Warning "Failed to load script $($File): $_"
            }
        }
    }
}
if ($ProfileTrace) { Mark 'Functions+Utilities' }

# 2.5 Register Custom Modules (Leveraging Lazy-Loading Autoload)
$LocalModulesPath = Join-Path $ProfileRoot "Modules"
if (Test-Path $LocalModulesPath) {
    $PathSeparator = [IO.Path]::PathSeparator
    $CurrentPaths  = $env:PSModulePath -split $PathSeparator
    if ($LocalModulesPath -notin $CurrentPaths) {
        $env:PSModulePath = "$LocalModulesPath$PathSeparator$env:PSModulePath"
    }
    # NOTE: Explicit 'Import-Module Rename-MediaFile' removed.
    # PowerShell will now auto-load it instantly on-demand the first time you invoke it.
}
if ($ProfileTrace) { Mark 'PSModulePath' }

# 3. Load Aliases (Consolidated)
$AliasFile = Join-Path $ConfigPath "Aliases.ps1"
if (Test-Path $AliasFile) {
    try { . $AliasFile } catch { Write-Warning "Failed to load aliases: $_" }
}
if ($ProfileTrace) { Mark 'Aliases' }

# 4. Initialization (Zoxide, Oh-My-Posh, Icons)
# Terminal-Icons removed for performance - Import manually if needed:
# Import-Module Terminal-Icons

# Oh-My-Posh (Optimized Caching - Only regenerate if cache missing)
$OmpTheme = Join-Path $HOME "Documents\PowerShell\Themes\gruvbox.omp.json"
$OmpCache = Join-Path $env:TEMP "omp.cache.ps1"
$OmpExe   = Resolve-CachedCommand 'oh-my-posh'

if ($OmpExe -and (Test-Path $OmpTheme)) {
    # Only regenerate if cache doesn't exist (eliminates 3 Get-Item calls on normal loads)
    if (-not (Test-Path $OmpCache)) {
        oh-my-posh init pwsh --config "$OmpTheme" | Out-File -FilePath $OmpCache -Encoding utf8 -Force
    }

    if (Test-Path $OmpCache) {
        try {
            . $OmpCache
        } catch {
            # Self-healing: regenerate on error
            oh-my-posh init pwsh --config "$OmpTheme" | Out-File -FilePath $OmpCache -Encoding utf8 -Force
            . $OmpCache
        }
    }
}
if ($ProfileTrace) { Mark 'oh-my-posh' }

# Zoxide (Optimized Caching - Only regenerate if cache missing)
$ZoxideCache = Join-Path $env:TEMP "zoxide.cache.ps1"
$ZoxideExe   = Resolve-CachedCommand 'zoxide'

if ($ZoxideExe) {
    # Only regenerate if cache doesn't exist (eliminates 2 Get-Item calls on normal loads)
    if (-not (Test-Path $ZoxideCache)) {
        zoxide init powershell | Out-File -FilePath $ZoxideCache -Encoding utf8 -Force
    }

    if (Test-Path $ZoxideCache) {
        try {
            . $ZoxideCache
        } catch {
            # Self-healing: regenerate on error
            zoxide init powershell | Out-File -FilePath $ZoxideCache -Encoding utf8 -Force
            . $ZoxideCache
        }
    }
}
if ($ProfileTrace) { Mark 'zoxide' }

if ($ProfileTrace) {
    $ProfileTraceState.Sw.Stop()
    $total = [math]::Round($ProfileTraceState.Sw.Elapsed.TotalMilliseconds, 1)
    $ProfileTraceState.Marks.Add([pscustomobject]@{ Stage = 'TOTAL'; Ms = $total; TotalMs = $total })
    $report = $ProfileTraceState.Marks | Format-Table Stage, Ms, TotalMs -AutoSize | Out-String
    $log = Join-Path $env:TEMP 'pwsh-profile-trace.log'
    "[$(Get-Date -Format o)] pid=$PID host=$($Host.Name)$report" | Add-Content -LiteralPath $log -Encoding utf8
    if (-not [Console]::IsOutputRedirected) { Write-Host $report -ForegroundColor DarkCyan }
}

Write-Host "Profile Loaded." -ForegroundColor DarkGray
