# =====================================================================
# New-ScanShare.Tests.ps1 - Functional & Unit Verification Suite
#
# Runs non-destructive unit and behavioral tests for New-ScanShare:
# manifest validation, parameter constraints, path normalization,
# -WhatIf dry run execution, and IP/firewall heuristics.
#
# Run:
#   pwsh -NoProfile -File .\Modules\New-ScanShare\Tests\New-ScanShare.Tests.ps1
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:Pass = 0
$script:Fail = 0

function Test-Case {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Body
    )

    try {
        $result = & $Body
        if ($result) {
            Write-Host "  [PASS] $Name" -ForegroundColor Green
            $script:Pass++
        }
        else {
            Write-Host "  [FAIL] $Name" -ForegroundColor Red
            $script:Fail++
        }
    }
    catch {
        Write-Host "  [FAIL] $Name : $($_.Exception.Message)" -ForegroundColor Red
        $script:Fail++
    }
}

$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path $moduleRoot 'New-ScanShare.psd1'

Write-Host "`n--- Testing New-ScanShare Module ---`n" -ForegroundColor Cyan

# 1. Manifest & Module Import
Test-Case 'Manifest parses without AST errors' {
    $t = $e = $null
    [System.Management.Automation.Language.Parser]::ParseFile($manifestPath, [ref]$t, [ref]$e)
    $null -eq $e -or $e.Count -eq 0
}

Test-Case 'Module imports cleanly and exports New-ScanShare and Show-ScanShare' {
    Import-Module $manifestPath -Force
    $names = @(Get-Command -Module New-ScanShare | ForEach-Object Name)
    $names.Count -eq 2 -and $names -contains 'New-ScanShare' -and $names -contains 'Show-ScanShare'
}

Test-Case 'Every module script parses without AST errors' {
    $bad = @()
    $scripts = Get-ChildItem -Path (Join-Path $moduleRoot 'Private'), (Join-Path $moduleRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue
    foreach ($file in $scripts) {
        $t = $e = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$t, [ref]$e) | Out-Null
        if ($e -and $e.Count -gt 0) { $bad += "$($file.Name): $($e[0].Message)" }
    }
    $bad.Count -eq 0
}

# 2. Parameter Validation & Constraints
Test-Case 'Validates valid ShareName and UserName parameters' {
    $cmd = Get-Command New-ScanShare
    $paramShare = $cmd.Parameters['ShareName']
    $paramUser = $cmd.Parameters['UserName']
    $paramRemote = $cmd.Parameters['RemoteAddress']
    $null -ne $paramShare -and $null -ne $paramUser -and $null -ne $paramRemote
}

Test-Case 'Rejects empty RemoteAddress' {
    try {
        New-ScanShare -RemoteAddress '' -WhatIf -ErrorAction Stop
        $false
    } catch [System.Management.Automation.ParameterBindingException] {
        $true
    } catch {
        $false
    }
}

Test-Case 'Rejects invalid characters in ShareName parameter metadata' {
    try {
        New-ScanShare -ShareName 'Invalid/Share' -WhatIf -ErrorAction Stop
        $false
    } catch [System.Management.Automation.ParameterBindingException] {
        $true
    } catch {
        $false
    }
}

Test-Case 'Rejects invalid characters in UserName parameter metadata' {
    try {
        New-ScanShare -UserName 'bad*user' -WhatIf -ErrorAction Stop
        $false
    } catch [System.Management.Automation.ParameterBindingException] {
        $true
    } catch {
        $false
    }
}

Test-Case 'Defines short parameter aliases' {
    $cmd = Get-Command New-ScanShare
    $cmd.Parameters['Path'].Aliases -contains 'p' -and
    $cmd.Parameters['ShareName'].Aliases -contains 'n' -and
    $cmd.Parameters['UserName'].Aliases -contains 'u' -and
    $cmd.Parameters['Password'].Aliases -contains 'w' -and
    $cmd.Parameters['ResetPassword'].Aliases -contains 'rp' -and
    $cmd.Parameters['RemoteAddress'].Aliases -contains 'ra' -and
    $cmd.Parameters['SkipFirewall'].Aliases -contains 'sf' -and
    $cmd.Parameters['SkipVerification'].Aliases -contains 'sv'
}

Test-Case 'Defines positional order for Path, ShareName, UserName, Password' {
    $cmd = Get-Command New-ScanShare
    $position = @{}
    foreach ($name in 'Path', 'ShareName', 'UserName', 'Password') {
        $attr = $cmd.Parameters[$name].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        $position[$name] = $attr.Position
    }
    $position['Path'] -eq 0 -and
    $position['ShareName'] -eq 1 -and
    $position['UserName'] -eq 2 -and
    $position['Password'] -eq 3
}

