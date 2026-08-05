function Optimize-VMX {
    <#
    .SYNOPSIS
        Optimizes VMware .vmx configuration files for network stability and legacy OS compatibility.

    .DESCRIPTION
        Parses all .vmx files in a target directory to ensure optimal network adapters
        (e.g., vmxnet3 for modern OSes, e1000/vlance for legacy) are configured based on the guestOS.
        Also pins hardware versions for legacy operating systems to prevent boot failures on modern hypervisors,
        and ensures time synchronization is enabled.

    .PARAMETER Path
        The root directory containing the VMware virtual machines.

    .PARAMETER Recurse
        Searches all subdirectories within the specified Path for .vmx files.

    .PARAMETER NoBackup
        Skips the creation of .bak files. By default, a backup is created before modifying any .vmx file.

    .PARAMETER AutoApprove
        Bypasses the interactive prompt and automatically applies all recommended changes.

    .PARAMETER ClearScreen
        Clears the host screen before running.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$Path = "D:\Virtual Machines",
        [switch]$Recurse,
        [switch]$NoBackup,
        [switch]$AutoApprove,
        [switch]$ClearScreen
    )

    $LogWidth = 85

    # Ordered dictionary is critical here to ensure specific OS regexes (like 64-bit variants)
    # are evaluated before broader catch-all regexes trigger.
    $AdapterRules = [ordered]@{
        "winvista-64"                                                                   = "vmxnet3"
        "windows[7-9]|windows1[01]|windows20|winserver2008r2|winserver201|winserver202" = "vmxnet3"
        "rhel|centos|ubuntu|debian|fedora|suse|other[2-6]xlinux|freebsd"                = "vmxnet3"
        "winxp|win2000|winnet|winvista|winserver2008"                                   = "e1000"
        "winnt|win31|win95|win98|winme"                                                 = "vlance"
    }

    # Modern hardware versions (10+) break mouse/keyboard or cause boot loops on Win9x/Vista.
    # Ordered dictionary is used here for the same reason as $AdapterRules: the loop below stops
    # after the first match, so enumeration order must be deterministic.
    $HardwarePinning = [ordered]@{ "winvista" = "12"; "win95|win98" = "8" }

    # Local mutable flag for "apply all remaining changes without prompting". Kept separate
    # from the -AutoApprove switch parameter so we never mutate a bound parameter value.
    $autoApproveAll = $AutoApprove.IsPresent

    if ($ClearScreen) { Clear-Host }
    Write-Host ("=" * $LogWidth) -ForegroundColor Cyan
    Write-Host " VMWARE CONFIGURATION OPTIMIZER" -ForegroundColor White
    Write-Host ("=" * $LogWidth) -ForegroundColor Cyan

    if (-not (Test-Path $Path)) { Write-Error "Path not found: $Path"; return }

    # If vmware-vmx is active, it holds locks on running VMs. Modifying a running VM's VMX
    # file directly will result in the changes being overwritten when the VM powers down.
    $zombies = Get-Process vmware-vmx -ErrorAction SilentlyContinue
    if ($zombies) {
        Write-Log "WARN" "Active 'vmware-vmx' processes found. Close VMware Workstation/Player."

        if ($autoApproveAll) {
            $k = 'Y'
        } else {
            $k = Read-Host "    > Kill processes? [Y/N]"
        }

        if ($k -eq 'Y') {
            Stop-Process -Name vmware-vmx -Force

            # Give VMware a chance to fully release file locks before we proceed. Poll
            # rather than a flat sleep, since a fixed 1s wait can be too short under load
            # (many running VMs) and unnecessarily long when the process exits instantly.
            $waited = 0
            $pollIntervalMs = 250
            $maxWaitMs = 5000
            while ((Get-Process vmware-vmx -ErrorAction SilentlyContinue) -and ($waited -lt $maxWaitMs)) {
                Start-Sleep -Milliseconds $pollIntervalMs
                $waited += $pollIntervalMs
            }
            if (Get-Process vmware-vmx -ErrorAction SilentlyContinue) {
                Write-Log "WARN" "vmware-vmx still running after ${maxWaitMs}ms wait" "Proceeding anyway"
            }
        } else { return }
    }

    $vmxFiles = Get-ChildItem -Path $Path -Filter "*.vmx" -Recurse:$Recurse
    $stats = @{ Scanned=0; Optimized=0; Failed=0; Skipped=0 }

    if ($vmxFiles.Count -eq 0) {
        Write-Log "WARN" "No .vmx files found" $Path
    }

    foreach ($file in $vmxFiles) {
        $vmName = $file.BaseName
        $stats.Scanned++

        # .lck files indicate the VM is currently powered on or suspended.
        if ((Test-Path ($file.FullName + ".lck")) -or (Test-Path ($file.FullName + ".lck\*"))) {
            Write-Log "WARN" "Skipping Locked VM (Running?)" $vmName
            $stats.Skipped++; continue
        }

        Try {
            $rawContent = Get-Content $file.FullName -Raw
            $currentContent = $rawContent -split '\r?\n'

            $guestOS = if ($rawContent -match 'guestOS\s*=\s*"([^"]+)"') { $matches[1] } else { "Unknown" }
            $pendingChanges = @()

            # e1000 is the safest fallback if the OS is unrecognized, as it has native inbox drivers
            # for almost all operating systems released after 2003.
            $recNet = "e1000"
            foreach ($pattern in $AdapterRules.Keys) {
                if ($guestOS -match $pattern) { $recNet = $AdapterRules[$pattern]; break }
            }

            # Extracts all unique ethernet adapter indexes (e.g., ethernet0, ethernet1) present in the file
            $adapters = [regex]::Matches($rawContent, 'ethernet(\d+)\.') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
            foreach ($idx in $adapters) {
                $key = "ethernet$idx.virtualDev"
                # Anchored to line start/end (multiline) so this can never ambiguously match
                # a different adapter's line (e.g. ethernet1 vs ethernet10).
                $currentValuePattern = "(?m)^\s*" + [regex]::Escape($key) + "\s*=\s*`"$recNet`"\s*$"
                if (-not ($rawContent -match $currentValuePattern)) {
                    $pendingChanges += [PSCustomObject]@{ Property = $key; NewValue = $recNet }
                }
            }

            foreach ($pattern in $HardwarePinning.Keys) {
                if ($guestOS -match $pattern) {
                    $ver = $HardwarePinning[$pattern]
                    if (-not ($rawContent -match "virtualHW.version\s*=\s*`"$ver`"")) {
                        $pendingChanges += [PSCustomObject]@{ Property = "virtualHW.version"; NewValue = $ver }

                        # Disabling auto-upgrade prevents VMware from overwriting our pinned hardware version later
                        $pendingChanges += [PSCustomObject]@{ Property = "tools.upgrade.policy"; NewValue = "manual" }
                    }

                    # Only one hardware-pinning rule should ever apply to a given guestOS. Stopping
                    # here prevents conflicting/duplicate virtualHW.version changes if the rule table
                    # is ever extended with overlapping patterns.
                    break
                }
            }

            if (-not ($rawContent -match 'tools.syncTime\s*=\s*"TRUE"')) {
                $pendingChanges += [PSCustomObject]@{ Property = "tools.syncTime"; NewValue = "TRUE" }
            }

            if ($pendingChanges.Count -gt 0) {
                Write-Host "`n[?] $vmName ($guestOS)" -ForegroundColor White
                foreach ($change in $pendingChanges) {
                    Write-Host "    $($change.Property)" -NoNewline -ForegroundColor Cyan
                    Write-Host " -> " -NoNewline -ForegroundColor DarkGray
                    Write-Host "$($change.NewValue)" -NoNewline -ForegroundColor Yellow

                    if ($change.NewValue -eq "vmxnet3" -and $guestOS -match "win") {
                        Write-Host " (Requires VMware Tools!)" -ForegroundColor Red
                    } else {
                        Write-Host ""
                    }
                }

                # ShouldProcess is the single source of truth for -WhatIf/-Confirm handling. It
                # returns $false automatically under -WhatIf, so we don't need (and must not
                # duplicate) a manual $WhatIfPreference check here - doing so previously caused
                # -Confirm to trigger two separate prompts for the same action.
                $choice = "Y"
                if (-not $autoApproveAll -and -not $WhatIfPreference) {
                    $choice = Read-Host "    Apply? [Y]es, [N]o (Skip), [A]ll, [Q]uit"
                }

                if ($choice -match '^[Qq]') {
                    Write-Log "WARN" "Aborted by user"
                    break
                }
                if ($choice -match '^[Aa]') { $autoApproveAll = $true; $choice = 'Y' }

                if ($choice -match '^[Yy]') {
                    if ($PSCmdlet.ShouldProcess($file.FullName, "Apply $($pendingChanges.Count) VMX setting change(s)")) {
                        foreach ($change in $pendingChanges) {
                            $currentContent = Set-VMXSetting -ContentLines $currentContent -Key $change.Property -Value $change.NewValue
                        }

                        if (-not $NoBackup) { Copy-Item $file.FullName ($file.FullName + ".bak") -Force }

                        # VMware cannot parse VMX files if they contain a Byte Order Mark (BOM).
                        # We must explicitly define UTF-8 encoding with the BOM disabled ($false).
                        [System.IO.File]::WriteAllLines($file.FullName, $currentContent, [System.Text.UTF8Encoding]::new($false))

                        Write-Log "OK" "Updated"
                        $stats.Optimized++
                    } else {
                        Write-Log "INFO" "Skipped (WhatIf)"
                        $stats.Skipped++
                    }
                } else {
                    Write-Log "INFO" "Skipped"
                    $stats.Skipped++
                }
            }
        } Catch {
            Write-Log "ERR" "Failed $vmName" $_.Exception.Message
            $stats.Failed++
        }
    }

    Write-Host "`nDONE. Scanned: $($stats.Scanned) | Optimized: $($stats.Optimized) | Failed: $($stats.Failed) | Skipped: $($stats.Skipped)" -ForegroundColor Green
}
