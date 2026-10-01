function Write-QRCodeConsole {
    <#
    .SYNOPSIS
        Draws a QR module matrix to the host as half-block characters.

    .DESCRIPTION
        Each character cell carries two matrix rows: the upper half for the top
        module and the lower half for the bottom one. Because a terminal cell is
        about twice as tall as it is wide, the result is square and scannable.

        QRCoder's matrix already includes a four-module quiet zone, so no border
        is added here. On a VT host the modules are forced to black-on-white via
        ANSI color, which keeps the code readable on either a light or a dark
        terminal theme; otherwise the raw half-blocks are printed and rely on the
        terminal colors.

    .PARAMETER Matrix
        The module matrix from QRCodeData.ModuleMatrix.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[System.Collections.BitArray]]$Matrix
    )

    $escape = [char]27
    $useColor = $Host.UI.SupportsVirtualTerminal -and [string]::IsNullOrEmpty($env:NO_COLOR)

    $blackOnWhite = "$escape[38;2;0;0;0m$escape[48;2;255;255;255m"
    $reset = "$escape[0m"

    $builder = [System.Text.StringBuilder]::new()
    $rowCount = $Matrix.Count
    for ($row = 0; $row -lt $rowCount; $row += 2) {
        $upper = $Matrix[$row]
        $lower = if ($row + 1 -lt $rowCount) { $Matrix[$row + 1] } else { $null }

        if ($useColor) { $null = $builder.Append($blackOnWhite) }

        for ($column = 0; $column -lt $upper.Length; $column++) {
            $top = $upper[$column]
            $bottom = $null -ne $lower -and $lower[$column]

            $glyph = if ($top -and $bottom) { [char]0x2588 }
            elseif ($top) { [char]0x2580 }
            elseif ($bottom) { [char]0x2584 }
            else { ' ' }

            $null = $builder.Append($glyph)
        }

        # Reset before the newline: with the white background still active at end
        # of line, terminals paint the rest of the line white (a stray white bar).
        if ($useColor) { $null = $builder.Append($reset) }
        $null = $builder.Append("`n")
    }

    Write-Host $builder.ToString() -NoNewline
}