Test-Case 'Binds positionally: path share user password' {
    $res = New-ScanShare 'C:\Scans' 'XeroxScans' 'xerox' -WhatIf
    $res.UncPath -eq "\\$env:COMPUTERNAME\XeroxScans" -and
    $res.Account -eq "$env:COMPUTERNAME\xerox" -and
    $res.Path -eq 'C:\Scans'
}

Test-Case 'Binds via short aliases -p -n -u' {
    $res = New-ScanShare -p 'C:\Scans' -n 'XeroxScans' -u 'xerox' -WhatIf
    $res.UncPath -eq "\\$env:COMPUTERNAME\XeroxScans" -and
    $res.Account -eq "$env:COMPUTERNAME\xerox"
}

# 3. Path Normalization
Test-Case 'Path normalizes trailing slash in -WhatIf simulation' {
    $res = New-ScanShare -Path 'C:\Scans\' -ShareName 'Scans' -WhatIf
    $res.Path -eq 'C:\Scans'
}

Test-Case 'Rejects filesystem drive root with terminating error' {
    try {
        New-ScanShare -Path 'C:\' -ShareName 'Scans' -WhatIf -ErrorAction Stop
        $false
    }
    catch [System.ArgumentException] {
        $true
    }
    catch {
        $_.FullyQualifiedErrorId -like '*DriveRootNotAllowed*'
    }
}

Test-Case 'Relative path resolves against current PowerShell location' {
    Push-Location $env:TEMP
    try {
        $expected = Join-Path (Get-Location).Path 'ScansTest'
        $res = New-ScanShare -Path '.\ScansTest' -WhatIf
        $res.Path -eq $expected
    }
    finally {
        Pop-Location
    }
}

# 4. Dry Run & Output Schema
Test-Case '-WhatIf returns PSCustomObject with complete schema' {
    $res = New-ScanShare -ShareName 'TestShare' -UserName 'testscan' -WhatIf
    $null -ne $res -and
    $res.UncPath -eq "\\$env:COMPUTERNAME\TestShare" -and
    $res.Account -eq "$env:COMPUTERNAME\testscan" -and
    $res.Steps.Count -ge 4
}

Test-Case '-WhatIf does not mutate file system or share state' {
    $testFolder = Join-Path $env:TEMP "TestScanShare_$(Get-Random)"
    $null = New-ScanShare -Path $testFolder -ShareName "TempShare$(Get-Random)" -WhatIf
    -not (Test-Path -LiteralPath $testFolder)
}

Test-Case '-Password accepts a plain string' {
    $user = "scanpw$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $res = New-ScanShare -UserName $user -Password 'Morris123!' -WhatIf
    $accountStep = $res.Steps | Where-Object Step -eq 'Account'
    $res.Account -eq "$env:COMPUTERNAME\$user" -and
    $accountStep.Status -eq 'WhatIf'
}

Test-Case '-ResetPassword with -WhatIf does not prompt for input' {
    # Existing local user (e.g. Administrator or Guest) should report WhatIf without blocking on Read-Host
    $firstUser = Get-LocalUser | Select-Object -First 1
    $existingUser = if ($firstUser) { $firstUser.Name } else { 'Administrator' }
    $res = New-ScanShare -UserName $existingUser -ResetPassword -WhatIf
    $accountStep = $res.Steps | Where-Object Step -eq 'Account'
    $accountStep.Status -eq 'WhatIf'
}

Test-Case '-SkipFirewall records Skipped status in Steps' {
    $res = New-ScanShare -SkipFirewall -WhatIf
    $fwStep = $res.Steps | Where-Object Step -eq 'Firewall'
    $fwStep.Status -eq 'Skipped'
}

# 5. IP Address and Network Heuristics
Test-Case 'Primary LAN IP resolves to valid non-virtual address' {
    $mod = Get-Module New-ScanShare
    $ip = & $mod.NewBoundScriptBlock({ Get-PrimaryIPv4Address })

    $ip -and
    $ip -notmatch '^127\.' -and
    $ip -notmatch '^169\.254\.'
}

Test-Case 'Get-PrimaryIPv4Address returns non-APIPA address on last-resort fallback' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        function Get-NetRoute { @() }
        function Get-NetIPAddress {
            [pscustomobject]@{
                PrefixOrigin   = 'Dhcp'
                IPAddress      = '192.168.100.55'
                InterfaceAlias = 'vEthernet (Default Switch)'
            }
        }
        Get-PrimaryIPv4Address
    }
    $ip = & $mod.NewBoundScriptBlock($testBlock)
    $ip -eq '192.168.100.55'
}

