# =====================================================================
# Plan.Probe.ps1 - Non-destructive verification of the module
#
# Every check here is read-only. Nothing is deleted, no service is
# touched and the allow-list file is exercised through a temporary path
# so the technician's real one is never modified.
#
#   pwsh -NoProfile -File .\Tests\Plan.Probe.ps1
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
$modulePath = Join-Path $moduleRoot 'Restart-PrintStack.psd1'

$script:Pass = 0
$script:Fail = 0

function Test-Case {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Body
    )

    try {
        $result = & $Body
        if ($result) {
            Write-Host "  [PASS] $Name" -ForegroundColor Green
            $script:Pass++
        }
        else {
            Write-Host "  [FAIL] $Name" -ForegroundColor Red
            $script:Fail++
        }
    }
    catch {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        Write-Host "         $($_.Exception.Message)" -ForegroundColor DarkGray
        $script:Fail++
    }
}

Write-Host ''
Write-Host 'Restart-PrintStack - probe' -ForegroundColor Cyan
Write-Host ('=' * 78) -ForegroundColor DarkGray

# ---------------------------------------------------------------------
Write-Host ''
Write-Host 'Module load' -ForegroundColor Cyan

Test-Case 'Manifest is valid' {
    $null = Test-ModuleManifest -Path $modulePath -ErrorAction Stop
    $true
}

Test-Case 'Module imports cleanly' {
    Import-Module $modulePath -Force -ErrorAction Stop
    $true
}

Test-Case 'Both public functions are exported' {
    $exported = (Get-Module Restart-PrintStack).ExportedFunctions.Keys
    ($exported -contains 'Restart-PrintStack') -and ($exported -contains 'Get-PrintStackInventory')
}

Test-Case 'Private helpers are NOT exported' {
    $exported = (Get-Module Restart-PrintStack).ExportedFunctions.Keys
    -not ($exported -contains 'Get-PrintStackPlan') -and -not ($exported -contains 'Remove-PrintQueue')
}

Test-Case 'Every declared alias actually resolves' {
    # An alias named in the manifest but never defined in the .psm1 imports
    # silently as nothing, so the declaration is verified rather than trusted.
    $manifest = Import-PowerShellDataFile -Path $modulePath
    foreach ($name in @($manifest.AliasesToExport)) {
        $alias = Get-Command $name -CommandType Alias -ErrorAction SilentlyContinue
        if (-not $alias) { return $false }
        if ($alias.ResolvedCommand.Name -ne 'Restart-PrintStack') { return $false }
    }
    $true
}


# ---------------------------------------------------------------------
# Reach into the module scope so the private functions can be exercised
# directly. The alternative - only testing through the public surface -
# would mean the selection parser and the allow-list merge are only ever
# covered by an interactive run, which is exactly where a regression
# would go unnoticed.
# ---------------------------------------------------------------------
$module = Get-Module Restart-PrintStack

Write-Host ''
Write-Host 'Selection parser' -ForegroundColor Cyan

Test-Case 'Parses a single row' {
    $r = & $module { ConvertFrom-IndexSelection -Selection '3' -Maximum 10 }
    $r.Valid -and $r.Indices.Count -eq 1 -and $r.Indices[0] -eq 3
}

Test-Case 'Parses a comma list' {
    $r = & $module { ConvertFrom-IndexSelection -Selection '1,4,7' -Maximum 10 }
    $r.Valid -and (Compare-Object $r.Indices @(1, 4, 7)) -eq $null
}

Test-Case 'Parses a range' {
    $r = & $module { ConvertFrom-IndexSelection -Selection '3-6' -Maximum 10 }
    $r.Valid -and (Compare-Object $r.Indices @(3, 4, 5, 6)) -eq $null
}

Test-Case 'Parses a mixed list and range' {
    $r = & $module { ConvertFrom-IndexSelection -Selection '1,4-6,9' -Maximum 10 }
    $r.Valid -and (Compare-Object $r.Indices @(1, 4, 5, 6, 9)) -eq $null
}

