function Get-SmbFirewallPlan {
    <#
    .SYNOPSIS
        Evaluates SMB (TCP 445) inbound firewall rules and plans per-profile coverage.

    .DESCRIPTION
        Inspects firewall rule descriptors to determine whether Domain and Private
        network profiles are covered by active Allow rules on port 445. Identifies
        safe existing rules that can be enabled without exposing Public networks,
        and calculates any remaining profiles requiring dedicated rule creation or update.

    .PARAMETER Rules
        Array of firewall rule objects or descriptors. Each object should have Name,
        Profile, Enabled, Action, and optionally LocalPort.

    .PARAMETER TargetProfiles
        Profiles that must be covered. Defaults to Domain and Private.

    .PARAMETER DedicatedOnly
        Count only the dedicated ScanShare-SMB-In rule as coverage and never plan
        to enable another rule. Used when -RemoteAddress is given: the built-in
        rules carry their own scope (the Domain one allows Any address), so
        enabling or relying on them would silently ignore the requested range.
        Enabled non-dedicated rules that cover a target profile are returned in
        BypassingRules so the caller can warn that they widen the scope.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [object[]]$Rules = @(),

        [Parameter()]
        [string[]]$TargetProfiles = @('Domain', 'Private'),

        [Parameter()]
        [switch]$DedicatedOnly
    )

    $activeProfiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $rulesToEnable = [System.Collections.Generic.List[object]]::new()
    $bypassingRules = [System.Collections.Generic.List[object]]::new()

    $smbRules = @($Rules | Where-Object {
        $null -ne $_ -and
        ($_.Action -as [string]) -eq 'Allow' -and
        (-not $_.PSObject.Properties['LocalPort'] -or ($_.LocalPort -contains '445' -or $_.LocalPort -eq '445'))
    })

    # 1. Identify profiles already covered by active allow rules
    foreach ($r in $smbRules) {
        $isEnabled = ($r.Enabled -as [string]) -eq 'True' -or $r.Enabled -eq $true
        if ($isEnabled) {
            $profiles = ($r.Profile -as [string]) -split ',\s*'
            $coversTarget = $false
            foreach ($tp in $TargetProfiles) {
                if ($profiles -contains $tp -or $profiles -contains 'Any') {
                    $coversTarget = $true
                    if (-not $DedicatedOnly -or $r.Name -eq 'ScanShare-SMB-In') {
                        $null = $activeProfiles.Add($tp)
                    }
                }
            }
            if ($DedicatedOnly -and $coversTarget -and $r.Name -ne 'ScanShare-SMB-In') {
                $bypassingRules.Add($r)
            }
        }
    }

    # 2. Identify disabled rules that can safely be enabled without opening Public networks
    $uncovered = @($TargetProfiles | Where-Object { -not $activeProfiles.Contains($_) })
    foreach ($r in $smbRules) {
        if ($DedicatedOnly -or $r.Name -eq 'ScanShare-SMB-In') { continue }
        $isDisabled = ($r.Enabled -as [string]) -eq 'False' -or $r.Enabled -eq $false
        if ($isDisabled) {
            $profiles = ($r.Profile -as [string]) -split ',\s*'
            $hasPublic = $profiles -contains 'Public' -or $profiles -contains 'Any'
            if (-not $hasPublic) {
                $coversUncovered = $false
                foreach ($tp in $uncovered) {
                    if ($profiles -contains $tp) {
                        $coversUncovered = $true
                        $null = $activeProfiles.Add($tp)
                    }
                }
                if ($coversUncovered) {
                    $rulesToEnable.Add($r)
                }
            }
        }
    }

    # 3. Calculate profiles still missing after considering safe-to-enable rules
    $missingProfiles = @($TargetProfiles | Where-Object { -not $activeProfiles.Contains($_) })

    $dedicatedRule = $smbRules | Where-Object { $_.Name -eq 'ScanShare-SMB-In' } | Select-Object -First 1
    $dedicatedAction = 'None'
    $dedicatedProfiles = @()

    if ($missingProfiles.Count -gt 0) {
        if (-not $dedicatedRule) {
            $dedicatedAction = 'Create'
            $dedicatedProfiles = @($missingProfiles)
        }
        else {
            $existingProfiles = if ($dedicatedRule.Profile) {
                @(($dedicatedRule.Profile -as [string]) -split ',\s*')
            } else { @() }

            $combined = @(@($existingProfiles) + @($missingProfiles) | Select-Object -Unique)
            $needsProfileUpdate = @($missingProfiles | Where-Object { $existingProfiles -notcontains $_ }).Count -gt 0
            $isDedicatedDisabled = ($dedicatedRule.Enabled -as [string]) -eq 'False' -or $dedicatedRule.Enabled -eq $false

            if ($needsProfileUpdate) {
                $dedicatedAction = 'Update'
                $dedicatedProfiles = $combined
            }
            elseif ($isDedicatedDisabled) {
                $dedicatedAction = 'Enable'
                $dedicatedProfiles = @($existingProfiles)
            }
        }
    }

    $status = if ($dedicatedAction -eq 'Create') {
        'Create'
    }
    elseif ($rulesToEnable.Count -gt 0 -or $dedicatedAction -in 'Update', 'Enable') {
        'Update'
    }
    else {
        'Exists'
    }

    [pscustomobject]@{
        Status            = $status
        ActiveProfiles    = @($activeProfiles)
        RulesToEnable     = $rulesToEnable.ToArray()
        MissingProfiles   = $missingProfiles
        DedicatedAction   = $dedicatedAction
        DedicatedProfiles = $dedicatedProfiles
        DedicatedRule     = $dedicatedRule
        BypassingRules    = $bypassingRules.ToArray()
    }
}