Test-Case 'Get-PrimaryIPv4Address returns null when no matching IPv4 address exists' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        function Get-NetRoute { @() }
        function Get-NetIPAddress { @() }
        Get-PrimaryIPv4Address
    }
    $ip = & $mod.NewBoundScriptBlock($testBlock)
    $null -eq $ip
}

# 6. Firewall Heuristics and Planning
Test-Case 'Firewall plan: Stock Win11 enables Domain and creates dedicated Private rule' {
    $mod = Get-Module New-ScanShare
    $rules = @(
        [pscustomobject]@{ Name = 'FPS-SMB-In-TCP'; Profile = 'Private, Public'; Enabled = 'False'; Action = 'Allow'; LocalPort = '445' },
        [pscustomobject]@{ Name = 'FPS-SMB-In-TCP-NoScope'; Profile = 'Domain'; Enabled = 'False'; Action = 'Allow'; LocalPort = '445' }
    )
    $plan = & $mod.NewBoundScriptBlock({ param($r) Get-SmbFirewallPlan -Rules $r }) $rules

    $plan.RulesToEnable.Count -eq 1 -and
    $plan.RulesToEnable[0].Name -eq 'FPS-SMB-In-TCP-NoScope' -and
    $plan.DedicatedAction -eq 'Create' -and
    @($plan.DedicatedProfiles) -contains 'Private' -and
    @($plan.DedicatedProfiles) -notcontains 'Public'
}

Test-Case 'Firewall plan: Exists when Domain and Private rules are already active' {
    $mod = Get-Module New-ScanShare
    $rules = @(
        [pscustomobject]@{ Name = 'FPS-SMB-In-TCP-NoScope'; Profile = 'Domain'; Enabled = 'True'; Action = 'Allow'; LocalPort = '445' },
        [pscustomobject]@{ Name = 'ScanShare-SMB-In'; Profile = 'Private'; Enabled = 'True'; Action = 'Allow'; LocalPort = '445' }
    )
    $plan = & $mod.NewBoundScriptBlock({ param($r) Get-SmbFirewallPlan -Rules $r }) $rules

    $plan.Status -eq 'Exists' -and
    $plan.RulesToEnable.Count -eq 0 -and
    $plan.DedicatedAction -eq 'None'
}

Test-Case 'Firewall plan: Any profile active rule covers Domain and Private' {
    $mod = Get-Module New-ScanShare
    $rules = @(
        [pscustomobject]@{ Name = 'Custom-SMB-Any'; Profile = 'Any'; Enabled = 'True'; Action = 'Allow'; LocalPort = '445' }
    )
    $plan = & $mod.NewBoundScriptBlock({ param($r) Get-SmbFirewallPlan -Rules $r }) $rules

    $plan.Status -eq 'Exists' -and
    $plan.RulesToEnable.Count -eq 0 -and
    $plan.DedicatedAction -eq 'None'
}

Test-Case 'Firewall plan: Ignores Block rules and Public-only rules' {
    $mod = Get-Module New-ScanShare
    $rules = @(
        [pscustomobject]@{ Name = 'Block-SMB'; Profile = 'Domain, Private'; Enabled = 'True'; Action = 'Block'; LocalPort = '445' },
        [pscustomobject]@{ Name = 'FPS-SMB-In-TCP'; Profile = 'Public'; Enabled = 'True'; Action = 'Allow'; LocalPort = '445' }
    )
    $plan = & $mod.NewBoundScriptBlock({ param($r) Get-SmbFirewallPlan -Rules $r }) $rules

    $plan.DedicatedAction -eq 'Create' -and
    @($plan.DedicatedProfiles) -contains 'Domain' -and
    @($plan.DedicatedProfiles) -contains 'Private'
}

Test-Case 'Firewall plan: Updates existing dedicated rule when profile is missing' {
    $mod = Get-Module New-ScanShare
    $rules = @(
        [pscustomobject]@{ Name = 'ScanShare-SMB-In'; Profile = 'Domain'; Enabled = 'True'; Action = 'Allow'; LocalPort = '445' }
    )
    $plan = & $mod.NewBoundScriptBlock({ param($r) Get-SmbFirewallPlan -Rules $r }) $rules

    $plan.DedicatedAction -eq 'Update' -and
    @($plan.DedicatedProfiles) -contains 'Domain' -and
    @($plan.DedicatedProfiles) -contains 'Private'
}

