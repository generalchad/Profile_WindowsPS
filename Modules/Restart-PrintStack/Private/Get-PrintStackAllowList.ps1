function Get-AllowListPath {
    <#
    .SYNOPSIS
        Resolves the location of the user-editable allow-list file.

    .DESCRIPTION
        Defaults to %APPDATA%\Restart-PrintStack\allowlist.json. Stored per-user
        under APPDATA rather than beside the module so re-cloning the profile
        repository does not discard a technician's pinned printers.

    .PARAMETER ConfigPath
        Explicit path supplied by the caller, used verbatim when present.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $ConfigPath
    )

    if ($ConfigPath) { return $ConfigPath }

    $root = if ($env:APPDATA) {
        $env:APPDATA
    }
    else {
        # PowerShell 7 on a non-Windows host, or a service account with no roaming
        # profile. Neither can print, but the path still has to resolve so that
        # -WhatIf and the unit probes work anywhere.
        Join-Path ([Environment]::GetFolderPath('ApplicationData')) ''
    }

    Join-Path (Join-Path $root $script:AllowListFolderName) $script:AllowListFileName
}

function New-AllowListFile {
    <#
    .SYNOPSIS
        Writes the starter allow-list file with the schema and a worked example.

    .DESCRIPTION
        Created on first run so the technician has something to edit rather than a
        blank file and a guess at the shape. The sample entries are commented via
        the '_comment' keys, which the reader ignores and the writer preserves.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $template = [ordered]@{
        '_comment'      = @(
            'Restart-PrintStack allow-list. Entries are wildcard patterns matched',
            'against the printer name, port name or driver name.',
            'Anything listed in keepPrinters/keepPorts/keepDrivers survives every sweep.',
            'removePrinters wins over every keep rule, including the built-in defaults.'
        )
        'version'       = $script:AllowListSchemaVersion
        'keepPrinters'  = @()
        'keepPorts'     = @()
        'keepDrivers'   = @()
        'removePrinters' = @()
    }

    try {
        # -WhatIf:$false on both writes. Creating the starter file is bookkeeping,
        # not one of the changes the technician is previewing, and letting the
        # preference flow through would emit two confusing "What if: Create
        # Directory" lines above the plan while still leaving no file behind.
        $folder = Split-Path -Path $Path -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) {
            $null = New-Item -Path $folder -ItemType Directory -Force -WhatIf:$false -ErrorAction Stop
        }
        $template | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $Path -Encoding UTF8 -WhatIf:$false -ErrorAction Stop

        Write-Verbose "Created allow-list file: $Path"
        return $true
    }
    catch {
        Write-Warning "Could not create the allow-list file '$Path': $($_.Exception.Message)"
        return $false
    }
}

