function Show-RenamePreview {
    <#
    .SYNOPSIS
        Renders the pending operation plan without truncating any names.
    .DESCRIPTION
        Format-Table clips long release names even with -AutoSize, which makes the
        preview useless for exactly the files that need review most. This renders
        one operation per block, full names intact, wrapping instead of clipping.

        Output is paged through Out-Host -Paging when it exceeds the console
        height so it does not scroll past. Space advances, Q quits, and the
        terminal's own scrollback still works once output has flushed.
    .PARAMETER Operations
        Pending operation objects.
    .PARAMETER NoPager
        Emit everything at once without paging.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$Operations,

        [switch]$NoPager
    )

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
        # Out-Host -Paging cannot carry colour, so emit plain text when paging.
        $Lines | ForEach-Object { $_.Text } | Out-Host -Paging
    } else {
        foreach ($Line in $Lines) {
            if ([string]::IsNullOrEmpty($Line.Text)) { Write-Host '' }
            else { Write-Host $Line.Text -ForegroundColor $Line.Color }
        }
    }
}
