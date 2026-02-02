function Optimize-VMX {
    <#
    .SYNOPSIS
        VMware vNetwork Optimizer v8.0 Enterprise
    .DESCRIPTION
        Scans a directory for VMX files and ensures they are using the optimal 
        virtual network adapter based on the Guest OS.
    #>
    
    # --- INTERNAL CONFIGURATION ---
    $SearchPath   = "D:\Virtual Machines"
    $DictToolPath = "C:\Program Files (x86)\VMware\VMware Workstation\dictTool.exe"
    $LogWidth     = 85 

    $AdapterRules = @{
        "windows[7-9]|windows1|windows20|winserver2008r2|winserver201|winserver202" = "vmxnet3"
        "rhel|centos|ubuntu|debian|fedora|suse|other[2-6]xlinux|freebsd"            = "vmxnet3"
        "winxp|win2000|winnet|winvista|winserver2008$"                             = "e1000"
        "winnt|win31|win95|win98|winme"                                             = "vlance"
    }

    $ImplicitDefaults = @{
        "win31" = "vlance"; "win95" = "vlance"; "win98" = "vlance"
        "winme" = "vlance"; "winnt" = "vlance"
        "winxppro-64" = "e1000"; "winvista-64" = "e1000"; "winnetenterprise-64" = "e1000"
    }

    # --- INTERNAL HELPER FUNCTIONS ---
    function Local:Write-Header {
        Clear-Host
        $title = "VMWARE NETWORK ADAPTER OPTIMIZER v8.0"
        $padding = [math]::Floor(($LogWidth - $title.Length)/2)
        Write-Host ("=" * $LogWidth) -ForegroundColor Cyan
        Write-Host (" " * $padding + $title) -ForegroundColor White
        Write-Host ("=" * $LogWidth) -ForegroundColor Cyan
        Write-Host ""
    }

    function Local:Write-Log {
        param([string]$Level, [string]$Message, [string]$Detail = "")
        $timestamp = Get-Date -Format "HH:mm:ss"
        switch ($Level) {
            "INFO"    { $color = "Gray";     $tag = "[INFO]  " }
            "WARN"    { $color = "Yellow";   $tag = "[WARN]  " }
            "ERR"     { $color = "Red";      $tag = "[ERR]   " }
            "OK"      { $color = "DarkGray"; $tag = "[OK]    " }
            "ACTION"  { $color = "Cyan";     $tag = "[ACTION]" }
            "SUCCESS" { $color = "Green";    $tag = "[DONE]  " }
            Default   { $color = "White";    $tag = "[LOG]   " }
        }
        Write-Host "$timestamp $tag " -NoNewline -ForegroundColor $color
        Write-Host $Message -NoNewline -ForegroundColor $color
        if ($Detail) { Write-Host " : $Detail" -ForegroundColor DarkGray } else { Write-Host "" }
    }

    function Local:Write-Separator {
        Write-Host ("-" * $LogWidth) -ForegroundColor DarkGray
    }

    function Local:Update-VMXManual ($FilePath, $Key, $Value) {
        Try {
            $enc = New-Object System.Text.UTF8Encoding $false 
            $lines = Get-Content $FilePath
            $newLines = @()
            $found = $false
            foreach ($line in $lines) {
                if ($line -match "^$Key\s*=") {
                    $newLines += "$Key = `"$Value`""
                    $found = $true
                } else { $newLines += $line }
            }
            if (-not $found) { $newLines += "$Key = `"$Value`"" }
            [System.IO.File]::WriteAllLines($FilePath, $newLines, $enc)
            return $true
        } Catch { return $false }
    }

    # --- EXECUTION LOGIC ---
    Write-Header

    # Zombie Check
    $zombies = Get-Process vmware-vmx -ErrorAction SilentlyContinue
    if ($zombies) {
        Write-Host " [!] CRITICAL PROCESS LOCK DETECTED" -ForegroundColor Red -BackgroundColor Black
        Write-Log "WARN" "Found $($zombies.Count) background 'vmware-vmx' processes."
        $conf = Read-Host " > Type 'KILL' to force terminate processes, or Enter to proceed at risk"
        if ($conf -eq 'KILL') { 
            Stop-Process -Name vmware-vmx -Force
            Start-Sleep -Seconds 2 
            Write-Log "INFO" "Processes terminated."
        }
        Write-Separator
    }

    $vmxFiles = Get-ChildItem -Path $SearchPath -Filter *.vmx -Recurse
    $stats = @{ Scanned=0; Optimized=0; Failed=0; Skipped=0; UpToDate=0 }

    Write-Log "INFO" "Scanning directory: $SearchPath"
    Write-Log "INFO" "Found $($vmxFiles.Count) VMX files."
    Write-Separator

    foreach ($file in $vmxFiles) {
        $vmName = $file.BaseName
        $stats.Scanned++

        if (Test-Path ($file.FullName + ".lck")) {
            $runningVMware = Get-Process vmware, vmware-vmx -ErrorAction SilentlyContinue
            if ($runningVMware) {
                Write-Log "WARN" "Skipping Locked VM (Active)" "$vmName - VMware is open."
                $stats.Skipped++
                continue
            } else {
                Write-Log "WARN" "Stale Lock Detected: $vmName"
                $unlock = Read-Host " > Delete stale lock and proceed? (Y/N)"
                if ($unlock -eq 'Y') {
                    Try {
                        Remove-Item ($file.FullName + ".lck") -Recurse -Force -ErrorAction Stop
                        Write-Log "SUCCESS" "Lock Removed."
                    } Catch {
                        Write-Log "ERR" "Could not delete lock." $_
                        $stats.Failed++
                        continue
                    }
                } else { $stats.Skipped++; continue }
            }
        }

        Try {
            $content = Get-Content $file.FullName -Raw
            $guestOS = "Unknown"
            if ($content -match 'guestOS\s*=\s*"([^"]+)"') { $guestOS = $matches[1] }
            
            $adapters = [regex]::Matches($content, 'ethernet(\d+)\.(?:virtualDev|present)') | 
                        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

            if ($adapters.Count -eq 0) { continue }

            $recType = "e1000"
            foreach ($pattern in $AdapterRules.Keys) {
                if ($guestOS -match $pattern) { $recType = $AdapterRules[$pattern]; break }
            }
            
            foreach ($idx in $adapters) {
                $key = "ethernet$idx.virtualDev"
                $currRaw = "MISSING"
                $currDisplay = "MISSING"
                if ($content -match "$key\s*=\s*`"([^`"]+)`"") {
                    $currRaw = $matches[1]
                    $currDisplay = $currRaw
                } elseif ($ImplicitDefaults.ContainsKey($guestOS)) {
                    $currRaw = $ImplicitDefaults[$guestOS]
                    $currDisplay = "$currRaw (Implicit)"
                }

                if ($currRaw -eq $recType) {
                    Write-Log "OK" "$($vmName): $key matches optimal ($recType)"
                    $stats.UpToDate++
                    continue
                }

                Write-Log "ACTION" "Optimization Required: $vmName ($guestOS)"
                Write-Host "           Current Driver:   $currDisplay" -ForegroundColor Red
                Write-Host "           Recommended:      $recType" -ForegroundColor Green
                
                $choice = Read-Host " > Apply Fix? (Y/N)"
                if ($choice -eq 'Y') {
                    # Try dictTool first
                    Start-Process -FilePath $DictToolPath -ArgumentList "set `"$($file.FullName)`" $key $recType" -Wait -NoNewWindow
                    
                    $v1 = Get-Content $file.FullName -Raw
                    if ($v1 -match "$key\s*=\s*`"$recType`"") {
                        Write-Log "SUCCESS" "Updated via dictTool."
                        $stats.Optimized++
                    } else {
                        if (Update-VMXManual $file.FullName $key $recType) {
                            Write-Log "SUCCESS" "Updated via Direct Write."
                            $stats.Optimized++
                        } else {
                            Write-Log "ERR" "Update failed."
                            $stats.Failed++
                        }
                    }
                } else { $stats.Skipped++ }
                Write-Separator
            }
        } Catch {
            Write-Log "ERR" "Read Error on $vmName"
            $stats.Failed++
        }
    }

    # --- SUMMARY ---
    Write-Separator
    Write-Host " SCANNED: $($stats.Scanned) | OPTIMIZED: $($stats.Optimized) | SKIPPED: $($stats.Skipped) | FAILED: $($stats.Failed)" -ForegroundColor White
    Write-Separator
}