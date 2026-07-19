# -----------------------------------------------------------------------------
# Microsoft.PowerShell_profile.ps1 - The Optimized Loader
# -----------------------------------------------------------------------------
$ProfileRoot = Split-Path $PROFILE

# 1. Load Settings (Theme, Editor, PSReadline)
$ConfigPath = Join-Path $ProfileRoot "Config"
if (Test-Path $ConfigPath) {
    # Using high-performance .NET file enumeration to skip Get-ChildItem object overhead
    foreach ($File in [System.IO.Directory]::GetFiles($ConfigPath, "*.ps1")) {
        . $File
    }
}

# 2. Load Functions & Utilities (Loose Script Blocks)
# Replaced high-overhead pipelines with native foreach loops
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
    $CurrentPaths = $env:PSModulePath -split $PathSeparator
    if ($LocalModulesPath -notin $CurrentPaths) {
        $env:PSModulePath = "$LocalModulesPath$PathSeparator$env:PSModulePath"
    }
    # NOTE: Explicit 'Import-Module Rename-MediaFile' removed.
    # PowerShell will now auto-load it instantly on-demand the first time you invoke it.
}

# 3. Load Aliases (Consolidated)
$AliasFile = Join-Path $ConfigPath "Aliases.ps1"
if (Test-Path $AliasFile) { . $AliasFile }

# 4. Initialization (Zoxide, Oh-My-Posh, Icons)
# Terminal-Icons alters directory formatting, so it requires an explicit import
try { Import-Module Terminal-Icons -ErrorAction SilentlyContinue } catch {}

# Oh-My-Posh (Cached)
$OmpTheme = Join-Path $HOME "Documents\PowerShell\Themes\gruvbox.omp.json"
$OmpCache = Join-Path $env:TEMP "omp.cache.ps1"
if ((Test-Path $OmpTheme) -and ((!(Test-Path $OmpCache)) -or ((Get-Item $OmpTheme).LastWriteTime -gt (Get-Item $OmpCache).LastWriteTime))) {
    oh-my-posh init pwsh --config "$OmpTheme" | Out-File -FilePath $OmpCache -Encoding utf8
}
if (Test-Path $OmpCache) { . $OmpCache }

# Zoxide (Cached)
$ZoxideCache = Join-Path $env:TEMP "zoxide.cache.ps1"
if (-not (Test-Path $ZoxideCache)) {
    if (Get-Command zoxide -ErrorAction SilentlyContinue) {
        zoxide init powershell | Out-File -FilePath $ZoxideCache -Encoding utf8
    }
}
if (Test-Path $ZoxideCache) { . $ZoxideCache }

Write-Host "Profile Loaded." -ForegroundColor DarkGray
