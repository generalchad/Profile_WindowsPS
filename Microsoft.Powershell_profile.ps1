# -----------------------------------------------------------------------------
# Microsoft.PowerShell_profile.ps1 - The Loader
# -----------------------------------------------------------------------------
$ProfileRoot = Split-Path $PROFILE

# 1. Load Settings (Theme, Editor, PSReadline)
$ConfigPath = Join-Path $ProfileRoot "Config"
Get-ChildItem -Path $ConfigPath -Filter "*.ps1" | ForEach-Object { . $_.FullName }

# 2. Load Functions & Utilities
# We load these before aliases so aliases can reference them
$ModuleFolders = @("Functions", "Utilities")
foreach ($folder in $ModuleFolders) {
    $path = Join-Path $ProfileRoot $folder
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter "*.ps1" | ForEach-Object {
            try {
                . $_.FullName
            } catch {
                Write-Warning "Failed to load module $($_.Name): $_"
            }
        }
    }
}

# 3. Load Aliases (Consolidated)
$AliasFile = Join-Path $ConfigPath "Aliases.ps1"
if (Test-Path $AliasFile) { . $AliasFile }

# 4. Initialization (Zoxide, Oh-My-Posh, Icons)
# Using 'try' blocks to prevent errors if tools aren't installed

# Terminal Icons
try { Import-Module Terminal-Icons -ErrorAction Stop } catch {}

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