Test-Case 'Firewall: -RemoteAddress change on existing dedicated rule plans an update' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        function Test-Elevation { $true }
        function Get-LocalUser { [pscustomobject]@{ Name = 'scanner'; Enabled = $true; PasswordExpires = $false } }
        function Get-SmbShare { $null }
        function Get-NetConnectionProfile { @() }
        function Get-NetFirewallRule {
            param([string]$Name, [string]$Direction, [string]$Group, [string]$DisplayGroup)
            if ($Name -eq 'ScanShare-SMB-In') {
                [pscustomobject]@{ Name = 'ScanShare-SMB-In'; InstanceID = 'ScanShare-SMB-In'; Profile = 'Domain, Private'; Enabled = 'True'; Action = 'Allow' }
            }
        }
        function Get-NetFirewallPortFilter {
            process { [pscustomobject]@{ InstanceID = $_.Name; LocalPort = '445' } }
        }
        function Get-NetFirewallAddressFilter {
            process { [pscustomobject]@{ RemoteAddress = 'LocalSubnet' } }
        }
        function Set-NetFirewallRule { throw 'Set-NetFirewallRule must not run under -WhatIf' }

        New-ScanShare -Path 'C:\ScansFwTest' -RemoteAddress '10.20.0.0/16' -WhatIf
    }
    $res = & $mod.NewBoundScriptBlock($testBlock)

    $fwStep = $res.Steps | Where-Object Step -eq 'Firewall'
    $fwStep.Status -eq 'WhatIf' -and
    $fwStep.Detail -like '*10.20.0.0/16*'
}

Test-Case 'Firewall candidates correlate by InstanceID when Name differs' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        function Get-NetFirewallRule {
            param($Name, $Direction, $Group, $DisplayGroup)
            if ($Name) {
                [pscustomobject]@{ Name = 'Friendly-Name'; InstanceID = 'GUID-123'; Profile = 'Private'; Enabled = 'True'; Action = 'Allow' }
            }
        }
        function Get-NetFirewallPortFilter {
            process { [pscustomobject]@{ InstanceID = 'GUID-123'; LocalPort = '445' } }
        }
        Get-SmbFirewallCandidates
    }
    $candidates = & $mod.NewBoundScriptBlock($testBlock)

    @($candidates).Count -eq 1 -and
    $candidates[0].InstanceID -eq 'GUID-123'
}

# 7. NTFS Lockdown Planning
Test-Case 'NTFS plan: detects inherited broad identities and needed Modify' {
    $mod = Get-Module New-ScanShare
    $aces = @(
        [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'NT AUTHORITY\Authenticated Users' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify },
        [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'BUILTIN\Users' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute },
        [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'CREATOR OWNER' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl }
    )
    $plan = & $mod.NewBoundScriptBlock({ param($a) Get-NtfsLockdownPlan -AceList $a -Account 'PC\scanner' -UserName 'scanner' }) $aces

    $plan.Status -eq 'Update' -and
    $plan.NeedsModify -eq $true -and
    @($plan.BroadIdentities).Count -eq 3 -and
    $plan.BroadIdentities -contains 'NT AUTHORITY\Authenticated Users' -and
    $plan.BroadIdentities -contains 'BUILTIN\Users' -and
    $plan.BroadIdentities -contains 'CREATOR OWNER'
}

Test-Case 'NTFS plan: reports Exists when already locked down' {
    $mod = Get-Module New-ScanShare
    $aces = @(
        [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'PC\scanner' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify },
        [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'NT AUTHORITY\SYSTEM' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl },
        [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'BUILTIN\Administrators' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl }
    )
    $plan = & $mod.NewBoundScriptBlock({ param($a) Get-NtfsLockdownPlan -AceList $a -Account 'PC\scanner' -UserName 'scanner' }) $aces

    $plan.Status -eq 'Exists' -and
    $plan.NeedsModify -eq $false -and
    @($plan.BroadIdentities).Count -eq 0
}

Test-Case 'NTFS plan: needs Modify when account is missing but folder is otherwise clean' {
    $mod = Get-Module New-ScanShare
    $aces = @(
        [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'NT AUTHORITY\SYSTEM' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl },
        [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'BUILTIN\Administrators' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl }
    )
    $plan = & $mod.NewBoundScriptBlock({ param($a) Get-NtfsLockdownPlan -AceList $a -Account 'PC\scanner' -UserName 'scanner' }) $aces

    $plan.Status -eq 'Update' -and
    $plan.NeedsModify -eq $true -and
    @($plan.BroadIdentities).Count -eq 0
}

