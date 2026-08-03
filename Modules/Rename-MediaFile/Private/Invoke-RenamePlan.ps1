function Invoke-RenamePlan {
    <#
    .SYNOPSIS
        Executes an ordered plan of rename / move / delete operations.
    .DESCRIPTION
        Ordering is fixed by the caller and matters:
          files -> subtitles -> deletes -> directories (deepest first)
        so no operation invalidates a path queued behind it.

        Subtitle moves may target a different directory (flattening out of
        Subs\), which requires Move-Item rather than Rename-Item.
    .PARAMETER Operations
        Ordered operation objects.
    .PARAMETER ApplyAll
        Execute everything without per-item prompting.
    .PARAMETER Interactive
        Prompt for each operation.
    .PARAMETER PermanentDelete
        Bypass the Recycle Bin for Delete operations.
    .PARAMETER Cmdlet
        Calling $PSCmdlet, so ShouldProcess reflects the public function's
        -WhatIf and -Confirm.
    .OUTPUTS
        PSCustomObject audit records.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$Operations,

        [switch]$ApplyAll,
        [switch]$Interactive,
        [switch]$PermanentDelete,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $Audit = [System.Collections.Generic.List[PSCustomObject]]::new()

    $IntChoices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Apply this operation.')
        [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Skip this operation.')
        [System.Management.Automation.Host.ChoiceDescription]::new('&All', 'Apply this and all remaining operations.')
        [System.Management.Automation.Host.ChoiceDescription]::new('&Quit', 'Stop processing.')
    )

    foreach ($Op in $Operations) {
        $Execute = [bool]$ApplyAll

        if ($Interactive) {
            $Caption = if ($Op.Type -eq 'Delete') { 'Delete file' } else { "Rename $($Op.Type)" }
            $Message = if ($Op.Type -eq 'Delete') {
                "Remove '$($Op.OldName)'?"
            } else {
                "'$($Op.OldName)'`n     -> '$($Op.NewName)'?"
            }

            switch ($Host.UI.PromptForChoice($Caption, $Message, $IntChoices, 0)) {
                0 { $Execute = $true }
                1 { $Execute = $false }
                2 { $Execute = $true; $Interactive = $false; $ApplyAll = $true }
                3 {
                    Write-Host "`nStopped by user. Remaining operations were not applied." -ForegroundColor Yellow
                    return $Audit
                }
            }
        }

        if (-not $Execute) {
            Write-Host "[SKIPPED] $($Op.OldName)" -ForegroundColor DarkGray
            $Audit.Add([PSCustomObject]@{
                Status = 'Skipped'; Type = $Op.Type; OldName = $Op.OldName
                NewName = $Op.NewName; OldPath = $Op.OldPath; NewPath = $Op.NewPath
            })
            continue
        }

        # ---------------- DELETE ----------------
        if ($Op.Type -eq 'Delete') {
            $Target = if ($PermanentDelete) { 'Permanently delete' } else { 'Send to Recycle Bin' }
            if ($Cmdlet.ShouldProcess($Op.OldPath, $Target)) {
                try {
                    Remove-FileSafely -Path $Op.OldPath -Permanent:$PermanentDelete -Confirm:$false
                    Write-Host "[DELETED] $($Op.OldName)" -ForegroundColor Red
                    $Audit.Add([PSCustomObject]@{
                        Status = 'Deleted'; Type = 'Delete'; OldName = $Op.OldName
                        NewName = $null; OldPath = $Op.OldPath; NewPath = $null
                    })
                } catch {
                    Write-Host "[FAILED]  Could not delete $($Op.OldName): $_" -ForegroundColor Red
                    $Audit.Add([PSCustomObject]@{
                        Status = 'Error'; Type = 'Delete'; OldName = $Op.OldName
                        NewName = $null; OldPath = $Op.OldPath; NewPath = $null
                    })
                }
            }
            continue
        }

        # ---------------- RENAME / MOVE ----------------
        $IsMove = $Op.PSObject.Properties['Moved'] -and $Op.Moved
        $Verb = if ($IsMove) { "Move to $($Op.NewPath)" } else { "Rename to $($Op.NewName)" }

        if (-not $Cmdlet.ShouldProcess($Op.OldPath, $Verb)) { continue }

        try {
            # Guard: never clobber an unrelated existing file.
            if ((Test-Path -LiteralPath $Op.NewPath) -and
                ($Op.NewPath -ne $Op.OldPath) -and
                -not ($Op.NewPath -ieq $Op.OldPath)) {
                throw "target already exists: $($Op.NewPath)"
            }

            if ($IsMove) {
                $Dest = Split-Path -Path $Op.NewPath -Parent
                if (-not (Test-Path -LiteralPath $Dest)) {
                    New-Item -Path $Dest -ItemType Directory -Force | Out-Null
                }
                Move-Item -LiteralPath $Op.OldPath -Destination $Op.NewPath -ErrorAction Stop
            } else {
                Rename-Item -LiteralPath $Op.OldPath -NewName $Op.NewName -ErrorAction Stop
            }

            $Tag = if ($IsMove) { 'MOVED  ' } else { 'SUCCESS' }
            Write-Host "[$Tag] $($Op.OldName) -> $($Op.NewName)" -ForegroundColor Green

            $Audit.Add([PSCustomObject]@{
                Status = 'Success'; Type = $Op.Type; OldName = $Op.OldName
                NewName = $Op.NewName; OldPath = $Op.OldPath; NewPath = $Op.NewPath
            })
        } catch {
            Write-Host "[FAILED]  $($Op.OldName): $_" -ForegroundColor Red
            $Audit.Add([PSCustomObject]@{
                Status = 'Error'; Type = $Op.Type; OldName = $Op.OldName
                NewName = $Op.NewName; OldPath = $Op.OldPath; NewPath = $Op.NewPath
            })
        }
    }

    return $Audit
}