function Get-PrintStackAllowList {
    <#
    .SYNOPSIS
        Builds the effective allow-list from the built-in defaults, the user's JSON
        file and the per-invocation -Keep / -Remove patterns.

    .DESCRIPTION
        Three layers are merged, in increasing order of authority:

          1. Built-in defaults from _Config.ps1 - the Microsoft virtual printers,
             OneNote, Fax and Adobe, matched by both name and driver.
          2. The user's allow-list file, created on first run if absent.
          3. -Keep and -Remove patterns supplied on the command line.

        Removal beats retention at every layer: a pattern in -Remove or in the
        file's removePrinters list drops an item even if a built-in rule would have
        kept it. That is the only way to get rid of something like a stale Adobe
        queue without editing the module.

    .PARAMETER Keep
        Additional patterns to protect for this invocation only.

    .PARAMETER Remove
        Patterns to force-remove, overriding every keep rule.

    .PARAMETER ConfigPath
        Alternate location for the allow-list file.

    .PARAMETER NoCreate
        Do not create the file when it is missing. Used by read-only callers such
        as Get-PrintStackInventory so simply listing printers never writes to disk.

    .OUTPUTS
        pscustomobject with KeepPrinters, KeepPorts, KeepDrivers, RemovePrinters
        and Path.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]] $Keep = @(),

        [string[]] $Remove = @(),

        [string] $ConfigPath,

        [switch] $NoCreate
    )

    $path = Get-AllowListPath -ConfigPath $ConfigPath

    $keepPrinters = [System.Collections.Generic.List[string]]::new()
    $keepPorts = [System.Collections.Generic.List[string]]::new()
    $keepDrivers = [System.Collections.Generic.List[string]]::new()
    $removePrinters = [System.Collections.Generic.List[string]]::new()

    # Layer 1: built-in defaults.
    foreach ($p in $script:DefaultKeepPrinterNames) { $keepPrinters.Add($p) }
    foreach ($p in $script:DefaultKeepPrinterDrivers) { $keepDrivers.Add($p) }
    foreach ($p in $script:ProtectedPortNames) { $keepPorts.Add($p) }

    # Layer 2: the user's file.
    if (-not (Test-Path -LiteralPath $path)) {
        if (-not $NoCreate) {
            $null = New-AllowListFile -Path $path
        }
    }

    if (Test-Path -LiteralPath $path) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if ($raw -and $raw.Trim()) {
                $json = $raw | ConvertFrom-Json -ErrorAction Stop

                foreach ($key in @('keepPrinters', 'keepPorts', 'keepDrivers', 'removePrinters')) {
                    # A hand-edited file routinely omits keys. Probing with
                    # PSObject.Properties avoids a StrictMode fault on a missing one.
                    if (-not $json.PSObject.Properties[$key]) { continue }

                    $values = @($json.$key) | Where-Object { $_ -is [string] -and $_.Trim() }
                    foreach ($v in $values) {
                        switch ($key) {
                            'keepPrinters' { $keepPrinters.Add($v.Trim()) }
                            'keepPorts' { $keepPorts.Add($v.Trim()) }
                            'keepDrivers' { $keepDrivers.Add($v.Trim()) }
                            'removePrinters' { $removePrinters.Add($v.Trim()) }
                        }
                    }
                }
            }
        }
        catch {
            # A corrupt file must not stop the run, but it must be loud: silently
            # continuing on built-in defaults would delete the very printers the
            # technician pinned.
            Write-Warning "Allow-list file '$path' could not be read and was ignored: $($_.Exception.Message)"
        }
    }

    # Layer 3: command-line patterns.
    foreach ($p in @($Keep) | Where-Object { $_ }) { $keepPrinters.Add($p) }
    foreach ($p in @($Remove) | Where-Object { $_ }) { $removePrinters.Add($p) }

    [pscustomobject]@{
        PSTypeName     = 'RestartPrintStack.AllowList'
        Path           = $path
        KeepPrinters   = @($keepPrinters | Sort-Object -Unique)
        KeepPorts      = @($keepPorts | Sort-Object -Unique)
        KeepDrivers    = @($keepDrivers | Sort-Object -Unique)
        RemovePrinters = @($removePrinters | Sort-Object -Unique)
    }
}

function Test-AllowListMatch {
    <#
    .SYNOPSIS
        Returns the pattern that matched, or $null when nothing did.

    .DESCRIPTION
        Returning the pattern rather than a boolean lets the plan explain itself:
        "kept by allow-list entry 'Adobe PDF*'" is actionable, "kept" is not.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Value,

        [string[]] $Patterns
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    foreach ($pattern in @($Patterns)) {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        if ($Value -like $pattern) { return $pattern }
    }

    return $null
}