Test-Case 'Share: grants Everyone Full Control on an existing share' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        function Test-Elevation { $true }
        function Get-LocalUser { [pscustomobject]@{ Name = 'scanner'; Enabled = $true; PasswordExpires = $false } }
        function Test-Path { $true }
        function Get-Acl {
            [pscustomobject]@{
                Access = @(
                    [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = "$env:COMPUTERNAME\scanner" }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify },
                    [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'NT AUTHORITY\SYSTEM' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl },
                    [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'BUILTIN\Administrators' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl }
                )
            }
        }
        function Get-SmbShare { [pscustomobject]@{ Name = 'Scans'; Path = 'C:\Scans' } }
        function Get-SmbShareAccess { [pscustomobject]@{ AccountName = 'CONTOSO\SomeGroup'; AccessControlType = 'Allow'; AccessRight = 'Change' } }
        function Grant-SmbShareAccess {
            param($Name, $AccountName, $AccessRight, $Force)
            if ($AccountName -ne 'Everyone' -or $AccessRight -ne 'Full') {
                throw "unexpected grant: $AccountName $AccessRight"
            }
            [pscustomobject]@{ }
        }
        function Get-NetFirewallRule { @() }
        function Get-SmbFirewallPlan { [pscustomobject]@{ Status = 'Exists'; RulesToEnable = @(); DedicatedAction = 'None' } }
        function Get-NetConnectionProfile { @() }

        New-ScanShare -Path 'C:\Scans' -SkipFirewall -Confirm:$false
    }
    $res = & $mod.NewBoundScriptBlock($testBlock)

    $shareStep = $res.Steps | Where-Object Step -eq 'Share'
    $shareStep.Status -eq 'Updated' -and
    $shareStep.Detail -eq 'Full Control granted to Everyone'
}

# 8. Pre-flight Summary
Test-Case 'Summary: reports create vs reuse intents per step' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        function Get-LocalUser { $null }
        function Test-Path { $false }
        function Get-SmbShare { $null }
        function Get-SmbFirewallCandidates { @() }
        function Get-SmbFirewallPlan { [pscustomobject]@{ Status = 'Exists' } }

        Get-ScanSharePlan -Path 'C:\Scans' -Account 'PC\scanner' -UserName 'scanner' -ShareName 'Scans' `
            -HasPassword $true -VerifyAvailable $true
    }
    $plan = & $mod.NewBoundScriptBlock($testBlock)

    $account = $plan | Where-Object Step -eq 'Account'
    $folder = $plan | Where-Object Step -eq 'Folder'
    $ntfs = $plan | Where-Object Step -eq 'NTFS'
    $share = $plan | Where-Object Step -eq 'Share'
    $firewall = $plan | Where-Object Step -eq 'Firewall'
    $listener = $plan | Where-Object Step -eq 'Listener'
    $access = $plan | Where-Object Step -eq 'Access'

    $account.Description -like '*Create local user PC\scanner*' -and
    $folder.Description -like '*Create C:\Scans*' -and
    $ntfs.Description -like '*Lock down*Modify*' -and
    $share.Description -like '*Create*Everyone: Full Control*' -and
    $firewall.Description -like '*No change*' -and
    $listener.Description -like '*Check SMB listener*' -and
    $access.Description -like '*Write/delete a test file*'
}

Test-Case 'Summary: reports no-change when folder and account already exist' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        function Get-LocalUser { [pscustomobject]@{ Name = 'scanner'; Enabled = $true; PasswordExpires = $false } }
        function Test-Path { $true }
        function Get-Acl {
            [pscustomobject]@{
                Access = @(
                    [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'PC\scanner' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify },
                    [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'NT AUTHORITY\SYSTEM' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl },
                    [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'BUILTIN\Administrators' }; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl }
                )
            }
        }
        function Get-SmbShare { [pscustomobject]@{ Name = 'Scans'; Path = 'C:\Scans' } }
        function Get-SmbShareAccess { [pscustomobject]@{ AccountName = 'Everyone'; AccessControlType = 'Allow'; AccessRight = 'Full' } }
        function Get-SmbFirewallCandidates { @() }
        function Get-SmbFirewallPlan { [pscustomobject]@{ Status = 'Exists' } }

        Get-ScanSharePlan -Path 'C:\Scans' -Account 'PC\scanner' -UserName 'scanner' -ShareName 'Scans' `
            -HasPassword $false -VerifyAvailable $true
    }
    $plan = & $mod.NewBoundScriptBlock($testBlock)

    $account = $plan | Where-Object Step -eq 'Account'
    $folder = $plan | Where-Object Step -eq 'Folder'
    $ntfs = $plan | Where-Object Step -eq 'NTFS'
    $share = $plan | Where-Object Step -eq 'Share'
    $access = $plan | Where-Object Step -eq 'Access'

    $account.Description -like '*No change*' -and
    $folder.Description -like '*No change*' -and
    $ntfs.Description -like '*No change*' -and
    $share.Description -like '*No change*' -and
    $access.Description -like '*Skipped*no password*'
}

