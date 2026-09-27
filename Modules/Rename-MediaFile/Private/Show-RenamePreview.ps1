function Show-RenamePreview {
    <#
    .SYNOPSIS
        Renders the pending operation plan without truncating any names.
    .DESCRIPTION
        Displays pending operations in an interactive Out-GridView window by default,
        providing searchable, sortable, filterable preview of all changes.

        Automatically falls back to console pagination when Out-GridView is unavailable
        (SSH/remote sessions, headless environments) or when -NoPager is specified.

        Console mode uses custom pagination with silent key handling - no keybind
        instructions displayed, Q/Escape quits gracefully without errors.
    .PARAMETER Operations
        Pending operation objects.
    .PARAMETER NoPager
        Force console output mode instead of Out-GridView. Also disables pagination
        when output is small enough to fit on screen.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$Operations,

        [switch]$NoPager
    )

    if ($Operations.Count -eq 0) {
        return
    }

    # Transform operations into a grid-friendly format
    $GridData = foreach ($Op in $Operations) {
        $BaseProps = [ordered]@{
            Type    = $Op.Type
            OldName = $Op.OldName
            NewName = $Op.NewName
        }

        if ($Op.Type -eq 'Delete') {
            $Size = if ($Op.Size -lt 1KB) { "$($Op.Size) B" } else { '{0:N1} KB' -f ($Op.Size / 1KB) }
            $Dest = if ($Op.Permanent) { 'Permanent' } else { 'Recycle Bin' }
            $BaseProps['Size'] = $Size
            $BaseProps['Destination'] = $Dest
            $BaseProps['Location'] = Split-Path -Path $Op.OldPath -Parent
            $BaseProps['Moved'] = $false
        } else {
            $BaseProps['Moved'] = if ($Op.PSObject.Properties['Moved']) { $Op.Moved } else { $false }
            if ($Op.Moved) {
                $BaseProps['NewLocation'] = Split-Path -Path $Op.NewPath -Parent
            }
            if ($Op.PSObject.Properties['Detail'] -and $Op.Detail) {
                $BaseProps['Note'] = $Op.Detail
            }
        }

        $BaseProps['OldPath'] = $Op.OldPath
        if ($Op.NewPath) {
            $BaseProps['NewPath'] = $Op.NewPath
        }

        [PSCustomObject]$BaseProps
    }

    # Try Out-GridView first (unless explicitly disabled)
    if (-not $NoPager) {
        try {
            Write-Host "`n─────────────────────────────────────────────────────────" -ForegroundColor DarkCyan
            Write-Host " PENDING OPERATIONS: $($Operations.Count)" -ForegroundColor Cyan
            Write-Host "─────────────────────────────────────────────────────────" -ForegroundColor DarkCyan
            Write-Host ""

            $TypeCounts = $Operations | Group-Object Type | ForEach-Object {
                "  $($_.Name): $($_.Count)"
            }
            $TypeCounts | ForEach-Object { Write-Host $_ -ForegroundColor White }
            Write-Host ""
            Write-Host "Opening interactive grid view..." -ForegroundColor Yellow
            Write-Host "(Close the grid window to continue)`n" -ForegroundColor DarkGray

            $GridData | Out-GridView -Title "Rename-MediaFile: Pending Operations ($($Operations.Count) items)" -Wait
            return  # Success - we're done
        } catch {
            Write-Verbose "Out-GridView unavailable, falling back to console pagination: $_"
            Write-Host "`nFalling back to console output...`n" -ForegroundColor Yellow
        }
    }

    # =========================================================================
    # CONSOLE FALLBACK: Custom pagination with color-coded output
    # =========================================================================

    # Colour and label per operation type.
    $Style = @{
        'File'      = @{ Label = 'RENAME';   Color = 'White' }
        'Directory' = @{ Label = 'FOLDER';   Color = 'Magenta' }
        'Subtitle'  = @{ Label = 'SUBTITLE'; Color = 'Cyan' }
        'Delete'    = @{ Label = 'DELETE';   Color = 'Red' }
    }

    $Width = try { $Host.UI.RawUI.WindowSize.Width } catch { 120 }
    if (-not $Width -or $Width -lt 40) { $Width = 120 }

    # Build the whole report first so we can decide about paging.
    $Lines = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Add = { param($Text, $Color) $Lines.Add([PSCustomObject]@{ Text = $Text; Color = $Color }) }

    & $Add ('─' * ($Width - 1)) 'DarkCyan'
    & $Add " PENDING OPERATIONS: $($Operations.Count)" 'Cyan'
    & $Add ('─' * ($Width - 1)) 'DarkCyan'
    & $Add '' 'Gray'

    $Index = 0
    foreach ($Op in $Operations) {
        $Index++
        $Info = if ($Style.ContainsKey($Op.Type)) { $Style[$Op.Type] } else { @{ Label = $Op.Type.ToUpper(); Color = 'White' } }

        if ($Op.Type -eq 'Delete') {
            $Size = if ($Op.Size -lt 1KB) { "$($Op.Size) B" } else { '{0:N1} KB' -f ($Op.Size / 1KB) }
            $Dest = if ($Op.Permanent) { 'permanent delete' } else { 'Recycle Bin' }
            & $Add ("{0,4}. [{1}]" -f $Index, $Info.Label) $Info.Color
            & $Add ("      file  {0}  ({1}) -> {2}" -f $Op.OldName, $Size, $Dest) 'Red'
            & $Add ("      in    {0}" -f (Split-Path -Path $Op.OldPath -Parent)) 'DarkGray'
        }
        else {
            $Action = if ($Op.PSObject.Properties['Moved'] -and $Op.Moved) { "$($Info.Label) + MOVE" } else { $Info.Label }
            & $Add ("{0,4}. [{1}]" -f $Index, $Action) $Info.Color
            & $Add ("      from  {0}" -f $Op.OldName) 'DarkGray'
            & $Add ("      to    {0}" -f $Op.NewName) $Info.Color

            if ($Op.PSObject.Properties['Moved'] -and $Op.Moved) {
                & $Add ("      into  {0}" -f (Split-Path -Path $Op.NewPath -Parent)) 'DarkGray'
            }
            if ($Op.PSObject.Properties['Detail'] -and $Op.Detail) {
                & $Add ("      note  {0}" -f $Op.Detail) 'DarkYellow'
            }
        }

        & $Add '' 'Gray'
    }

    # Page only when the report will not fit on screen.
    $Height = try { $Host.UI.RawUI.WindowSize.Height } catch { 40 }
    if (-not $Height -or $Height -lt 10) { $Height = 40 }

    if (-not $NoPager -and $Lines.Count -gt ($Height - 4)) {
        # Custom pagination: no keybind text, silent Q handling.
        $Index = 0
        $PageSize = $Height - 2  # Reserve 2 lines for breathing room

        while ($Index -lt $Lines.Count) {
            $PageEnd = [Math]::Min($Index + $PageSize, $Lines.Count)

            for ($i = $Index; $i -lt $PageEnd; $i++) {
                $Line = $Lines[$i]
                if ([string]::IsNullOrEmpty($Line.Text)) { Write-Host '' }
                else { Write-Host $Line.Text -ForegroundColor $Line.Color }
            }

            $Index = $PageEnd

            # If there's more content, wait for user input
            if ($Index -lt $Lines.Count) {
                try {
                    $Key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                    # Q or Escape quits silently
                    if ($Key.Character -eq 'q' -or $Key.Character -eq 'Q' -or $Key.VirtualKeyCode -eq 27) {
                        break
                    }
                } catch {
                    # ReadKey failed (non-interactive), just continue
                    break
                }
            }
        }
    } else {
        foreach ($Line in $Lines) {
            if ([string]::IsNullOrEmpty($Line.Text)) { Write-Host '' }
            else { Write-Host $Line.Text -ForegroundColor $Line.Color }
        }
    }
}
