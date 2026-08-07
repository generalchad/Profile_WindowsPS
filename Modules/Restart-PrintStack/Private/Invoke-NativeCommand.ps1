function Invoke-NativeCommand {
    <#
    .SYNOPSIS
        Executes a native console executable (rundll32, pnputil, net) and returns a
        normalized step result.

    .DESCRIPTION
        Wraps native command invocation so that:
          * stdout and stderr are captured together
          * the process exit code is preserved
          * -WhatIf from the calling cmdlet short-circuits execution and reports the
            exact command line that would have run
          * a non-zero exit code becomes a 'Failed' status rather than an exception

    .PARAMETER Step
        Friendly name of the step, used in the summary table.

    .PARAMETER Target
        The object acted upon, carried through to the result.

    .PARAMETER FilePath
        The executable to run. Resolved via Get-Command; if it cannot be found the
        step is reported as Skipped.

    .PARAMETER ArgumentList
        Arguments passed to the executable.

    .PARAMETER SuccessExitCodes
        Exit codes to treat as success. Defaults to 0. pnputil in particular returns
        3010 ("reboot required") on an otherwise clean removal, so callers widen this.

    .PARAMETER DryRun
        Report the command without running it.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Step,

        [string] $Target = '',

        [Parameter(Mandatory)]
        [string] $FilePath,

        [string[]] $ArgumentList = @(),

        [int[]] $SuccessExitCodes = @(0),

        [switch] $DryRun
    )

    $display = if ($ArgumentList.Count) {
        '{0} {1}' -f $FilePath, ($ArgumentList -join ' ')
    }
    else {
        $FilePath
    }

    $exe = Get-Command -Name $FilePath -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $exe) {
        return Write-StepResult -Step $Step -Target $Target -Method 'Native' -Command $display `
            -Status 'Skipped' -Message "Executable '$FilePath' was not found on this system."
    }

    if ($DryRun) {
        return Write-StepResult -Step $Step -Target $Target -Method 'Native' -Command $display `
            -Status 'WhatIf' -Message 'Command was not executed (WhatIf).'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = $null
    $exitCode = $null

    try {
        # 2>&1 merges the error stream so tool complaints are captured.
        $output = & $exe.Source @ArgumentList 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        $sw.Stop()
        return Write-StepResult -Step $Step -Target $Target -Method 'Native' -Command $display `
            -Status 'Failed' -Duration $sw.Elapsed -Message $_.Exception.Message
    }

    $sw.Stop()

    $text = (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim()
    if ($text.Length -gt 300) { $text = $text.Substring(0, 297) + '...' }

    $status = if ($SuccessExitCodes -contains $exitCode) { 'Success' } else { 'Failed' }

    Write-StepResult -Step $Step -Target $Target -Method 'Native' -Command $display `
        -Status $status -ExitCode $exitCode -Duration $sw.Elapsed -Message $text
}

function Test-PrintManagementAvailable {
    <#
    .SYNOPSIS
        Returns $true when the PrintManagement cmdlets are usable in this session.

    .DESCRIPTION
        PrintManagement ships with Windows but is absent from some stripped images,
        and under PowerShell 7 it is only reachable through the Windows Compatibility
        shim - which is present far more often than it is functional. Rather than
        trusting Get-Module, the check actually invokes Get-Printer once and caches
        the answer for the rest of the session.

        Every caller has a CIM fallback, so a $false here degrades the run rather
        than failing it.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($null -ne $script:PrintManagementAvailable) {
        return $script:PrintManagementAvailable
    }

    $script:PrintManagementAvailable = $false

    if (-not (Get-Command -Name Get-Printer -ErrorAction SilentlyContinue)) {
        Write-Verbose 'PrintManagement: Get-Printer is not available; using CIM fallbacks.'
        return $script:PrintManagementAvailable
    }

    try {
        $null = Get-Printer -ErrorAction Stop | Select-Object -First 1
        $script:PrintManagementAvailable = $true
        Write-Verbose 'PrintManagement: cmdlets are available.'
    }
    catch {
        Write-Verbose "PrintManagement: Get-Printer failed ($($_.Exception.Message)); using CIM fallbacks."
    }

    return $script:PrintManagementAvailable
}
