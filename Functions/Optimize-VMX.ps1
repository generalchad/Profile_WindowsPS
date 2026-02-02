# =============================================================================
# VMware vNetwork Optimizer v8.0 Enterprise
# =============================================================================

# --- GLOBAL CONFIGURATION ---
$SearchPath   = "D:\Virtual Machines"
$DictToolPath = "C:\Program Files (x86)\VMware\VMware Workstation\dictTool.exe"
$LogWidth     = 85 # Width for horizontal rules

# --- ADAPTER RULES ---
$AdapterRules = @{
    "windows[7-9]|windows1|windows20|winserver2008r2|winserver201|winserver202" = "vmxnet3"
    "rhel|centos|ubuntu|debian|fedora|suse|other[2-6]xlinux|freebsd"            = "vmxnet3"
    "winxp|win2000|winnet|winvista|winserver2008$"                              = "e1000"
    "winnt|win31|win95|win98|winme"                                             = "vlance"
}

$ImplicitDefaults = @{
    "win31" = "vlance"; "win95" = "vlance"; "win98" = "vlance"
    "winme" = "vlance"; "winnt" = "vlance"
    "winxppro-64" = "e1000"; "winvista-64" = "e1000"; "winnetenterprise-64" = "e1000"
}

# --- HELPER FUNCTIONS ---

