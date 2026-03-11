function Restore-ADStructure {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OrgNameInput,

        [Parameter(Mandatory=$false)]
        [switch]$DisableProtection
    )

    process {
        #region Prerequisites
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
        } catch {
            Write-Error "Active Directory module not found. Please ensure RSAT is installed."
            return
        }
        #endregion

        #region Initialization
        # Determine protection status based on the -DisableProtection flag
        $ProtectionValue = -not $DisableProtection
        Write-Verbose "Protection from accidental deletion is set to: $ProtectionValue"

        $DomainDN = (Get-ADDomain).DistinguishedName
        $OrgName = "_" + $OrgNameInput.Trim().TrimStart('_').ToUpper()
        #endregion

        #region Helper Functions
        function New-OUHelper {
            param(
                [string]$Name,
                [string]$Path,
                [bool]$IsProtected
            )
            $FullDN = "OU=$Name,$Path"

            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$FullDN'")) {
                # SupportsShouldProcess intercepts here for -WhatIf
                if ($PSCmdlet.ShouldProcess($FullDN, "Create Organizational Unit '$Name'")) {
                    Write-Verbose "Creating OU: $Name"
                    New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $IsProtected
                }
            } else {
                Write-Verbose "OU already exists: $Name (Skipping)"
            }
        }
        #endregion

        #region 1. Root OU
        New-OUHelper -Name $OrgName -Path $DomainDN -IsProtected $ProtectionValue
        $RootPath = "OU=$OrgName,$DomainDN"
        #endregion

        #region 2. Top-Level OUs
        # Added _Staging for new domain joins and _ServiceAccounts for general gMSAs
        $TopLevelOUs = @("_Admin", "_DisabledObjects", "_Quarantine", "_Staging", "_ServiceAccounts", "Groups", "Servers", "Users", "Workstations")
        foreach ($OU in $TopLevelOUs) {
            New-OUHelper -Name $OU -Path $RootPath -IsProtected $ProtectionValue
        }
        #endregion

        #region 3. Admin Tiers
        $AdminPath = "OU=_Admin,$RootPath"
        $Tiers = @("Tier 0", "Tier 1", "Tier 2")
        # Added gMSA to the administrative tiers
        $SubTypes = @("Accounts", "Groups", "ServiceAccounts", "gMSA", "PAWs")

        foreach ($Tier in $Tiers) {
            New-OUHelper -Name $Tier -Path $AdminPath -IsProtected $ProtectionValue
            $CurrentTierPath = "OU=$Tier,$AdminPath"

            foreach ($Sub in $SubTypes) {
                $TierPrefix = $Tier.Replace("ier ", "")
                New-OUHelper -Name "$($TierPrefix)_$Sub" -Path $CurrentTierPath -IsProtected $ProtectionValue
            }
        }
        #endregion

        #region 4. Second-Level OUs
        $SubOUs = @(
            @{ Name = "Access"; Parent = "Groups" },
            @{ Name = "Distribution"; Parent = "Groups" },
            @{ Name = "Security"; Parent = "Groups" },
            @{ Name = "Management"; Parent = "Groups" },
            @{ Name = "Applications"; Parent = "Servers" },
            @{ Name = "Database"; Parent = "Servers" },
            @{ Name = "Infrastructure"; Parent = "Servers" },
            @{ Name = "Contractors"; Parent = "Users" },
            @{ Name = "Employees"; Parent = "Users" },
            @{ Name = "Desktops"; Parent = "Workstations" },
            @{ Name = "Kiosks"; Parent = "Workstations" },
            @{ Name = "Laptops"; Parent = "Workstations" },
            @{ Name = "VDI"; Parent = "Workstations" }
        )

        foreach ($OU in $SubOUs) {
            New-OUHelper -Name $OU.Name -Path "OU=$($OU.Parent),$RootPath" -IsProtected $ProtectionValue
        }
        #endregion

        Write-Verbose "AD Structure for $OrgName script execution completed."
    }
}
