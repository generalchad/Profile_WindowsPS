function Get-SmbFirewallCandidates {
    <#
    .SYNOPSIS
        Gathers the inbound SMB (TCP 445) firewall rules to evaluate.

    .DESCRIPTION
        Collects the dedicated ScanShare-SMB-In rule and the built-in File and
        Printer Sharing group, then keeps only the rules whose port filter allows
        TCP 445. Used by both the execution path and the pre-flight summary.

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $dedicated = Get-NetFirewallRule -Name 'ScanShare-SMB-In' -ErrorAction SilentlyContinue
    $groupRules = Get-NetFirewallRule -Direction Inbound -Group '@FirewallAPI.dll,-28502' -ErrorAction SilentlyContinue
    if (-not $groupRules) {
        $groupRules = Get-NetFirewallRule -Direction Inbound -DisplayGroup 'File and Printer Sharing*' -ErrorAction SilentlyContinue
    }

    $candidateRules = @($dedicated | Where-Object { $null -ne $_ }) + @($groupRules | Where-Object { $null -ne $_ })
    $portFilters = $candidateRules | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    # Port filters are keyed by InstanceID; correlate on it, not Name, because some
    # rules expose a GUID InstanceID whose Name is the friendly display name.
    $smbRuleIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($pf in $portFilters) {
        if ($pf.LocalPort -contains '445') {
            $null = $smbRuleIds.Add($pf.InstanceID)
        }
    }

    @($candidateRules | Where-Object { $smbRuleIds.Contains($_.InstanceID) })
}
