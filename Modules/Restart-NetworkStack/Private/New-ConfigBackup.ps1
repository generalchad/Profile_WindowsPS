function New-ConfigBackupRoot {
    <#
    .SYNOPSIS
        Creates (once per run) the timestamped folder that holds pre-reset backups.

    .OUTPUTS
        The full path to the backup folder, or $null if it could not be created.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $env:TEMP "RestartNetworkStack_$stamp"

    try {
        if (-not (Test-Path -LiteralPath $path)) {
            $null = New-Item -Path $path -ItemType Directory -Force -ErrorAction Stop
        }
        return $path
    }
    catch {
        Write-Warning "Could not create the backup folder '$path': $($_.Exception.Message)"
        return $null
    }
}

function Backup-IPConfiguration {
    <#
    .SYNOPSIS
        Snapshots the current IP configuration before 'netsh int ip reset' wipes it.

    .DESCRIPTION
        Writes two artefacts:
          * ipconfig.xml  - Get-NetIPConfiguration output, for human/scripted review
          * ip-dump.txt   - 'netsh int ip dump', which can be replayed with
                            'netsh exec ip-dump.txt' to restore the previous settings

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $BackupRoot,

        [switch] $DryRun
    )

    $target = Join-Path $BackupRoot 'ip-dump.txt'

    if ($DryRun) {
        return Write-StepResult -Step 'Backup: IP configuration' -Method 'Native' `
            -Command "netsh int ip dump > $target" -Status 'WhatIf' `
            -Message 'Backup was not written (WhatIf).'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue) {
            Get-NetIPConfiguration -Detailed -ErrorAction SilentlyContinue |
                Export-Clixml -Path (Join-Path $BackupRoot 'ipconfig.xml') -ErrorAction SilentlyContinue
        }

        $dump = & netsh.exe int ip dump 2>&1
        $dump | Out-File -FilePath $target -Encoding utf8 -ErrorAction Stop

        $sw.Stop()
        Write-StepResult -Step 'Backup: IP configuration' -Method 'Native' `
            -Command "netsh int ip dump > $target" -Status 'Success' -Duration $sw.Elapsed `
            -Message "Restore with: netsh exec `"$target`""
    }
    catch {
        $sw.Stop()
        Write-StepResult -Step 'Backup: IP configuration' -Method 'Native' `
            -Command "netsh int ip dump > $target" -Status 'Failed' -Duration $sw.Elapsed `
            -Message $_.Exception.Message
    }
}

function Backup-FirewallPolicy {
    <#
    .SYNOPSIS
        Exports the current Windows Defender Firewall policy before it is reset.

    .DESCRIPTION
        Produces a .wfw file that can be restored with 'netsh advfirewall import'.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $BackupRoot,

        [switch] $DryRun
    )

    $target = Join-Path $BackupRoot 'firewall.wfw'

    if ($DryRun) {
        return Write-StepResult -Step 'Backup: firewall policy' -Method 'Native' `
            -Command "netsh advfirewall export `"$target`"" -Status 'WhatIf' `
            -Message 'Backup was not written (WhatIf).'
    }

    $r = Invoke-NativeCommand -Step 'Backup: firewall policy' -FilePath 'netsh.exe' `
        -ArgumentList @('advfirewall', 'export', $target)

    if ($r.Status -eq 'Success') {
        $r.Message = "Restore with: netsh advfirewall import `"$target`""
    }
    $r
}

function Backup-ProxyConfiguration {
    <#
    .SYNOPSIS
        Records the current WinHTTP and WinINET proxy settings before they are cleared.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $BackupRoot,

        [switch] $DryRun
    )

    $target = Join-Path $BackupRoot 'proxy.txt'

    if ($DryRun) {
        return Write-StepResult -Step 'Backup: proxy settings' -Method 'Native' `
            -Command "netsh winhttp show proxy > $target" -Status 'WhatIf' `
            -Message 'Backup was not written (WhatIf).'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('--- netsh winhttp show proxy ---')
        (& netsh.exe winhttp show proxy 2>&1) | ForEach-Object { $lines.Add("$_") }

        $lines.Add('')
        $lines.Add('--- HKCU Internet Settings ---')
        $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $reg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        $lines.Add("ProxyEnable = $($reg.ProxyEnable)")
        $lines.Add("ProxyServer = $($reg.ProxyServer)")
        $lines.Add("AutoConfigURL = $($reg.AutoConfigURL)")

        $lines | Out-File -FilePath $target -Encoding utf8 -ErrorAction Stop

        $sw.Stop()
        Write-StepResult -Step 'Backup: proxy settings' -Method 'Native' `
            -Command "netsh winhttp show proxy > $target" -Status 'Success' -Duration $sw.Elapsed `
            -Message "Previous values recorded in $target"
    }
    catch {
        $sw.Stop()
        Write-StepResult -Step 'Backup: proxy settings' -Method 'Native' `
            -Command "netsh winhttp show proxy > $target" -Status 'Failed' -Duration $sw.Elapsed `
            -Message $_.Exception.Message
    }
}
