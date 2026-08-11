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
# Terminal-Icons removed for performance - Import manually if needed:
# Import-Module Terminal-Icons

# Oh-My-Posh (Optimized Caching - Only regenerate if cache missing)
$OmpTheme = Join-Path $HOME "Documents\PowerShell\Themes\gruvbox.omp.json"
$OmpCache = Join-Path $env:TEMP "omp.cache.ps1"
$OmpExe   = (Get-Command oh-my-posh -ErrorAction SilentlyContinue).Source

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

# Zoxide (Optimized Caching - Only regenerate if cache missing)
$ZoxideCache = Join-Path $env:TEMP "zoxide.cache.ps1"
$ZoxideExe   = (Get-Command zoxide -ErrorAction SilentlyContinue).Source

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

Write-Host "Profile Loaded." -ForegroundColor DarkGray