function Add-PrintStackAllowListEntry {
    <#
    .SYNOPSIS
        Appends pinned printer and port patterns to the user's allow-list file.

    .DESCRIPTION
        Called once, after the technician confirms the review screen, with every
        pin collected during the session. Writing at the end rather than on each
        keystroke means cancelling the review leaves the file untouched.

        The merge is additive and order-preserving: unknown keys and the '_comment'
        block a technician may have hand-edited are read back and rewritten intact,
        so this never clobbers manual customisation.

        The write is atomic - a temporary file in the same folder is populated and
        then moved over the target - so an interruption mid-write cannot leave a
        truncated allow-list, which would silently un-protect every pinned printer
        on the next run.

    .PARAMETER Printer
        Printer name patterns to add to keepPrinters.

    .PARAMETER Port
        Port name patterns to add to keepPorts.

    .PARAMETER Driver
        Driver name patterns to add to keepDrivers.

    .PARAMETER ConfigPath
        Alternate location for the allow-list file.

    .PARAMETER DryRun
        Report what would be written without touching the file.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]] $Printer = @(),

        [string[]] $Port = @(),

        [string[]] $Driver = @(),

        [string] $ConfigPath,

        [switch] $DryRun
    )

    $path = Get-AllowListPath -ConfigPath $ConfigPath

    $additions = @($Printer).Count + @($Port).Count + @($Driver).Count
    if ($additions -eq 0) {
        return Write-StepResult -Step 'Pin to allow-list' -Method 'File' -Status 'Skipped' `
            -Message 'Nothing was pinned.'
    }

    $summary = @()
    if (@($Printer).Count) { $summary += "$(@($Printer).Count) printer(s)" }
    if (@($Port).Count) { $summary += "$(@($Port).Count) port(s)" }
    if (@($Driver).Count) { $summary += "$(@($Driver).Count) driver(s)" }
    $summaryText = $summary -join ', '

    if ($DryRun) {
        return Write-StepResult -Step 'Pin to allow-list' -Method 'File' -Command $path `
            -Status 'WhatIf' -Message "Would pin $summaryText (file not modified)."
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $folder = Split-Path -Path $path -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) {
            $null = New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop
        }

        # Read the existing document, preserving unknown keys.
        $doc = [ordered]@{}
        if (Test-Path -LiteralPath $path) {
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if ($raw -and $raw.Trim()) {
                $existing = $raw | ConvertFrom-Json -ErrorAction Stop
                foreach ($prop in $existing.PSObject.Properties) {
                    $doc[$prop.Name] = $prop.Value
                }
            }
        }

        if (-not $doc.Contains('version')) { $doc['version'] = $script:AllowListSchemaVersion }

        $map = @{
            'keepPrinters' = $Printer
            'keepPorts'    = $Port
            'keepDrivers'  = $Driver
        }

        foreach ($key in @('keepPrinters', 'keepPorts', 'keepDrivers')) {
            $incoming = @($map[$key]) | Where-Object { $_ -and $_.Trim() }
            $current = @()
            if ($doc.Contains($key) -and $null -ne $doc[$key]) {
                $current = @($doc[$key]) | Where-Object { $_ -is [string] }
            }

            # Case-insensitive de-duplication: pinning the same queue twice across
            # two runs must not grow the file.
            $merged = [System.Collections.Generic.List[string]]::new()
            foreach ($v in @($current) + @($incoming)) {
                $trimmed = "$v".Trim()
                if (-not $trimmed) { continue }
                if (-not ($merged | Where-Object { $_ -ieq $trimmed })) {
                    $merged.Add($trimmed)
                }
            }
            $doc[$key] = @($merged)
        }

        if (-not $doc.Contains('removePrinters')) { $doc['removePrinters'] = @() }

        # Atomic replace: write beside the target, then move over it.
        $temp = "$path.tmp"
        $doc | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temp -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temp -Destination $path -Force -ErrorAction Stop

        $sw.Stop()
        Write-StepResult -Step 'Pin to allow-list' -Method 'File' -Command $path -Status 'Success' `
            -Duration $sw.Elapsed -Message "Pinned $summaryText to $path"
    }
    catch {
        $sw.Stop()
        Write-StepResult -Step 'Pin to allow-list' -Method 'File' -Command $path -Status 'Failed' `
            -Duration $sw.Elapsed -Message $_.Exception.Message
    }
}
