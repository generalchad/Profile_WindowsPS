function Show-PrintStackReview {
    <#
    .SYNOPSIS
        Interactive review screen: lets the technician amend the plan and pin
        keepers to the allow-list before anything is deleted.

    .DESCRIPTION
        Replaces a bare "proceed? y/n" with the moment the decision is actually
        informed. The whole print state is on screen, numbered, and the technician
        can act on it directly.

        Two distinct actions, and the distinction is the point:

          keep (k)  exempt for THIS RUN only. Nothing is written to disk.
          pin  (p)  exempt for this run AND every future run, by appending the
                    name to the user's allow-list file.

        Conflating the two is how a tool like this rots: if every "don't delete
        that one" were persisted, six months of site visits would leave an
        allow-list that protects everything and a sweep that cleans nothing.

        Pins are collected but NOT written here. They are returned to the caller
        and committed only after the technician confirms, so cancelling the review
        leaves the allow-list exactly as it was.

    .PARAMETER Plan
        The plan from Get-PrintStackPlan. Amended and returned.

    .PARAMETER NoPortSweep
        Passed through to the plan recompute, so keeping a queue re-protects its
        port under the same rules the original plan used.

    .OUTPUTS
        pscustomobject with Confirmed, Plan, PinnedPrinters, PinnedPorts.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan,

        [switch] $NoPortSweep
    )

    $current = $Plan
    $pinnedPrinters = [System.Collections.Generic.List[string]]::new()
    $pinnedPorts = [System.Collections.Generic.List[string]]::new()
    $message = $null

    while ($true) {
        Write-Host ''
        Write-Host 'Restart-PrintStack - review before removal' -ForegroundColor Cyan
        Write-Host ('=' * 78) -ForegroundColor DarkGray

        Show-PrintStackPlan -Plan $current

        Write-Host ("  {0} item(s) will be REMOVED, {1} kept." -f $current.RemoveCount, $current.KeepCount) `
            -ForegroundColor $(if ($current.RemoveCount) { 'Yellow' } else { 'Green' })

        if ($current.DefaultIsRemoved) {
            Write-Host "  The current default printer ('$($current.DefaultPrinter)') is in the removal list." -ForegroundColor Yellow
            Write-Host '  A surviving printer will be made default afterwards.' -ForegroundColor DarkGray
        }

        if ($pinnedPrinters.Count -or $pinnedPorts.Count) {
            Write-Host ("  {0} item(s) will be pinned to {1}" -f `
                ($pinnedPrinters.Count + $pinnedPorts.Count), $current.AllowList.Path) -ForegroundColor Cyan
        }

        Write-Host ''
        Write-Host '  [Enter] proceed   ' -ForegroundColor Green -NoNewline
        Write-Host '[k 3,5-7] keep this run   ' -NoNewline
        Write-Host '[p 4] pin permanently   ' -ForegroundColor Cyan -NoNewline
        Write-Host '[r 4] remove'
        Write-Host '  [a] keep all      ' -NoNewline
        Write-Host '[n] cancel                ' -ForegroundColor Red -NoNewline
        Write-Host '[?] help'
        Write-Host ''

        if ($message) {
            Write-Host "  $message" -ForegroundColor Yellow
            $message = $null
        }

        # $input is an automatic variable in PowerShell; shadowing it inside a
        # loop is a well-known source of confusing failures, so the answer gets
        # its own name.
        $answer = "$(Read-Host '  >')".Trim()

        # Bare Enter is the common case and means "the plan is right, go".
        if (-not $answer) {

            if ($current.RemoveCount -eq 0) {
                Write-Host '  Nothing to remove.' -ForegroundColor Green
                return New-ReviewResult -Confirmed $false -Plan $current
            }
            return New-ReviewResult -Confirmed $true -Plan $current `
                -PinnedPrinters $pinnedPrinters -PinnedPorts $pinnedPorts
        }

        $parts = $answer -split '\s+', 2
        $verb = $parts[0].ToLowerInvariant()
        $argument = if ($parts.Count -gt 1) { $parts[1] } else { '' }


        switch ($verb) {
            'n' {
                return New-ReviewResult -Confirmed $false -Plan $current
            }
            'q' {
                return New-ReviewResult -Confirmed $false -Plan $current
            }
            'y' {
                if ($current.RemoveCount -eq 0) {
                    Write-Host '  Nothing to remove.' -ForegroundColor Green
                    return New-ReviewResult -Confirmed $false -Plan $current
                }
                return New-ReviewResult -Confirmed $true -Plan $current `
                    -PinnedPrinters $pinnedPrinters -PinnedPorts $pinnedPorts
            }
            'a' {
                foreach ($item in (@($current.Queues) + @($current.Ports) + @($current.Scanners))) {
                    $item.Action = 'Keep'
                    $item.Reason = 'Kept for this run.'
                }
                $current = Update-PrintStackPlan -Plan $current -NoPortSweep:$NoPortSweep
                $message = 'Everything is now marked Keep. Press Enter to exit without changes, or use r to re-select.'
            }
            '?' {
                Show-ReviewHelp
            }
            'h' {
                Show-ReviewHelp
            }
            { $_ -in @('k', 'p', 'r') } {
                $selection = ConvertFrom-IndexSelection -Selection $argument -Maximum (Get-PlanRow -Plan $current).Count
                if (-not $selection.Valid) {
                    $message = $selection.Error
                    break
                }

                $rows = Get-PlanRow -Plan $current
                $touched = 0

                foreach ($i in $selection.Indices) {
                    $item = ($rows | Where-Object { $_.Index -eq $i }).Item
                    if (-not $item) { continue }
                    $touched++

                    switch ($verb) {
                        'k' {
                            $item.Action = 'Keep'
                            $item.Pinned = $false
                            $item.Reason = 'Kept for this run.'
                        }
                        'p' {
                            $item.Action = 'Keep'
                            $item.Pinned = $true
                            $item.Reason = 'Pinned to the allow-list.'

                            # The exact name is recorded rather than a guessed
                            # pattern. A technician pinning "HP LaserJet (Home)"
                            # means that queue, and the file is right there for
                            # anyone who wants to widen it to a wildcard.
                            if ($item.Type -eq 'Port') {
                                if (-not ($pinnedPorts | Where-Object { $_ -ieq $item.Name })) {
                                    $pinnedPorts.Add($item.Name)
                                }
                            }
                            else {
                                if (-not ($pinnedPrinters | Where-Object { $_ -ieq $item.Name })) {
                                    $pinnedPrinters.Add($item.Name)
                                }
                            }
                        }
                        'r' {
                            $item.Action = 'Remove'
                            $item.Pinned = $false
                            $item.Reason = 'Selected for removal.'

                            if ($item.Type -eq 'Port') {
                                $idx = -1
                                for ($j = 0; $j -lt $pinnedPorts.Count; $j++) {
                                    if ($pinnedPorts[$j] -ieq $item.Name) { $idx = $j; break }
                                }
                                if ($idx -ge 0) { $pinnedPorts.RemoveAt($idx) }
                            }
                            else {
                                $idx = -1
                                for ($j = 0; $j -lt $pinnedPrinters.Count; $j++) {
                                    if ($pinnedPrinters[$j] -ieq $item.Name) { $idx = $j; break }
                                }
                                if ($idx -ge 0) { $pinnedPrinters.RemoveAt($idx) }
                            }
                        }
                    }
                }

                # Keeping a queue re-references its port, so the port plan has to
                # be recomputed rather than left stale.
                $current = Update-PrintStackPlan -Plan $current -NoPortSweep:$NoPortSweep

                $verbText = switch ($verb) { 'k' { 'kept' } 'p' { 'pinned' } 'r' { 'marked for removal' } }
                $message = "$touched item(s) $verbText."
            }
            default {
                $message = "Unrecognised command '$verb'. Press ? for help."
            }
        }
    }
}

