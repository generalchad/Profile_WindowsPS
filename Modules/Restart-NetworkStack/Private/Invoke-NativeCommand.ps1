function Invoke-NativeCommand {
    <#
    .SYNOPSIS
        Executes a native console executable (ipconfig, netsh, arp, nbtstat...) and
        returns a normalized step result.

    .DESCRIPTION
        Wraps native command invocation so that:
          * stdout and stderr are captured together
          * the process exit code is preserved
          * -WhatIf from the calling cmdlet short-circuits execution and reports the
            exact command line that would have run
          * a non-zero exit code becomes a 'Failed' status rather than an exception

    .PARAMETER Step
        Friendly name of the step, used in the summary table.

    .PARAMETER FilePath
        The executable to run. Resolved via Get-Command; if it cannot be found the
        step is reported as Skipped.

    .PARAMETER ArgumentList
        Arguments passed to the executable.

    .PARAMETER SuccessExitCodes
        Exit codes to treat as success. Defaults to 0. Some netsh operations return
        non-zero on benign conditions (e.g. nothing to reset), so callers can widen this.

    .PARAMETER WhatIfPreferenceOverride
        Set by the caller (usually $PSCmdlet.ShouldProcess result) to indicate the
        command must not actually run.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Step,

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
        return Write-StepResult -Step $Step -Method 'Native' -Command $display `
            -Status 'Skipped' -Message "Executable '$FilePath' was not found on this system."
    }

    if ($DryRun) {
        return Write-StepResult -Step $Step -Method 'Native' -Command $display `
            -Status 'WhatIf' -Message 'Command was not executed (WhatIf).'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = $null
    $exitCode = $null

    try {
        # 2>&1 merges the error stream so netsh/ipconfig complaints are captured.
        $output = & $exe.Source @ArgumentList 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        $sw.Stop()
        return Write-StepResult -Step $Step -Method 'Native' -Command $display `
            -Status 'Failed' -Duration $sw.Elapsed -Message $_.Exception.Message
    }

    $sw.Stop()

    $text = (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim()
    if ($text.Length -gt 300) { $text = $text.Substring(0, 297) + '...' }

    $status = if ($SuccessExitCodes -contains $exitCode) { 'Success' } else { 'Failed' }

    Write-StepResult -Step $Step -Method 'Native' -Command $display `
        -Status $status -ExitCode $exitCode -Duration $sw.Elapsed `
        -Message $text
}
