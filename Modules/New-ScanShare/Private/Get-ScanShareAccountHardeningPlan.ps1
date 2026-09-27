function Get-ScanShareAccountHardeningPlan {
    <#
    .SYNOPSIS
        Decides which logon-right restrictions the scan account is missing.

    .DESCRIPTION
        The scan account must authenticate only over SMB. It is therefore denied
        interactive, Remote Desktop, batch-job, and service logons, so a leaked
        password cannot be reused to sit at the console or to install persistence.
        Network logon is left untouched - it is the account's whole purpose.

        The result also flags membership in local groups that would give the
        credential more power than a scan account should ever have; the caller
        refuses to expose the share while such a membership remains.

        The read is best-effort: if the rights or group memberships cannot be read
        (for example in an unelevated preview) the account is treated as needing
        hardening instead of failing the plan.

    .PARAMETER Account
        Full account identity (e.g. "PC\scanner").

    .PARAMETER UserName
        Bare account name (e.g. "scanner"), matched against group members.

    .PARAMETER CurrentRights
        Overrides the live rights read. Primarily for testing.

    .PARAMETER AccountGroups
        Overrides the live group-membership read. Primarily for testing.

    .OUTPUTS
        PSCustomObject with RequiredRights, MissingRights, PrivilegedGroups,
        RightsKnown, and NeedsHardening.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][string]$Account,
        [Parameter()][string]$UserName,

        [Parameter()][AllowEmptyCollection()][string[]]$CurrentRights,
        [Parameter()][AllowEmptyCollection()][string[]]$AccountGroups
    )

    $requiredRights = @(
        'SeDenyInteractiveLogonRight'
        'SeDenyRemoteInteractiveLogonRight'
        'SeDenyBatchLogonRight'
        'SeDenyServiceLogonRight'
    )

    $privilegedGroups = @(
        'Administrators'
        'Backup Operators'
        'Power Users'
        'Remote Desktop Users'
        'Remote Management Users'
        'Hyper-V Administrators'
    )

    if ($PSBoundParameters.ContainsKey('CurrentRights')) {
        $rightsKnown = $true
    }
    else {
        try {
            $CurrentRights = @(Get-LocalAccountRight -AccountName $Account)
            $rightsKnown = $true
        }
        catch {
            $CurrentRights = @()
            $rightsKnown = $false
        }
    }

    if (-not $PSBoundParameters.ContainsKey('AccountGroups')) {
        $found = [System.Collections.Generic.List[string]]::new()
        foreach ($group in $privilegedGroups) {
            try {
                $members = @(Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue)
                $isMember = [bool]($members | Where-Object {
                    $_.Name -eq $Account -or (($_.Name -split '\\')[-1]) -eq $UserName
                })
                if ($isMember) { $found.Add($group) }
            }
            catch { }
        }
        $AccountGroups = $found.ToArray()
    }

    $missingRights = @($requiredRights | Where-Object { $CurrentRights -notcontains $_ })
    $privilegedFound = @($AccountGroups | Where-Object { $privilegedGroups -contains $_ })

    [pscustomobject]@{
        RequiredRights   = $requiredRights
        MissingRights    = $missingRights
        PrivilegedGroups = $privilegedFound
        RightsKnown      = $rightsKnown
        NeedsHardening   = $missingRights.Count -gt 0 -or $privilegedFound.Count -gt 0
    }
}
