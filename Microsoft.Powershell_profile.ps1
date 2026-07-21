# -----------------------------------------------------------------------------
# Microsoft.PowerShell_profile.ps1 - The Optimized Loader
# -----------------------------------------------------------------------------
$ProfileRoot = Split-Path $PROFILE

# 1. Load Settings (Theme, Editor, PSReadline)
$ConfigPath = Join-Path $ProfileRoot "Config"
if (Test-Path $ConfigPath) {
    # Using high-performance .NET file enumeration to skip Get-ChildItem object overhead
    foreach ($File in [System.IO.Directory]::GetFiles($ConfigPath, "*.ps1")) {
        try {
            . $File
        } catch {
            Write-Warning "Failed to load config $($File): $_"
        }
    }
}

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

# 3. Load Aliases (Consolidated)
$AliasFile = Join-Path $ConfigPath "Aliases.ps1"
if (Test-Path $AliasFile) {
    try { . $AliasFile } catch { Write-Warning "Failed to load aliases: $_" }
}

# 4. Initialization (Zoxide, Oh-My-Posh, Icons)
# Terminal-Icons alters directory formatting, so it requires an explicit import
try { Import-Module Terminal-Icons -ErrorAction SilentlyContinue } catch {}

# Oh-My-Posh (Cached with Executable & Theme Validation)
$OmpTheme = Join-Path $HOME "Documents\PowerShell\Themes\gruvbox.omp.json"
$OmpCache = Join-Path $env:TEMP "omp.cache.ps1"
$OmpExe   = (Get-Command oh-my-posh -ErrorAction SilentlyContinue).Source

if ($OmpExe -and (Test-Path $OmpTheme)) {
    $CacheTime = if (Test-Path $OmpCache) { (Get-Item $OmpCache).LastWriteTime } else { [DateTime]::MinValue }
    $ThemeTime = (Get-Item $OmpTheme).LastWriteTime
    $ExeTime   = (Get-Item $OmpExe).LastWriteTime

    # Regenerate if cache is missing, theme changed, or oh-my-posh binary was updated
    if ($ThemeTime -gt $CacheTime -or $ExeTime -gt $CacheTime) {
        oh-my-posh init pwsh --config "$OmpTheme" | Out-File -FilePath $OmpCache -Encoding utf8 -Force
    }

    if (Test-Path $OmpCache) {
        try {
            . $OmpCache
        } catch {
            # Self-healing: If cached script fails (e.g. broken runtime paths after update), purge and regenerate instantly
            Remove-Item $OmpCache -Force -ErrorAction SilentlyContinue
            oh-my-posh init pwsh --config "$OmpTheme" | Out-File -FilePath $OmpCache -Encoding utf8 -Force
            . $OmpCache
        }
    }
}

# Zoxide (Cached with Executable Validation)
$ZoxideCache = Join-Path $env:TEMP "zoxide.cache.ps1"
$ZoxideExe   = (Get-Command zoxide -ErrorAction SilentlyContinue).Source

if ($ZoxideExe) {
    $CacheTime = if (Test-Path $ZoxideCache) { (Get-Item $ZoxideCache).LastWriteTime } else { [DateTime]::MinValue }
    $ExeTime   = (Get-Item $ZoxideExe).LastWriteTime

    if ($ExeTime -gt $CacheTime) {
        zoxide init powershell | Out-File -FilePath $ZoxideCache -Encoding utf8 -Force
    }

    if (Test-Path $ZoxideCache) {
        try {
            . $ZoxideCache
        } catch {
            Remove-Item $ZoxideCache -Force -ErrorAction SilentlyContinue
            zoxide init powershell | Out-File -FilePath $ZoxideCache -Encoding utf8 -Force
            . $ZoxideCache
        }
    }
}

Write-Host "Profile Loaded." -ForegroundColor DarkGray
