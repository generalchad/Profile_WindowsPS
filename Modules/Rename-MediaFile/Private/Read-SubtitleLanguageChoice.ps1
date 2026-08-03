function Read-SubtitleLanguageChoice {
    <#
    .SYNOPSIS
        Prints a sample of the subtitle and asks the user for a language code.
    .DESCRIPTION
        Tier 3 of the detection cascade. Shows the opening dialogue lines so the
        language is obvious at a glance, then accepts a 2 or 3 letter code, a
        full language name, blank to accept the suggested default, or 's' to skip
        tagging entirely.
    .PARAMETER File
        The subtitle file being identified.
    .PARAMETER Suggestion
        The detector's best guess, offered as the default.
    .PARAMETER SampleLines
        How many dialogue lines to display.
    .OUTPUTS
        A canonical 3 letter code, or $null when the user declines to tag.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [System.IO.FileInfo]$File,

        [Parameter(Position = 1)]
        [AllowNull()]
        [string]$Suggestion,

        [Parameter(Position = 2)]
        [int]$SampleLines = 10
    )

    Write-Host ''
    Write-Host '  ┌─ Unable to determine subtitle language ─────────────────' -ForegroundColor Yellow
    Write-Host "  │ File: $($File.Name)" -ForegroundColor Gray
    Write-Host "  │ Path: $($File.DirectoryName)" -ForegroundColor DarkGray
    Write-Host '  │' -ForegroundColor Yellow

    if ($script:ImageSubtitleExtensions -contains $File.Extension.ToLower()) {
        Write-Host '  │ (image based subtitle - no text available to preview)' -ForegroundColor DarkGray
    } else {
        $Sample = Read-SubtitleSample -Path $File.FullName -LineCount $SampleLines
        if ($Sample -and $Sample.Count -gt 0) {
            foreach ($Line in $Sample) {
                $Display = if ($Line.Length -gt 90) { $Line.Substring(0, 87) + '...' } else { $Line }
                Write-Host "  │   $Display" -ForegroundColor White
            }
        } else {
            Write-Host '  │ (no readable text found)' -ForegroundColor DarkGray
        }
    }

    Write-Host '  └──────────────────────────────────────────────────────────' -ForegroundColor Yellow

    $DefaultText = if ($Suggestion) {
        $Name = if ($script:LanguageNames.ContainsKey($Suggestion)) { $script:LanguageNames[$Suggestion] } else { $Suggestion }
        " [default: $Suggestion ($Name)]"
    } else { '' }

    while ($true) {
        $Answer = Read-Host "  Language code$DefaultText, 's' to skip, '?' to list"

        if ([string]::IsNullOrWhiteSpace($Answer)) {
            if ($Suggestion) { return $Suggestion }
            Write-Host '  No default available - enter a code or "s" to skip.' -ForegroundColor DarkYellow
            continue
        }

        $Answer = $Answer.Trim().ToLower()

        if ($Answer -eq 's' -or $Answer -eq 'skip') { return $null }

        if ($Answer -eq '?') {
            $Codes = @($script:LanguageNames.GetEnumerator() | Sort-Object Key)
            $Line = ''
            foreach ($Entry in $Codes) {
                $Cell = '{0} {1,-13}' -f $Entry.Key, $Entry.Value
                if (($Line.Length + $Cell.Length) -gt 96) {
                    Write-Host "    $Line" -ForegroundColor DarkGray
                    $Line = ''
                }
                $Line += $Cell
            }
            if ($Line) { Write-Host "    $Line" -ForegroundColor DarkGray }
            continue
        }

        if ($script:LanguageMap.ContainsKey($Answer)) { return $script:LanguageMap[$Answer] }

        Write-Host "  '$Answer' is not a recognised language code. Enter '?' to list valid codes." -ForegroundColor DarkYellow
    }
}
