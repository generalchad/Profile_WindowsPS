# 4. Initialization (Zoxide, Oh-My-Posh, Icons)
# -----------------------------------------------------------------------------

# A. Terminal Icons (Fast enough to load directly)
if (Get-Module -ListAvailable Terminal-Icons) {
    Import-Module Terminal-Icons -ErrorAction SilentlyContinue
}

# B. Oh-My-Posh (Smart Caching)
$OmpTheme     = Join-Path $HOME "Documents\PowerShell\Themes\gruvbox.omp.json"
$OmpCache     = Join-Path $env:TEMP "omp.cache.ps1"
$ProfileTime  = (Get-Item $PROFILE).LastWriteTime

if (Test-Path $OmpTheme) {
    # We rebuild the cache if:
    # 1. Cache file is missing
    # 2. You edited your PROFILE recently (This fixes your current issue!)
    # 3. You edited the THEME file recently
    $NeedRebuild = -not (Test-Path $OmpCache)
    
    if (-not $NeedRebuild) {
        $CacheTime = (Get-Item $OmpCache).LastWriteTime
        $ThemeTime = (Get-Item $OmpTheme).LastWriteTime
        if ($ProfileTime -gt $CacheTime -or $ThemeTime -gt $CacheTime) { $NeedRebuild = $true }
    }

    if ($NeedRebuild) {
        # Generate new cache
        $null = oh-my-posh init pwsh --config "$OmpTheme" | Out-File -FilePath $OmpCache -Encoding utf8 -Force
    }

    # Safety Check: If cache is valid (exists and has content), run it.
    if ((Test-Path $OmpCache) -and (Get-Item $OmpCache).Length -gt 0) {
        . $OmpCache
    }
    else {
        # Fallback: If cache generation failed, run live so the shell doesn't break
        oh-my-posh init pwsh --config "$OmpTheme" | Invoke-Expression
    }
}

# C. Zoxide (Binary Awareness)
$ZoxideCache = Join-Path $env:TEMP "zoxide.cache.ps1"
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    # Check if Zoxide binary is newer than the cache (e.g. you ran 'winget upgrade zoxide')
    $ZoxideBinTime = (Get-Command zoxide).Source | Get-Item | Select-Object -ExpandProperty LastWriteTime
    
    if (-not (Test-Path $ZoxideCache) -or $ZoxideBinTime -gt (Get-Item $ZoxideCache).LastWriteTime) {
        zoxide init powershell | Out-File -FilePath $ZoxideCache -Encoding utf8 -Force
    }
    . $ZoxideCache
}
else {
    # Fallback: If Zoxide is not installed, use a simple alias for 'cd'
    Set-Alias cd Set-Location
}