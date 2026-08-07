function Write-StepResult {
    <#
    .SYNOPSIS
        Creates a normalized result object for a single print-stack step.

    .DESCRIPTION
        Every action performed by Restart-PrintStack emits one of these objects so
        the final summary table and the -PassThru output are consistent regardless
        of whether the work was done by a cmdlet, a CIM method or a native tool.

    .PARAMETER Step
        Friendly name of the step, used in the summary table.

    .PARAMETER Target
        The object acted upon - a queue name, port name or device instance.

    .PARAMETER Method
        How the work was carried out. Recorded so a summary can show that a
        deletion fell back from Remove-Printer to printui.dll.

    .PARAMETER Command
        The command line or cmdlet expression that was (or would have been) run.

    .PARAMETER Status
        Success, Failed, Skipped or WhatIf.

    .NOTES
        Private helper. Not exported.

        The object is intentionally mutable: callers amend Message after the fact
        to append restore hints or retry outcomes.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Step,

        [string] $Target = '',

        [ValidateSet('Cmdlet', 'CIM', 'Native', 'Registry', 'File', 'None')]
        [string] $Method = 'None',

        [string] $Command = '',

        [ValidateSet('Success', 'Failed', 'Skipped', 'WhatIf')]
        [string] $Status = 'Success',

        [Nullable[int]] $ExitCode = $null,

        [timespan] $Duration = [timespan]::Zero,

        [string] $Message = ''
    )

    [pscustomobject]@{
        PSTypeName = 'RestartPrintStack.StepResult'
        Step       = $Step
        Target     = $Target
        Method     = $Method
        Command    = $Command
        Status     = $Status
        ExitCode   = $ExitCode
        Duration   = $Duration
        Message    = $Message
    }
}
