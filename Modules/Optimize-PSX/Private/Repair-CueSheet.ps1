function Repair-CueSheet {
    <#
    .SYNOPSIS
        Repairs a broken single-track cue sheet.
    .DESCRIPTION
        Repairs exactly one situation, and only when it is unambiguous: the
        sheet has a single FILE reference, that reference does not resolve, and
        exactly one candidate payload file (.bin/.img/.raw/.iso) sits beside the
        sheet. The reference is then rewritten to the candidate's name.

        Every other case is refused and reported:

          Multi-track sheets       repair by hand; there is no safe inference
          No candidate payload     the data file is genuinely absent
          Several candidates       the correct target cannot be determined

        Sheets that resolve correctly but carry a byte order mark are rewritten
        without one, leaving content untouched. chdman rejects a cue sheet whose
        first bytes are a BOM.

        A .bak copy is written before any modification and an existing .bak is
        never overwritten. Output is UTF-8 without BOM using CRLF line endings.
    .PARAMETER CueSheet
        A parse result from Read-CueSheet.
    .PARAMETER Cmdlet
        Calling $PSCmdlet, so ShouldProcess honours the caller's -WhatIf.
    .OUTPUTS
        PSCustomObject { Repaired, Reason, BackupPath }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [pscustomobject]$CueSheet,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $outcome = [pscustomobject]@{
        Repaired   = $false
        Reason     = ''
        BackupPath = $null
    }

    if ($CueSheet.ParseError) {
        $outcome.Reason = $CueSheet.ParseError
        return $outcome
    }

    $needsBomStrip = $CueSheet.HasBom
    $needsRefFix = -not $CueSheet.IsValid

    if (-not $needsBomStrip -and -not $needsRefFix) {
        $outcome.Reason = 'Sheet is already valid.'
        return $outcome
    }

    if ($needsRefFix -and -not $CueSheet.IsSingleFile) {
        $outcome.Reason = "Multi-track sheet ($($CueSheet.FileReferences.Count) FILE entries, $($CueSheet.MissingFiles.Count) missing). Repair by hand."
        return $outcome
    }

    $newText = $null

    if ($needsRefFix) {
        # Restricted to real track extensions so cover art or a readme can
        # never become a candidate.
        $candidates = @(
            [System.IO.Directory]::EnumerateFiles($CueSheet.Directory) |
                Where-Object {
                    $ext = [System.IO.Path]::GetExtension($_).ToLowerInvariant()
                    $ext -in @('.bin', '.img', '.raw', '.iso')
                }
        )

        if ($candidates.Count -eq 0) {
            $outcome.Reason = 'No candidate data file found beside the sheet.'
            return $outcome
        }
        if ($candidates.Count -gt 1) {
            $outcome.Reason = "Ambiguous: $($candidates.Count) candidate data files beside the sheet."
            return $outcome
        }

        $actualLeaf = [System.IO.Path]::GetFileName($candidates[0])
        $oldLeaf = $CueSheet.FileReferences[0].Name

        # Substitution is scoped to the single FILE line rather than applied
        # across the whole text, so surrounding directives are preserved
        # byte for byte.
        $lines = [System.IO.File]::ReadAllLines($CueSheet.Path)
        $rebuilt = [System.Collections.Generic.List[string]]::new()
        $replaced = $false

        foreach ($line in $lines) {
            if (-not $replaced -and $line -match '(?i)^\s*FILE\s+') {
                $indent = [regex]::Match($line, '^\s*').Value
                $type = [regex]::Match($line, '(?i)\s(?<T>BINARY|MOTOROLA|AIFF|WAVE|MP3)\s*$')
                $typeText = if ($type.Success) { $type.Groups['T'].Value } else { 'BINARY' }
                $rebuilt.Add(('{0}FILE "{1}" {2}' -f $indent, $actualLeaf, $typeText))
                $replaced = $true
            } else {
                $rebuilt.Add($line)
            }
        }

        $newText = ($rebuilt -join "`r`n") + "`r`n"
        $outcome.Reason = "Reference '$oldLeaf' -> '$actualLeaf'"
    } else {
        $newText = ([System.IO.File]::ReadAllLines($CueSheet.Path) -join "`r`n") + "`r`n"
        $outcome.Reason = "Removed $($CueSheet.Encoding) byte order mark"
    }

    $action = "Repair cue sheet ($($outcome.Reason))"
    if (-not $Cmdlet.ShouldProcess($CueSheet.Path, $action)) {
        $outcome.Reason = "WhatIf: would repair - $($outcome.Reason)"
        return $outcome
    }

    try {
        $backup = "$($CueSheet.Path).bak"
        if (-not [System.IO.File]::Exists($backup)) {
            [System.IO.File]::Copy($CueSheet.Path, $backup)
            $outcome.BackupPath = $backup
        }

        # UTF8Encoding($false) emits no BOM, and preserves non-ASCII characters
        # that may legitimately appear in a track filename.
        [System.IO.File]::WriteAllText($CueSheet.Path, $newText, [System.Text.UTF8Encoding]::new($false))
        $outcome.Repaired = $true
    } catch {
        $outcome.Reason = "Repair failed: $($_.Exception.Message)"
    }

    return $outcome
}
