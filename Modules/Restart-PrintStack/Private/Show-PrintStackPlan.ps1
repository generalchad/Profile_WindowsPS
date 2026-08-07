function Show-PrintStackPlan {
    <#
    .SYNOPSIS
        Renders the plan as a numbered table.

    .DESCRIPTION
        Used both by -WhatIf and as the redraw for the interactive review screen,
        so the technician sees exactly the same rows in both places and the row
        numbers referenced by the review commands are stable.

        Row numbering is assigned across the whole plan in display order
        (printers, then ports, then scanners) rather than per section, because the
        review commands take a single flat list of indices.

    .PARAMETER Plan
        The plan from Get-PrintStackPlan.

    .PARAMETER ShowKept
        Include the rows that will be kept. On by default in the review screen so
        the technician can see the machine's whole print state; suppressed with
        -RemovalsOnly on very long lists.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [pscustomobject] $Plan,

        [switch] $RemovalsOnly
    )

    $rows = Get-PlanRow -Plan $Plan
    if ($RemovalsOnly) {
        $rows = @($rows | Where-Object { $_.Item.Action -eq 'Remove' })
    }

    if (-not $rows -or $rows.Count -eq 0) {
        Write-Host '  Nothing to display - the print system is already at its default state.' -ForegroundColor Green
        Write-Host ''
        return
    }

    # Column widths are computed from the data so a long queue name is not
    # truncated into ambiguity; the technician is about to delete these.
    $nameWidth = [Math]::Min(40, [Math]::Max(20, (@($rows | ForEach-Object { "$($_.Item.Name)".Length }) | Measure-Object -Maximum).Maximum))
    $detailWidth = [Math]::Min(24, [Math]::Max(12, (@($rows | ForEach-Object { "$($_.Item.Detail)".Length }) | Measure-Object -Maximum).Maximum))

    Write-Host ''
    $header = '  {0,3}  {1,-7} {2,-8} {3,-' + $nameWidth + '} {4,-' + $detailWidth + '} {5}'

    Write-Host ($header -f '#', 'Action', 'Type', 'Name', 'Port / Address', 'Reason') -ForegroundColor DarkGray
    Write-Host ('  ' + ('-' * (3 + 2 + 7 + 1 + 8 + 1 + $nameWidth + 1 + $detailWidth + 1 + 30))) -ForegroundColor DarkGray

    foreach ($row in $rows) {
        $item = $row.Item

        $action = if ($item.Pinned) { 'PIN' } elseif ($item.Action -eq 'Remove') { 'REMOVE' } else { 'KEEP' }
        $color = switch ($action) {
            'REMOVE' { 'Yellow' }
            'PIN' { 'Cyan' }
            default { 'Green' }
        }

        $name = Format-PlanField -Value $item.Name -Width $nameWidth
        $detail = Format-PlanField -Value $item.Detail -Width $detailWidth

        Write-Host ('  {0,3}  ' -f $row.Index) -NoNewline
        Write-Host ('{0,-7} ' -f $action) -ForegroundColor $color -NoNewline
        Write-Host ('{0,-8} ' -f $item.Type) -ForegroundColor DarkGray -NoNewline
        Write-Host (('{0,-' + $nameWidth + '} ') -f $name) -NoNewline
        Write-Host (('{0,-' + $detailWidth + '} ') -f $detail) -ForegroundColor DarkGray -NoNewline

        $marker = if ($item.IsDefault) { '[default] ' } else { '' }
        Write-Host "$marker$($item.Reason)" -ForegroundColor DarkGray
    }

    Write-Host ''
}

function Get-PlanRow {
    <#
    .SYNOPSIS
        Flattens the plan into numbered rows for display and index-based selection.

    .DESCRIPTION
        The review screen and the renderer must agree on what "row 4" means, so
        the numbering lives in exactly one place. Order is printers, ports, then
        scanners - the order in which the removals will actually be carried out,
        so reading the table top to bottom describes the run.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Plan
    )

    $index = 0
    $rows = foreach ($item in (@($Plan.Queues) + @($Plan.Ports) + @($Plan.Scanners))) {
        $index++
        [pscustomobject]@{
            Index = $index
            Item  = $item
        }
    }

    @($rows)
}

function Format-PlanField {
    <#
    .SYNOPSIS
        Truncates a display value with an ellipsis so columns stay aligned.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Value,
        [int] $Width
    )

    $text = "$Value"
    if ($text.Length -le $Width) { return $text }
    if ($Width -le 3) { return $text.Substring(0, $Width) }
    $text.Substring(0, $Width - 3) + '...'
}