function Show-ReviewHelp {
    <#
    .SYNOPSIS
        Prints the review screen command reference.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '  Review commands' -ForegroundColor Cyan
    Write-Host '  ---------------' -ForegroundColor DarkGray
    Write-Host '    Enter        Proceed with the plan as shown.'
    Write-Host '    k <list>     Keep the listed rows for THIS RUN only. Nothing is saved.'
    Write-Host '    p <list>     Pin the listed rows: kept now and saved to the allow-list'
    Write-Host '                 file so every future run keeps them too.'
    Write-Host '    r <list>     Mark the listed rows for removal (undoes k or p).'
    Write-Host '    a            Keep everything.'
    Write-Host '    n            Cancel. Nothing is deleted and nothing is saved.'
    Write-Host '    ?            This help.'
    Write-Host ''
    Write-Host '  <list> accepts single numbers, comma-separated lists and ranges:' -ForegroundColor DarkGray
    Write-Host '    k 3          k 3,7,9        k 3-6         k 1,4-6,11' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Keeping a printer automatically protects the port it uses.' -ForegroundColor DarkGray
    Write-Host ''
}

function ConvertFrom-IndexSelection {
    <#
    .SYNOPSIS
        Parses '1,4-6,11' into a validated, de-duplicated list of row indices.

    .DESCRIPTION
        Returns a result object rather than throwing, because a typo at the review
        prompt should redraw with an explanation, not terminate a session the
        technician is halfway through curating.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Selection,

        [int] $Maximum
    )

    $result = [pscustomobject]@{
        Valid   = $false
        Indices = @()
        Error   = ''
    }

    if ([string]::IsNullOrWhiteSpace($Selection)) {
        $result.Error = 'No rows were specified. Example: k 3,5-7'
        return $result
    }

    $indices = [System.Collections.Generic.List[int]]::new()

    foreach ($token in ($Selection -split '[,\s]+' | Where-Object { $_ })) {
        if ($token -match '^(?<from>\d+)\s*-\s*(?<to>\d+)$') {
            $from = [int]$Matches['from']
            $to = [int]$Matches['to']
            if ($from -gt $to) { $from, $to = $to, $from }

            if ($from -lt 1 -or $to -gt $Maximum) {
                $result.Error = "Range '$token' is outside 1-$Maximum."
                return $result
            }
            for ($i = $from; $i -le $to; $i++) {
                if (-not $indices.Contains($i)) { $indices.Add($i) }
            }
        }
        elseif ($token -match '^\d+$') {
            $value = [int]$token
            if ($value -lt 1 -or $value -gt $Maximum) {
                $result.Error = "Row '$token' is outside 1-$Maximum."
                return $result
            }
            if (-not $indices.Contains($value)) { $indices.Add($value) }
        }
        else {
            $result.Error = "'$token' is not a row number or range."
            return $result
        }
    }

    if ($indices.Count -eq 0) {
        $result.Error = 'No valid rows were specified.'
        return $result
    }

    $result.Valid = $true
    $result.Indices = @($indices)
    $result
}

function New-ReviewResult {
    <#
    .SYNOPSIS
        Builds the review screen's return value.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [bool] $Confirmed,

        [Parameter(Mandatory)]
        [pscustomobject] $Plan,

        [AllowEmptyCollection()]
        [object[]] $PinnedPrinters = @(),

        [AllowEmptyCollection()]
        [object[]] $PinnedPorts = @()
    )

    [pscustomobject]@{
        PSTypeName     = 'RestartPrintStack.ReviewResult'
        Confirmed      = $Confirmed
        Plan           = $Plan
        PinnedPrinters = @($PinnedPrinters)
        PinnedPorts    = @($PinnedPorts)
    }
}
