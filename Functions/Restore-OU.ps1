Import-Module ActiveDirectory

# --- CONFIGURATION ---
$OrgNameInput = "BROWNCOM"
$DomainDN = (Get-ADDomain).DistinguishedName

$OrgName = "_" + $OrgNameInput.Trim().TrimStart('_').ToUpper()

# --- HELPER FUNCTION ---
function New-OU {
    param($Name, $Path)
    $FullDN = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$FullDN'")) {
        Write-Host "Creating OU: $Name" -ForegroundColor Cyan
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $false
    } else {
        Write-Host "OU already exists: $Name" -ForegroundColor Yellow
    }
}

function Restore-OU {
    # --- 1. CREATE ROOT OU ---
    New-OU -Name $OrgName -Path $DomainDN
    $RootPath = "OU=$OrgName,$DomainDN"

    # --- 2. CREATE TOP-LEVEL OUs ---
    $TopLevelOUs = @("_Admin", "_DisabledObjects", "_Quarantine", "Groups", "Servers", "Users", "Workstations")
    foreach ($OU in $TopLevelOUs) {
        New-OU -Name $OU -Path $RootPath
    }

    # --- 3. CREATE ADMIN TIERS ---
    $AdminPath = "OU=_Admin,$RootPath"
    $Tiers = @("Tier 0", "Tier 1", "Tier 2")
    $SubTypes = @("Accounts", "Groups", "ServiceAccounts", "PAWs")

    foreach ($Tier in $Tiers) {
        New-OU -Name $Tier -Path $AdminPath
        $CurrentTierPath = "OU=$Tier,$AdminPath"

        foreach ($Sub in $SubTypes) {
            $TierPrefix = $Tier.Replace("ier ", "")
            New-OU -Name "$($TierPrefix)_$Sub" -Path $CurrentTierPath
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
        New-OU -Name $OU.Name -Path "OU=$($OU.Parent),$RootPath"
    }

    Write-Host "`nAD Structure for $OrgName created successfully!" -ForegroundColor Green
}
