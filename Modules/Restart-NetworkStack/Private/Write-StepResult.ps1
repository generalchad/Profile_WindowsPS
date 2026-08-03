function Write-StepResult {
    <#
    .SYNOPSIS
        Creates a normalized result object for a single network-reset step.

    .DESCRIPTION
        Every step performed by Restart-NetworkStack emits one of these objects so the
        final summary table and the -PassThru output are consistent.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Step,

        [ValidateSet('Cmdlet', 'Native', 'Registry', 'None')]
        [string] $Method = 'None',

        [string] $Command = '',

        [ValidateSet('Success', 'Failed', 'Skipped', 'WhatIf')]
        [string] $Status = 'Success',

        [Nullable[int]] $ExitCode = $null,

        [timespan] $Duration = [timespan]::Zero,

        [string] $Message = ''
    )

    # Note: this object is intentionally mutable - callers (e.g. the backup helpers)
    # amend Message after the fact to append restore instructions.
    [pscustomobject]@{
        PSTypeName = 'RestartNetworkStack.StepResult'
        Step       = $Step
        Method     = $Method
        Command    = $Command
        Status     = $Status
        ExitCode   = $ExitCode
        Duration   = $Duration
        Message    = $Message
    }
}
