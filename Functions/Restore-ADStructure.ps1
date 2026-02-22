function Restore-ADStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OrgNameInput,

        [Parameter(Mandatory=$false)]
        [switch]$DisableProtection
    )

    process {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
        } catch {
            Write-Error "Active Directory module not found. Please ensure RSAT is installed."
            return
        }

        # Determine protection status based on the -DisableProtection flag
        $ProtectionValue = -not $DisableProtection
        Write-Host "Protection from accidental deletion is set to: $ProtectionValue" -ForegroundColor ($(if($ProtectionValue){"Green"}else{"Yellow"}))

        # --- INTERNAL HELPER FUNCTION ---
        function New-OUHelper {
            param($Name, $Path, $IsProtected)
            $FullDN = "OU=$Name,$Path"

            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$FullDN'")) {
                Write-Host "Creating OU: $Name" -ForegroundColor Cyan
                New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $IsProtected
            } else {
                Write-Host "OU already exists: $Name" -ForegroundColor Yellow
            }
        }

        # --- INITIALIZATION ---
        $DomainDN = (Get-ADDomain).DistinguishedName
        $OrgName = "_" + $OrgNameInput.Trim().TrimStart('_').ToUpper()

        # --- 1. CREATE ROOT OU ---
        New-OUHelper -Name $OrgName -Path $DomainDN -IsProtected $ProtectionValue
        $RootPath = "OU=$OrgName,$DomainDN"

        # --- 2. CREATE TOP-LEVEL OUs ---
        $TopLevelOUs = @("_Admin", "_DisabledObjects", "_Quarantine", "Groups", "Servers", "Users", "Workstations")
        foreach ($OU in $TopLevelOUs) {
            New-OUHelper -Name $OU -Path $RootPath -IsProtected $ProtectionValue
        }

        # --- 3. CREATE ADMIN TIERS ---
        $AdminPath = "OU=_Admin,$RootPath"
        $Tiers = @("Tier 0", "Tier 1", "Tier 2")
        $SubTypes = @("Accounts", "Groups", "ServiceAccounts", "PAWs")

        foreach ($Tier in $Tiers) {
            New-OUHelper -Name $Tier -Path $AdminPath -IsProtected $ProtectionValue
            $CurrentTierPath = "OU=$Tier,$AdminPath"

            foreach ($Sub in $SubTypes) {
                $TierPrefix = $Tier.Replace("ier ", "")
                New-OUHelper -Name "$($TierPrefix)_$Sub" -Path $CurrentTierPath -IsProtected $ProtectionValue
            }
        }

        # --- 4. CREATE SECOND-LEVEL OUs ---
        $SubOUs = @(
            @{ Name = "Access"; Parent = "Groups" },
            @{ Name = "Distribution"; Parent = "Groups" },
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

        Write-Host "`nAD Structure for $OrgName created successfully!" -ForegroundColor Green
    }
}