Test-Case 'Summary: flags share path mismatch and skips firewall' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        function Get-LocalUser { $null }
        function Test-Path { $false }
        function Get-SmbShare { [pscustomobject]@{ Name = 'Scans'; Path = 'D:\Other' } }
        function Get-SmbFirewallCandidates { @() }
        function Get-SmbFirewallPlan { [pscustomobject]@{ Status = 'Exists' } }

        Get-ScanSharePlan -Path 'C:\Scans' -Account 'PC\scanner' -UserName 'scanner' -ShareName 'Scans' `
            -SkipFirewall -HasPassword $false -VerifyAvailable $false
    }
    $plan = & $mod.NewBoundScriptBlock($testBlock)

    $share = $plan | Where-Object Step -eq 'Share'
    $firewall = $plan | Where-Object Step -eq 'Firewall'
    $listener = $plan | Where-Object Step -eq 'Listener'

    $share.Description -like '*FAIL*' -and
    $firewall.Description -like '*Skipped*' -and
    $listener.Description -like '*Skipped*Test-FileShare*'
}

Test-Case 'Summary: reports Skipped verification when -SkipVerification' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        function Get-LocalUser { $null }
        function Test-Path { $false }
        function Get-SmbShare { $null }
        function Get-SmbFirewallCandidates { @() }
        function Get-SmbFirewallPlan { [pscustomobject]@{ Status = 'Exists' } }

        Get-ScanSharePlan -Path 'C:\Scans' -Account 'PC\scanner' -UserName 'scanner' -ShareName 'Scans' `
            -SkipVerification -HasPassword $true -VerifyAvailable $true
    }
    $plan = & $mod.NewBoundScriptBlock($testBlock)

    $listener = $plan | Where-Object Step -eq 'Listener'
    $access = $plan | Where-Object Step -eq 'Access'

    $listener.Description -like '*Skipped*SkipVerification*' -and
    $access.Description -like '*Skipped*SkipVerification*'
}

# 9. Verification Steps (Listener and Access)
Test-Case 'Verification: Listener checks local port and Access reports Skipped without password' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        function Test-Elevation { $true }
        function Get-LocalUser { [pscustomobject]@{ Name = 'scanner'; Enabled = $true; PasswordExpires = $false } }
        function Test-Path { $true }
        function Get-Acl {
            [pscustomobject]@{
                Access = @([pscustomobject]@{
                    IdentityReference = [pscustomobject]@{ Value = "$env:COMPUTERNAME\scanner" }
                    AccessControlType = 'Allow'
                    FileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify
                })
            }
        }
        function Get-SmbShare { [pscustomobject]@{ Name = 'Scans'; Path = 'C:\Scans' } }
        function Get-SmbShareAccess { [pscustomobject]@{ AccountName = 'Everyone'; AccessControlType = 'Allow'; AccessRight = 'Full' } }
        function Get-NetFirewallRule { @() }
        function Get-SmbFirewallPlan { [pscustomobject]@{ Status = 'Exists'; RulesToEnable = @(); DedicatedAction = 'None' } }
        function Get-NetConnectionProfile { @() }
        function Test-FileShare { [pscustomobject]@{ Status = 'OPEN'; Target = $env:COMPUTERNAME; Port = 445 } }

        New-ScanShare -Path 'C:\Scans' -SkipFirewall
    }
    $res = & $mod.NewBoundScriptBlock($testBlock)

    $listenerStep = $res.Steps | Where-Object Step -eq 'Listener'
    $accessStep = $res.Steps | Where-Object Step -eq 'Access'

    $listenerStep.Status -eq 'Passed' -and
    $accessStep.Status -eq 'Skipped' -and
    $accessStep.Detail -like '*password not available*'
}