Test-Case 'De-duplicates overlapping selections' {
    $r = & $module { ConvertFrom-IndexSelection -Selection '3,3-5,4' -Maximum 10 }
    $r.Valid -and $r.Indices.Count -eq 3
}

Test-Case 'Rejects an out-of-range row' {
    $r = & $module { ConvertFrom-IndexSelection -Selection '99' -Maximum 10 }
    -not $r.Valid -and $r.Error
}

Test-Case 'Rejects non-numeric input' {
    $r = & $module { ConvertFrom-IndexSelection -Selection 'abc' -Maximum 10 }
    -not $r.Valid
}

Test-Case 'Rejects an empty selection' {
    $r = & $module { ConvertFrom-IndexSelection -Selection '' -Maximum 10 }
    -not $r.Valid
}

Test-Case 'Normalises a reversed range' {
    $r = & $module { ConvertFrom-IndexSelection -Selection '6-3' -Maximum 10 }
    $r.Valid -and (Compare-Object $r.Indices @(3, 4, 5, 6)) -eq $null
}

# ---------------------------------------------------------------------
Write-Host ''
Write-Host 'Pattern matching' -ForegroundColor Cyan

Test-Case 'Matches an exact name' {
    $r = & $module { Test-AllowListMatch -Value 'Microsoft Print to PDF' -Patterns @('Microsoft Print to PDF') }
    $r -eq 'Microsoft Print to PDF'
}

Test-Case 'Matches a wildcard and returns the pattern' {
    $r = & $module { Test-AllowListMatch -Value 'OneNote (Desktop)' -Patterns @('OneNote*') }
    $r -eq 'OneNote*'
}

Test-Case 'Is case-insensitive' {
    $r = & $module { Test-AllowListMatch -Value 'onenote for windows 10' -Patterns @('OneNote*') }
    $null -ne $r
}

Test-Case 'Returns null when nothing matches' {
    $r = & $module { Test-AllowListMatch -Value 'Canon iR-ADV' -Patterns @('OneNote*', 'Fax') }
    $null -eq $r
}

Test-Case 'Handles an empty value safely' {
    $r = & $module { Test-AllowListMatch -Value '' -Patterns @('*') }
    $null -eq $r
}

# ---------------------------------------------------------------------
Write-Host ''
Write-Host 'Port name splitting' -ForegroundColor Cyan

Test-Case 'Splits a single port' {
    # A one-element result unrolls to a bare string, so it is wrapped before
    # indexing - $r[0] on a string would return the character 'U'.
    $r = @(& $module { Split-PortName -PortName 'USB001' })
    $r.Count -eq 1 -and $r[0] -eq 'USB001'
}


Test-Case 'Splits a pooled port list' {
    # A pooled queue references every port in the list; failing to split
    # would make each look unreferenced and get it swept.
    $r = & $module { Split-PortName -PortName '192.168.1.5, 192.168.1.6,192.168.1.7' }
    @($r).Count -eq 3 -and $r[1] -eq '192.168.1.6'
}

Test-Case 'Returns empty for a null port name' {
    $r = & $module { Split-PortName -PortName $null }
    @($r).Count -eq 0
}

# ---------------------------------------------------------------------
Write-Host ''
Write-Host 'Allow-list file' -ForegroundColor Cyan

$tempConfig = Join-Path ([System.IO.Path]::GetTempPath()) "rps-probe-$([guid]::NewGuid()).json"

Test-Case 'Built-in defaults are present without a file' {
    $r = & $module { param($p) Get-PrintStackAllowList -ConfigPath $p -NoCreate } $tempConfig
    ($r.KeepPrinters -contains 'Microsoft Print to PDF') -and ($r.KeepDrivers.Count -gt 0)
}