function Write-Header {
    Clear-Host
    $title = "VMWARE NETWORK ADAPTER OPTIMIZER v8.0"
    $padding = [math]::Floor(($LogWidth - $title.Length)/2)
    Write-Host ("=" * $LogWidth) -ForegroundColor Cyan
    Write-Host (" " * $padding + $title) -ForegroundColor White
    Write-Host ("=" * $LogWidth) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Log {
    param(
        [string]$Level,    # INFO, WARN, ERR, OK, ACTION
        [string]$Message,
        [string]$Detail = ""
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    switch ($Level) {
        "INFO"   { $color = "Gray";     $tag = "[INFO]  " }
        "WARN"   { $color = "Yellow";   $tag = "[WARN]  " }
        "ERR"    { $color = "Red";      $tag = "[ERR]   " }
        "OK"     { $color = "DarkGray"; $tag = "[OK]    " }
        "ACTION" { $color = "Cyan";     $tag = "[ACTION]" }
        "SUCCESS"{ $color = "Green";    $tag = "[DONE]  " }
        Default  { $color = "White";    $tag = "[LOG]   " }
    }

    # Format: Time | Tag | Message
    Write-Host "$timestamp $tag " -NoNewline -ForegroundColor $color
    Write-Host $Message -NoNewline -ForegroundColor $color
    
    if ($Detail) {
        Write-Host " : $Detail" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }
}

function Write-Separator {
    Write-Host ("-" * $LogWidth) -ForegroundColor DarkGray
}

# --- SAFE MANUAL WRITER (FALLBACK) ---
function Update-VMXManual ($FilePath, $Key, $Value) {
    Try {
        $enc = New-Object System.Text.UTF8Encoding $false # No BOM
        $lines = Get-Content $FilePath
        $newLines = @()
        $found = $false
        
        foreach ($line in $lines) {
            if ($line -match "^$Key\s*=") {
                $newLines += "$Key = `"$Value`""
                $found = $true
            } else {
                $newLines += $line
            }
        }
        if (-not $found) { $newLines += "$Key = `"$Value`"" }
        
        [System.IO.File]::WriteAllLines($FilePath, $newLines, $enc)
        return $true
    } Catch {
        return $false
    }
}

# --- INITIALIZATION ---
Write-Header

# --- ZOMBIE CHECK ---
$zombies = Get-Process vmware-vmx -ErrorAction SilentlyContinue
if ($zombies) {
    Write-Host " [!] CRITICAL PROCESS LOCK DETECTED" -ForegroundColor Red -BackgroundColor Black
    Write-Log "WARN" "Found $($zombies.Count) background 'vmware-vmx' processes."
    Write-Log "WARN" "These locks may cause write operations to fail."
    Write-Host ""
    $conf = Read-Host " > Type 'KILL' to force terminate processes, or Enter to proceed at risk"
    if ($conf -eq 'KILL') { 
        Stop-Process -Name vmware-vmx -Force
        Start-Sleep -Seconds 2 
        Write-Log "INFO" "Processes terminated."
    }
    Write-Separator
}

# --- MAIN EXECUTION ---
$vmxFiles = Get-ChildItem -Path $SearchPath -Filter *.vmx -Recurse
$stats = @{ Scanned=0; Optimized=0; Failed=0; Skipped=0; UpToDate=0 }

Write-Log "INFO" "Scanning directory: $SearchPath"
Write-Log "INFO" "Found $($vmxFiles.Count) VMX files."
Write-Separator

foreach ($file in $vmxFiles) {
    $vmName = $file.BaseName
    $stats.Scanned++

    # Check Locks
if (Test-Path ($file.FullName + ".lck")) {
        
        # Check if ANY VMware processes are running (Engine OR GUI)
        $runningVMware = Get-Process vmware, vmware-vmx -ErrorAction SilentlyContinue

        if ($runningVMware) {
            # DANGER: VMware is running. This lock is likely valid (or too risky to touch).
            Write-Log "WARN" "Skipping Locked VM (Active)" "$vmName - VMware is open."
            $stats.Skipped++
            continue
        } else {
            # OPPORTUNITY: Lock exists, but VMware is totally closed. It is STALE.
            Write-Host ""
            Write-Log "WARN" "Stale Lock Detected: $vmName"
            Write-Host "           The VM is locked, but VMware is not running." -ForegroundColor Gray
            Write-Host "           This is likely a leftover from a crash." -ForegroundColor Gray
            
            $unlock = Read-Host " > Delete stale lock and proceed? (Y/N)"
            
            if ($unlock -eq 'Y') {
                Try {
                    Remove-Item ($file.FullName + ".lck") -Recurse -Force -ErrorAction Stop
                    Write-Log "SUCCESS" "Lock Removed. Proceeding with scan..."
                    # We do NOT 'continue' here; we let the script fall through to the optimization logic below.
                } Catch {
                    Write-Log "ERR" "Could not delete lock folder." $_
                    $stats.Failed++
                    continue
                }
            } else {
                $stats.Skipped++
                continue
            }
        }
    }

    Try {
        $content = Get-Content $file.FullName -Raw
        $guestOS = "Unknown"
        if ($content -match 'guestOS\s*=\s*"([^"]+)"') { $guestOS = $matches[1] }
        
        $adapters = [regex]::Matches($content, 'ethernet(\d+)\.(?:virtualDev|present)') | 
                    ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

        if ($adapters.Count -eq 0) { 
            # Silent skip for non-networked VMs
            continue 
        }

        # Determine Recommendation
        $recType = "e1000"
        foreach ($pattern in $AdapterRules.Keys) {
            if ($guestOS -match $pattern) { $recType = $AdapterRules[$pattern]; break }
        }
        
        foreach ($idx in $adapters) {
            $key = "ethernet$idx.virtualDev"
            
            # Determine Current State
            $currRaw = "MISSING"
            $currDisplay = "MISSING"
            if ($content -match "$key\s*=\s*`"([^`"]+)`"") {
                $currRaw = $matches[1]
                $currDisplay = $currRaw
            } elseif ($ImplicitDefaults.ContainsKey($guestOS)) {
                $currRaw = $ImplicitDefaults[$guestOS]
                $currDisplay = "$currRaw (Implicit)"
            }

            # Check Compliance
            if ($currRaw -eq $recType) {
                Write-Log "OK" "$($vmName): $key matches optimal ($recType)"
                $stats.UpToDate++
                continue
            }

            # ACTION REQUIRED
            Write-Host ""
            Write-Log "ACTION" "Optimization Required: $vmName ($guestOS)"
            Write-Host "           Target Interface: $key" -ForegroundColor Gray
            Write-Host "           Current Driver:   $currDisplay" -ForegroundColor Red
            Write-Host "           Recommended:      $recType" -ForegroundColor Green
            Write-Host ""
            
            $choice = Read-Host " > Apply Fix? (Y/N)"
            
            if ($choice -eq 'Y') {
                # METHOD 1: dictTool
                $pInfo = New-Object System.Diagnostics.ProcessStartInfo
                $pInfo.FileName = $DictToolPath
                $pInfo.Arguments = "set `"$($file.FullName)`" $key $recType"
                $pInfo.RedirectStandardOutput = $true
                $pInfo.RedirectStandardError = $true
                $pInfo.UseShellExecute = $false
                $p = [System.Diagnostics.Process]::Start($pInfo)
                $p.WaitForExit()
                
                # Verify 1
                $v1 = Get-Content $file.FullName -Raw
                if ($v1 -match "$key\s*=\s*`"$recType`"") {
                    Write-Log "SUCCESS" "Updated successfully via dictTool."
                    $stats.Optimized++
                } else {
                    Write-Log "WARN" "dictTool failed. Attempting Direct Write..."
                    
                    # METHOD 2: Manual Fallback
                    $res = Update-VMXManual $file.FullName $key $recType
                    
                    # Verify 2
                    $v2 = Get-Content $file.FullName -Raw
                    if ($v2 -match "$key\s*=\s*`"$recType`"") {
                        Write-Log "SUCCESS" "Updated successfully via Direct Write."
                        $stats.Optimized++
                    } else {
                        Write-Log "ERR" "FATAL: Could not write to disk. Check Permissions."
                        $stats.Failed++
                    }
                }
            } else {
                Write-Log "INFO" "Skipped by user."
                $stats.Skipped++
            }
            Write-Separator
        }
    } Catch {
        Write-Log "ERR" "Read Error on $vmName" $_
        $stats.Failed++
    }
}

# --- SUMMARY REPORT ---
Write-Host ""
Write-Host ("=" * $LogWidth) -ForegroundColor Cyan
Write-Host " EXECUTION SUMMARY" -ForegroundColor White
Write-Host ("=" * $LogWidth) -ForegroundColor Cyan
Write-Host "  Files Scanned:   $($stats.Scanned)"
Write-Host "  Already Optimal: $($stats.UpToDate)" -ForegroundColor DarkGray
Write-Host "  Optimized:       $($stats.Optimized)" -ForegroundColor Green
Write-Host "  Skipped:         $($stats.Skipped)"   -ForegroundColor Yellow
Write-Host "  Failed:          $($stats.Failed)"    -ForegroundColor Red
Write-Host ("=" * $LogWidth) -ForegroundColor Cyan
Write-Host ""
pause