Test-Case 'Verification: Access writes probe file when password supplied' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        $secPass = ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force
        function Test-Elevation { $true }
        function Get-LocalUser { [pscustomobject]@{ Name = 'scanner'; Enabled = $true; PasswordExpires = $false } }
        function Test-Path { $true }
        function Get-Acl {
            [pscustomobject]@{
                Access = @([pscustomobject]@{
                    IdentityReference = [pscustomobject]@{ Value = "$env:COMPUTERNAME\scanner" }
                    AccessControlType = 'Allow'
                    FileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify
                })
            }
        }
        function Get-SmbShare { [pscustomobject]@{ Name = 'Scans'; Path = 'C:\Scans' } }
        function Get-SmbShareAccess { [pscustomobject]@{ AccountName = 'Everyone'; AccessControlType = 'Allow'; AccessRight = 'Full' } }
        function Get-NetFirewallRule { @() }
        function Get-SmbFirewallPlan { [pscustomobject]@{ Status = 'Exists'; RulesToEnable = @(); DedicatedAction = 'None' } }
        function Get-NetConnectionProfile { @() }
        function Test-FileShare { [pscustomobject]@{ Status = 'OPEN'; Target = $env:COMPUTERNAME; Port = 445 } }
        function New-PSDrive { [pscustomobject]@{ Name = 'mockDrive' } }
        function New-Item { [pscustomobject]@{ Name = 'mockFile' } }
        function Remove-Item { $true }
        function Remove-PSDrive { $true }

        New-ScanShare -Path 'C:\Scans' -Password $secPass -SkipFirewall
    }
    $res = & $mod.NewBoundScriptBlock($testBlock)

    $accessStep = $res.Steps | Where-Object Step -eq 'Access'
    $accessStep.Status -eq 'Passed' -and
    $accessStep.Detail -like '*authenticated and wrote*'
}

Test-Case 'Verification: Access formats error 1219 gracefully' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        $secPass = ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force
        function Test-Elevation { $true }
        function Get-LocalUser { [pscustomobject]@{ Name = 'scanner'; Enabled = $true; PasswordExpires = $false } }
        function Test-Path { $true }
        function Get-Acl {
            [pscustomobject]@{
                Access = @([pscustomobject]@{
                    IdentityReference = [pscustomobject]@{ Value = "$env:COMPUTERNAME\scanner" }
                    AccessControlType = 'Allow'
                    FileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify
                })
            }
        }
        function Get-SmbShare { [pscustomobject]@{ Name = 'Scans'; Path = 'C:\Scans' } }
        function Get-SmbShareAccess { [pscustomobject]@{ AccountName = 'Everyone'; AccessControlType = 'Allow'; AccessRight = 'Full' } }
        function Get-NetFirewallRule { @() }
        function Get-SmbFirewallPlan { [pscustomobject]@{ Status = 'Exists'; RulesToEnable = @(); DedicatedAction = 'None' } }
        function Get-NetConnectionProfile { @() }
        function Test-FileShare { [pscustomobject]@{ Status = 'OPEN'; Target = $env:COMPUTERNAME; Port = 445 } }
        function New-PSDrive { throw 'System error 1219 has occurred.' }

        New-ScanShare -Path 'C:\Scans' -Password $secPass -SkipFirewall
    }
    $res = & $mod.NewBoundScriptBlock($testBlock)

    $accessStep = $res.Steps | Where-Object Step -eq 'Access'
    $accessStep.Status -eq 'Failed' -and
    $accessStep.Detail -like '*conflicting network credentials*'
}

Test-Case 'Verification: -SkipVerification records Skipped for Listener and Access' {
    $mod = Get-Module New-ScanShare
    $testBlock = {
        function Test-Elevation { $true }
        function Get-LocalUser { [pscustomobject]@{ Name = 'scanner'; Enabled = $true; PasswordExpires = $false } }
        function Test-Path { $true }
        function Get-Acl {
            [pscustomobject]@{
                Access = @([pscustomobject]@{
                    IdentityReference = [pscustomobject]@{ Value = "$env:COMPUTERNAME\scanner" }
                    AccessControlType = 'Allow'
                    FileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify
                })
            }
        }
        function Get-SmbShare { [pscustomobject]@{ Name = 'Scans'; Path = 'C:\Scans' } }
        function Get-SmbShareAccess { [pscustomobject]@{ AccountName = 'Everyone'; AccessControlType = 'Allow'; AccessRight = 'Full' } }
        function Get-NetFirewallRule { @() }
        function Get-SmbFirewallPlan { [pscustomobject]@{ Status = 'Exists'; RulesToEnable = @(); DedicatedAction = 'None' } }
        function Get-NetConnectionProfile { @() }
        function Test-FileShare { [pscustomobject]@{ Status = 'OPEN'; Target = $env:COMPUTERNAME; Port = 445 } }

        New-ScanShare -Path 'C:\Scans' -SkipFirewall -SkipVerification
    }
    $res = & $mod.NewBoundScriptBlock($testBlock)

    $listenerStep = $res.Steps | Where-Object Step -eq 'Listener'
    $accessStep = $res.Steps | Where-Object Step -eq 'Access'

    $listenerStep.Status -eq 'Skipped' -and
    $listenerStep.Detail -eq '-SkipVerification' -and
    $accessStep.Status -eq 'Skipped' -and
    $accessStep.Detail -eq '-SkipVerification'
}