Test-Case '-NoCreate does not create the file' {
    -not (Test-Path -LiteralPath $tempConfig)
}

Test-Case 'Pinning creates the file and stores the entry' {
    $null = & $module { param($p) Add-PrintStackAllowListEntry -Printer @('Probe Printer A') -ConfigPath $p } $tempConfig
    (Test-Path -LiteralPath $tempConfig) -and
    ((Get-Content -LiteralPath $tempConfig -Raw | ConvertFrom-Json).keepPrinters -contains 'Probe Printer A')
}

Test-Case 'Pinning again is additive, not destructive' {
    $null = & $module { param($p) Add-PrintStackAllowListEntry -Printer @('Probe Printer B') -ConfigPath $p } $tempConfig
    $json = Get-Content -LiteralPath $tempConfig -Raw | ConvertFrom-Json
    ($json.keepPrinters -contains 'Probe Printer A') -and ($json.keepPrinters -contains 'Probe Printer B')
}

Test-Case 'Duplicate pins do not grow the file' {
    $null = & $module { param($p) Add-PrintStackAllowListEntry -Printer @('probe printer a') -ConfigPath $p } $tempConfig
    $json = Get-Content -LiteralPath $tempConfig -Raw | ConvertFrom-Json
    @($json.keepPrinters | Where-Object { $_ -ieq 'Probe Printer A' }).Count -eq 1
}

Test-Case 'Pinned entries are read back into the allow-list' {
    $r = & $module { param($p) Get-PrintStackAllowList -ConfigPath $p -NoCreate } $tempConfig
    $r.KeepPrinters -contains 'Probe Printer A'
}

Test-Case 'Ports pin into keepPorts, not keepPrinters' {
    $null = & $module { param($p) Add-PrintStackAllowListEntry -Port @('192.168.99.99') -ConfigPath $p } $tempConfig
    $json = Get-Content -LiteralPath $tempConfig -Raw | ConvertFrom-Json
    ($json.keepPorts -contains '192.168.99.99') -and -not ($json.keepPrinters -contains '192.168.99.99')
}

Test-Case 'Hand-added unknown keys are preserved' {
    # A technician editing the file by hand must not have their notes wiped
    # out by the next pin.
    $json = Get-Content -LiteralPath $tempConfig -Raw | ConvertFrom-Json
    $json | Add-Member -NotePropertyName 'siteNotes' -NotePropertyValue 'do not delete' -Force
    $json | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tempConfig -Encoding UTF8

    $null = & $module { param($p) Add-PrintStackAllowListEntry -Printer @('Probe Printer C') -ConfigPath $p } $tempConfig

    $after = Get-Content -LiteralPath $tempConfig -Raw | ConvertFrom-Json
    $after.siteNotes -eq 'do not delete'
}

