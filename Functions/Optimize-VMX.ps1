function Optimize-VMX {
    <#
    .SYNOPSIS
        VMware vNetwork & Stability Optimizer
    #>
    param (
        [string]$Path = "D:\Virtual Machines",
        [switch]$Recurse,
        [switch]$NoBackup,
        [switch]$AutoApprove
    )

    # --- CONFIGURATION ---
    $LogWidth     = 85
    $AdapterRules = [ordered]@{
        "winvista-64"                                                                     = "vmxnet3"
        "windows[7-9]|windows1|windows20|winserver2008r2|winserver201|winserver202"       = "vmxnet3"
        "rhel|centos|ubuntu|debian|fedora|suse|other[2-6]xlinux|freebsd"                  = "vmxnet3"
        "winxp|win2000|winnet|winvista|winserver2008$"                                    = "e1000"
        "winnt|win31|win95|win98|winme"                                                   = "vlance"
    }
    $HardwarePinning = @{ "winvista" = "12"; "win95|win98" = "8" }

    # --- HELPERS ---
    function Local:Write-Log {
        param([string]$Level, [string]$Message, [string]$Detail = "")
        $colors = @{ "INFO"="Gray"; "WARN"="Yellow"; "ERR"="Red"; "ACTION"="Cyan"; "OK"="DarkGray" }
        Write-Host ("$(Get-Date -Format 'HH:mm:ss') [$($Level.PadRight(4).Substring(0,4))] ") -NoNewline -ForegroundColor $colors[$Level]
        Write-Host $Message -NoNewline -ForegroundColor $colors[$Level]
        if ($Detail) { Write-Host " : $Detail" -ForegroundColor DarkGray } else { Write-Host "" }
    }

    function Local:Set-VMXSetting {
        param ($ContentLines, $Key, $Value)
        $escapedKey = [regex]::Escape($Key)
        $found = $false; $newLines = @()
        foreach ($line in $ContentLines) {
            # Added ^\s* to handle potential indentation in VMX files
            if ($line -match "^\s*$escapedKey\s*=") {
                $newLines += "$Key = `"$Value`""
                $found = $true
            }
            else { $newLines += $line }
        }
        if (-not $found) { $newLines += "$Key = `"$Value`"" }
        return ,$newLines
    }

    # --- EXECUTION ---
    Clear-Host
    Write-Host ("=" * $LogWidth) -ForegroundColor Cyan
    Write-Host " VMWARE OPTIMIZER v8.9 [FINAL CHECK]" -ForegroundColor White
    Write-Host ("=" * $LogWidth) -ForegroundColor Cyan

    if (-not (Test-Path $Path)) { Write-Error "Path not found: $Path"; return }

    # Kill Zombies
    $zombies = Get-Process vmware-vmx -ErrorAction SilentlyContinue
    if ($zombies) {
        Write-Log "WARN" "Active 'vmware-vmx' processes found. Close VMware Workstation/Player."
        $k = Read-Host "    > Kill processes? [Y/N]"
        if ($k -eq 'Y') { Stop-Process -Name vmware-vmx -Force; Start-Sleep 1 } else { return }
    }

    $vmxFiles = Get-ChildItem -Path $Path -Filter "*.vmx" -Recurse:$Recurse
    $stats = @{ Scanned=0; Optimized=0; Failed=0; Skipped=0 }

    foreach ($file in $vmxFiles) {
        $vmName = $file.BaseName
        $stats.Scanned++

        if (Test-Path ($file.FullName + ".lck")) {
            Write-Log "WARN" "Skipping Locked VM (Running?)" $vmName
            $stats.Skipped++; continue
        }

        Try {
            $currentContent = Get-Content $file.FullName
            $originalHash = $currentContent -join "`n"
            $guestOS = if ($originalHash -match 'guestOS\s*=\s*"([^"]+)"') { $matches[1] } else { "Unknown" }
            $pendingChanges = @()

            # 1. NETWORK ADAPTERS
            $recNet = "e1000"
            foreach ($pattern in $AdapterRules.Keys) { if ($guestOS -match $pattern) { $recNet = $AdapterRules[$pattern]; break } }

            $adapters = [regex]::Matches($originalHash, 'ethernet(\d+)\.(?:virtualDev|present)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
            foreach ($idx in $adapters) {
                $key = "ethernet$idx.virtualDev"
                # Check using strict regex to avoid false positives
                if (-not ($currentContent -match [regex]::Escape($key) + "\s*=\s*`"$recNet`"")) {
                    $pendingChanges += [PSCustomObject]@{ Property = $key; NewValue = $recNet }
                }
            }

            # 2. PINNING & STABILITY
            foreach ($pattern in $HardwarePinning.Keys) {
                if ($guestOS -match $pattern) {
                    $ver = $HardwarePinning[$pattern]
                    if (-not ($currentContent -match "virtualHW.version\s*=\s*`"$ver`"")) {
                        $pendingChanges += [PSCustomObject]@{ Property = "virtualHW.version"; NewValue = $ver }
                        $pendingChanges += [PSCustomObject]@{ Property = "tools.upgrade.policy"; NewValue = "manual" }
                    }
                }
            }

            # 3. TIME SYNC
            if (-not ($currentContent -match 'tools.syncTime\s*=\s*"TRUE"')) {
                $pendingChanges += [PSCustomObject]@{ Property = "tools.syncTime"; NewValue = "TRUE" }
            }

            # --- APPLY LOGIC ---
            if ($pendingChanges.Count -gt 0) {
                Write-Host "`n[?] $vmName ($guestOS)" -ForegroundColor White
                foreach ($change in $pendingChanges) {
                    Write-Host "    $($change.Property)" -NoNewline -ForegroundColor Cyan
                    Write-Host " -> " -NoNewline -ForegroundColor DarkGray
                    Write-Host "$($change.NewValue)" -ForegroundColor Yellow

                    # VMXNET3 Warning
                    if ($change.NewValue -eq "vmxnet3" -and $guestOS -match "win") {
                        Write-Host " (Requires VMware Tools!)" -NoNewline -ForegroundColor Red
                    }
                    Write-Host ""
                }

                $choice = "Y"
                if (-not $AutoApprove) {
                    $choice = Read-Host "    Apply? [Y]es, [N]o (Skip), [A]ll, [Q]uit"
                }

                if ($choice -eq 'Q') { break }
                if ($choice -eq 'A') { $AutoApprove = $true; $choice = 'Y' }

                # Default safety: If user hits Enter (Empty), treat as No
                if ($choice -eq 'Y') {
                    foreach ($change in $pendingChanges) {
                        $currentContent = Set-VMXSetting $currentContent $change.Property $change.NewValue
                    }

                    # Backup
                    if (-not $NoBackup) { Copy-Item $file.FullName ($file.FullName + ".bak") -Force }

                    # Write
                    [System.IO.File]::WriteAllLines($file.FullName, $currentContent, [System.Text.UTF8Encoding]::new($false))

                    Write-Log "OK" "Updated"
                    $stats.Optimized++
                } else {
                    Write-Log "INFO" "Skipped"
                }
            }
        } Catch {
            Write-Log "ERR" "Failed $vmName" $_.Exception.Message
            $stats.Failed++
        }
    }

    Write-Host "`nDONE. Scanned: $($stats.Scanned) | Optimized: $($stats.Optimized) | Failed: $($stats.Failed)" -ForegroundColor Green
}