# 10. GUI Helpers (Show-ScanShare)
Test-Case 'GUI splat: converts password, splits remote addresses, sets switches' {
    $mod = Get-Module New-ScanShare
    $splat = & $mod.NewBoundScriptBlock({
        Get-ScanShareGuiSplat -Path ' D:\Scans\Xerox ' -ShareName 'XeroxScans' -UserName 'xerox' `
            -Password 'Morris123!' -RemoteAddress '10.20.0.0/16, 10.21.0.0/16' -ResetPassword -SkipFirewall
    })
    $splat.Path -eq 'D:\Scans\Xerox' -and
    $splat.ShareName -eq 'XeroxScans' -and
    $splat.UserName -eq 'xerox' -and
    $splat.Password -is [System.Security.SecureString] -and
    @($splat.RemoteAddress).Count -eq 2 -and
    $splat.RemoteAddress -contains '10.21.0.0/16' -and
    $splat.ResetPassword -eq $true -and
    $splat.SkipFirewall -eq $true -and
    -not $splat.ContainsKey('SkipVerification')
}

Test-Case 'GUI splat: omits blank optional fields' {
    $mod = Get-Module New-ScanShare
    $splat = & $mod.NewBoundScriptBlock({ Get-ScanShareGuiSplat -Path 'C:\Scans' -ShareName 'Scans' -UserName 'scanner' })
    -not $splat.ContainsKey('Password') -and
    -not $splat.ContainsKey('RemoteAddress') -and
    -not $splat.ContainsKey('ResetPassword') -and
    $splat.Count -eq 3
}

Test-Case 'Result formatter: renders steps and copier summary on success' {
    $mod = Get-Module New-ScanShare
    $render = & $mod.NewBoundScriptBlock({
        $result = [pscustomobject]@{
            UncPath = "\\$env:COMPUTERNAME\Scans"
            Account = "$env:COMPUTERNAME\scanner"
            Path    = 'C:\Scans'
            Steps   = @(
                [pscustomobject]@{ Step = 'Account'; Status = 'Exists'; Detail = "$env:COMPUTERNAME\scanner" }
                [pscustomobject]@{ Step = 'Share'; Status = 'Created'; Detail = "\\$env:COMPUTERNAME\Scans" }
            )
        }
        Format-ScanShareResult -Result $result -ShareName 'Scans' -UserName 'scanner'
    })
    $render.Text -like '*Created*Share*' -and
    $render.Text -like '*Enter on the copier*' -and
    $render.Summary -like '*SMB, port 445*' -and
    $render.Summary -like '*\\*Scans*'
}

Test-Case 'Result formatter: reports failed steps without copier summary' {
    $mod = Get-Module New-ScanShare
    $render = & $mod.NewBoundScriptBlock({
        $result = [pscustomobject]@{
            UncPath = "\\$env:COMPUTERNAME\Scans"
            Account = "$env:COMPUTERNAME\scanner"
            Path    = 'C:\Scans'
            Steps   = @([pscustomobject]@{ Step = 'Share'; Status = 'Failed'; Detail = 'nope' })
        }
        Format-ScanShareResult -Result $result -ShareName 'Scans' -UserName 'scanner'
    })
    $render.Summary -eq '' -and $render.Text -like '*1 step(s) failed*'
}

Test-Case 'Result formatter: preview shows no copier summary' {
    $mod = Get-Module New-ScanShare
    $render = & $mod.NewBoundScriptBlock({
        $result = [pscustomobject]@{
            UncPath = "\\$env:COMPUTERNAME\Scans"
            Account = "$env:COMPUTERNAME\scanner"
            Path    = 'C:\Scans'
            Steps   = @([pscustomobject]@{ Step = 'Share'; Status = 'WhatIf'; Detail = 'would create' })
        }
        Format-ScanShareResult -Result $result -DryRun -ShareName 'Scans' -UserName 'scanner'
    })
    $render.Summary -eq '' -and $render.Text -like '*Preview only*'
}

Test-Case 'Result formatter: handles null result (unelevated early return)' {
    $mod = Get-Module New-ScanShare
    $render = & $mod.NewBoundScriptBlock({ Format-ScanShareResult -Result $null })
    $render.Summary -eq '' -and $render.Text -like '*No result*'
}

# 11. Summary
Write-Host "`nTest Results: $($script:Pass) Passed, $($script:Fail) Failed`n" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) {
    exit 1
}