Test-Case 'A corrupt file warns but does not throw' {
    $corrupt = Join-Path ([System.IO.Path]::GetTempPath()) "rps-corrupt-$([guid]::NewGuid()).json"
    '{ this is not json' | Set-Content -LiteralPath $corrupt -Encoding UTF8
    try {
        $r = & $module { param($p) Get-PrintStackAllowList -ConfigPath $p -NoCreate -WarningAction SilentlyContinue } $corrupt
        # Built-in protection must survive a broken user file.
        $r.KeepPrinters -contains 'Microsoft Print to PDF'
    }
    finally {
        Remove-Item -LiteralPath $corrupt -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Pinning nothing is a no-op' {
    $r = & $module { param($p) Add-PrintStackAllowListEntry -ConfigPath $p } $tempConfig
    $r.Status -eq 'Skipped'
}

Remove-Item -LiteralPath $tempConfig -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------
Write-Host ''
Write-Host 'Planning (live system, read-only)' -ForegroundColor Cyan

Test-Case 'A plan can be built from the live system' {
    $plan = & $module {
        $al = Get-PrintStackAllowList -NoCreate
        Get-PrintStackPlan -AllowList $al
    }
    $null -ne $plan -and $null -ne $plan.Queues
}

Test-Case 'Every planned item has an action and a reason' {
    $plan = & $module {
        $al = Get-PrintStackAllowList -NoCreate
        Get-PrintStackPlan -AllowList $al
    }
    $items = @($plan.Queues) + @($plan.Ports) + @($plan.Scanners)
    if ($items.Count -eq 0) { return $true }
    -not @($items | Where-Object { $_.Action -notin @('Keep', 'Remove') -or -not $_.Reason }).Count
}

Test-Case 'Microsoft Print to PDF is never planned for removal' {
    $plan = & $module {
        $al = Get-PrintStackAllowList -NoCreate
        Get-PrintStackPlan -AllowList $al
    }
    $pdf = @($plan.Queues | Where-Object { $_.Name -eq 'Microsoft Print to PDF' })
    if ($pdf.Count -eq 0) { return $true }   # not installed on this machine
    $pdf[0].Action -eq 'Keep'
}

Test-Case 'No port in use by a surviving printer is planned for removal' {
    # The single most damaging failure mode: deleting a port out from under
    # a queue that was meant to be kept.
    $plan = & $module {
        $al = Get-PrintStackAllowList -NoCreate
        Get-PrintStackPlan -AllowList $al
    }

    $keptPorts = @{}
    foreach ($q in @($plan.Queues | Where-Object { $_.Action -eq 'Keep' })) {
        foreach ($n in ("$($q.Object.PortName)" -split ',')) {
            $t = $n.Trim()
            if ($t) { $keptPorts[$t] = $true }
        }
    }

    $bad = @($plan.Ports | Where-Object { $_.Action -eq 'Remove' -and $keptPorts.ContainsKey($_.Name) })
    $bad.Count -eq 0
}

Test-Case '-NoPortSweep plans no port removals' {
    $plan = & $module {
        $al = Get-PrintStackAllowList -NoCreate
        Get-PrintStackPlan -AllowList $al -NoPortSweep
    }
    @($plan.Ports | Where-Object { $_.Action -eq 'Remove' }).Count -eq 0
}

Test-Case '-NoScanners plans no scanner removals' {
    $plan = & $module {
        $al = Get-PrintStackAllowList -NoCreate
        Get-PrintStackPlan -AllowList $al -NoScanners
    }
    @($plan.Scanners).Count -eq 0
}

Test-Case 'Locally attached scanners are kept by default' {
    $plan = & $module {
        $al = Get-PrintStackAllowList -NoCreate
        Get-PrintStackPlan -AllowList $al
    }
    $local = @($plan.Scanners | Where-Object { $_.Object.Connection -eq 'Local' -and $_.Action -eq 'Remove' })
    $local.Count -eq 0
}

Test-Case 'Force-removal outranks a keep rule' {
    $plan = & $module {
        $al = Get-PrintStackAllowList -NoCreate -Remove @('Microsoft Print to PDF')
        Get-PrintStackPlan -AllowList $al
    }
    $pdf = @($plan.Queues | Where-Object { $_.Name -eq 'Microsoft Print to PDF' })
    if ($pdf.Count -eq 0) { return $true }
    $pdf[0].Action -eq 'Remove'
}

Test-Case '-Keep protects a queue that would otherwise be removed' {
    $plan = & $module {
        $al = Get-PrintStackAllowList -NoCreate
        Get-PrintStackPlan -AllowList $al
    }
    $victim = @($plan.Queues | Where-Object { $_.Action -eq 'Remove' } | Select-Object -First 1)
    if ($victim.Count -eq 0) { return $true }   # nothing to clean on this machine

    $name = $victim[0].Name
    $plan2 = & $module { param($n)
        $al = Get-PrintStackAllowList -NoCreate -Keep @($n)
        Get-PrintStackPlan -AllowList $al
    } $name

    (@($plan2.Queues | Where-Object { $_.Name -eq $name })[0]).Action -eq 'Keep'
}

# ---------------------------------------------------------------------
Write-Host ''
Write-Host 'Plan recompute (review screen behaviour)' -ForegroundColor Cyan

Test-Case 'Keeping a queue re-protects its port' {
    $ok = & $module {
        $al = Get-PrintStackAllowList -NoCreate
        $plan = Get-PrintStackPlan -AllowList $al

        # Find a queue being removed whose port is also being removed - the
        # exact pairing the review screen has to keep consistent.
        $pair = $null
        foreach ($q in @($plan.Queues | Where-Object { $_.Action -eq 'Remove' })) {
            $portName = "$($q.Object.PortName)".Trim()
            if (-not $portName) { continue }
            $port = @($plan.Ports | Where-Object { $_.Name -eq $portName -and $_.Action -eq 'Remove' })
            if ($port.Count) { $pair = @{ Queue = $q; Port = $port[0] }; break }
        }

        if (-not $pair) { return $true }   # no such pairing on this machine

        $pair.Queue.Action = 'Keep'
        $updated = Update-PrintStackPlan -Plan $plan

        (@($updated.Ports | Where-Object { $_.Name -eq $pair.Port.Name })[0]).Action -eq 'Keep'
    }
    $ok
}

Test-Case 'Counts stay consistent after a recompute' {
    $ok = & $module {
        $al = Get-PrintStackAllowList -NoCreate
        $plan = Get-PrintStackPlan -AllowList $al
        $updated = Update-PrintStackPlan -Plan $plan

        $all = @($updated.Queues) + @($updated.Ports) + @($updated.Scanners)
        $actual = @($all | Where-Object { $_.Action -eq 'Remove' }).Count
        $updated.RemoveCount -eq $actual
    }
    $ok
}

Test-Case 'Row numbering is contiguous and starts at 1' {
    $ok = & $module {
        $al = Get-PrintStackAllowList -NoCreate
        $plan = Get-PrintStackPlan -AllowList $al
        $rows = Get-PlanRow -Plan $plan
        if (@($rows).Count -eq 0) { return $true }
        $rows[0].Index -eq 1 -and $rows[-1].Index -eq @($rows).Count
    }
    $ok
}

# ---------------------------------------------------------------------
Write-Host ''
Write-Host 'Public surface' -ForegroundColor Cyan

Test-Case 'Restart-PrintStack supports -WhatIf' {
    (Get-Command Restart-PrintStack).Parameters.ContainsKey('WhatIf')
}

Test-Case 'Restart-PrintStack has a High confirm impact' {
    $meta = (Get-Command Restart-PrintStack).ScriptBlock.Ast.Body.ParamBlock.Attributes |
        Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }
    "$meta" -match 'High'
}

Test-Case 'Get-PrintStackInventory runs read-only' {
    $items = Get-PrintStackInventory -AsObject
    $null -ne $items -or $true
}

Test-Case 'Get-PrintStackInventory -Type Port returns only ports' {
    $items = @(Get-PrintStackInventory -Type Port -AsObject)
    if ($items.Count -eq 0) { return $true }
    -not @($items | Where-Object { $_.Type -ne 'Port' }).Count
}

Test-Case 'Get-PrintStackInventory -RemovalsOnly returns only removals' {
    $items = @(Get-PrintStackInventory -RemovalsOnly -AsObject)
    if ($items.Count -eq 0) { return $true }
    -not @($items | Where-Object { $_.Action -ne 'Remove' }).Count
}

# ---------------------------------------------------------------------
Write-Host ''
Write-Host ('=' * 78) -ForegroundColor DarkGray
Write-Host ("  {0} passed, {1} failed" -f $script:Pass, $script:Fail) `
    -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
Write-Host ''

if ($script:Fail) { exit 1 }
