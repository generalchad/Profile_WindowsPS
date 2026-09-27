function New-ScanShare {
    <#
    .SYNOPSIS
        Sets up an SMB scan-to-folder destination on this PC for an MFP in one step.

    .DESCRIPTION
        Creates (or reuses) everything a copier needs to scan to this machine:

          1. A local account for the MFP to authenticate as (password never expires,
             cannot be changed by the account).
          2. The destination folder.
          3. Locks the folder's NTFS permissions to SYSTEM, Administrators, and the
             scan account (Modify), removing inherited broad entries.
          4. An SMB share open to Everyone with Full Control (access is limited by
             the folder's NTFS permissions).
          5. The inbound "File and Printer Sharing (SMB-In)" firewall rules.
          6. Verification: checks local SMB listener and validates credentialed
             share access with a write/delete probe when password is available.

        Every step is idempotent - existing items are reused and only missing
        pieces are created - so it is safe to re-run to repair a half-working setup.
        Finally it prints the exact values to enter on the copier's address book.

    .PARAMETER Path
        Folder to receive scans. Created if missing. Defaults to C:\Scans.

    .PARAMETER ShareName
        SMB share name. Defaults to "Scans".

    .PARAMETER UserName
        Local account the MFP authenticates as. Defaults to "scanner".

    .PARAMETER Password
        Password for the account, as a SecureString or a plain string (converted
        internally). Prompted for when a new account is created and none is
        supplied. Ignored for an existing account unless -ResetPassword is given.
        A plain string is visible in the process list, so prefer a SecureString
        for anything sensitive.

    .PARAMETER ResetPassword
        Set -Password on an account that already exists.

    .PARAMETER RemoteAddress
        Remote IP address range(s) permitted for inbound SMB scans on the dedicated
        firewall rule. Defaults to 'LocalSubnet'. Specify a subnet (e.g. '10.20.0.0/16')
        or 'Any' if the MFP resides on a separate VLAN.

    .PARAMETER SkipFirewall
        Leave firewall rules untouched (e.g. when managed by Group Policy).

    .OUTPUTS
        PSCustomObject with the share UNC path, account, local path, per-step
        results (including Listener and Access checks) and the Test-FileShare verification.

    .EXAMPLE
        New-ScanShare

        Creates C:\Scans shared as \\<PC>\Scans for local user "scanner",
        prompting for the password.

    .EXAMPLE
        New-ScanShare -RemoteAddress '10.20.0.0/16'

        Creates the scan share and scopes the dedicated firewall rule to allow
        inbound copier scans from a separate printer VLAN (10.20.0.0/16).

    .EXAMPLE
        New-ScanShare -Path D:\Scans\Xerox -ShareName XeroxScans -UserName xerox -WhatIf

        Shows every change that would be made without applying any of them.

    .NOTES
        Requires elevation. The account is local to this PC; on the copier use
        "<PC name>\<UserName>" (or just the user name on most models) as the login.

        The scan folder's NTFS permissions are locked down to SYSTEM (Full control),
        Administrators (Full control), and the scan account (Modify). Inherited broad
        entries (Everyone, Authenticated Users, Users, Creator Owner) are removed.

        Supported platforms: Windows 10, Windows 11, and Windows Server 2016+
        (64-bit only). Older Windows (7/8/8.1, Server 2008 R2/2012/2012 R2) lack
        the LocalAccounts module this script depends on. Runs on PowerShell 7 and
        Windows PowerShell 5.1. Under 5.1 use a 64-bit console: LocalAccounts is
        not available in 32-bit (x86) hosts. Windows client editions default
        Windows PowerShell to the Restricted
        execution policy, so on a fresh PC relax it for the session only first:
            Set-ExecutionPolicy -Scope Process Bypass
        Files copied from a download or network share may also need Unblock-File.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$Path = 'C:\Scans',

        [ValidatePattern('^[^\\/:*?"<>|\[\];=+,]{1,80}$')]
        [string]$ShareName = 'Scans',

        [ValidatePattern('^[^\\/"\[\]:|<>+=;,?*@]{1,20}$')]
        [string]$UserName = 'scanner',

        [object]$Password,

        [switch]$ResetPassword,

        [ValidateNotNullOrEmpty()]
        [string[]]$RemoteAddress = @('LocalSubnet'),

        [switch]$SkipFirewall
    )

    if ($Password -is [string]) {
        $Password = ConvertTo-SecureString -String $Password -AsPlainText -Force
    }

    $resolvedPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
    $root = [System.IO.Path]::GetPathRoot($resolvedPath)
    if ($resolvedPath -eq $root) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.ArgumentException]::new("Path '$Path' is a filesystem root. New-ScanShare requires a dedicated subfolder (e.g. 'C:\Scans') to prevent exposing entire drives."),
            'DriveRootNotAllowed',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $Path
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $Path = $resolvedPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

    $dryRun = [bool]$WhatIfPreference

    if (-not (Test-Elevation) -and -not $dryRun) {
        Write-Warning 'New-ScanShare creates a local account, a share and firewall rules, which requires an elevated session.'
        Write-Host "  Relaunch with: $(Get-ElevationHint)" -ForegroundColor DarkGray
        Write-Host '  Preview without elevation: New-ScanShare -WhatIf' -ForegroundColor DarkGray
        return
    }

    $steps = [System.Collections.Generic.List[object]]::new()
    $addStep = {
        param([string]$Step, [string]$Status, [string]$Detail)
        $steps.Add([pscustomobject]@{ Step = $Step; Status = $Status; Detail = $Detail })
        $color = @{ Created = 'Green'; Updated = 'Green'; Passed = 'Green'; Exists = 'DarkGray'; Skipped = 'DarkGray'; WhatIf = 'Yellow'; Failed = 'Red' }[$Status]
        Write-Host ('  {0,-9} {1,-12} {2}' -f $Status, $Step, $Detail) -ForegroundColor $color
    }

    $promptPassword = {
        param([string]$PromptText)
        $pass = $Password
        while ($null -eq $pass -or $pass.Length -eq 0) {
            $pass = Read-Host $PromptText -AsSecureString
            if ($null -eq $pass -or $pass.Length -eq 0) {
                Write-Warning 'Password cannot be blank. Windows security policy blocks network authentications for accounts with empty passwords.'
            }
        }
        return $pass
    }

    $account = "$env:COMPUTERNAME\$UserName"
    Write-Host ''
    Write-Host "Scan-to-folder setup: \\$env:COMPUTERNAME\$ShareName -> $Path" -ForegroundColor Cyan

    # ---- 1. Local account ---------------------------------------------------
    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    try {
        if (-not $user) {
            if ($PSCmdlet.ShouldProcess($account, 'Create local user')) {
                # Windows LSA blocks network/SMB logins for accounts with empty passwords by default (LimitBlankPasswordUse).
                $Password = & $promptPassword "Password for new local user '$UserName' (blank passwords cannot be used over SMB)"
                $user = New-LocalUser -Name $UserName -Password $Password -PasswordNeverExpires `
                    -UserMayNotChangePassword -AccountNeverExpires `
                    -Description 'MFP scan-to-folder account (New-ScanShare)' -ErrorAction Stop
                & $addStep 'Account' 'Created' $account
            }
            else { & $addStep 'Account' 'WhatIf' "would create $account" }
        }
        else {
            if ($ResetPassword) {
                if ($PSCmdlet.ShouldProcess($account, 'Reset password')) {
                    $Password = & $promptPassword "New password for '$UserName' (blank passwords cannot be used over SMB)"
                    $user | Set-LocalUser -Password $Password -ErrorAction Stop
                    & $addStep 'Account' 'Updated' "$account (password reset)"
                }
                else { & $addStep 'Account' 'WhatIf' "would reset password for $account" }
            }
            else { & $addStep 'Account' 'Exists' $account }

            # Copiers keep sending the old password after it expires; scans then fail
            # with a generic "login error" that is hard to trace back to this.
            if ($user.PasswordExpires -and $PSCmdlet.ShouldProcess($account, 'Set password to never expire')) {
                $user | Set-LocalUser -PasswordNeverExpires $true -ErrorAction Stop
                & $addStep 'Account' 'Updated' 'password set to never expire'
            }
            if (-not $user.Enabled -and $PSCmdlet.ShouldProcess($account, 'Enable account')) {
                $user | Enable-LocalUser -ErrorAction Stop
                & $addStep 'Account' 'Updated' 'account enabled'
            }
        }
    }
    catch {
        & $addStep 'Account' 'Failed' $_.Exception.Message
        return [pscustomobject]@{ UncPath = $null; Account = $account; Path = $Path; Steps = $steps.ToArray(); Verification = $null }
    }

    # ---- 2. Folder ----------------------------------------------------------
    try {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            & $addStep 'Folder' 'Exists' $Path
        }
        elseif ($PSCmdlet.ShouldProcess($Path, 'Create folder')) {
            $null = New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
            & $addStep 'Folder' 'Created' $Path
        }
        else { & $addStep 'Folder' 'WhatIf' "would create $Path" }
    }
    catch {
        & $addStep 'Folder' 'Failed' $_.Exception.Message
    }

    # ---- 3. NTFS permissions ------------------------------------------------
    try {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            $acl = Get-Acl -LiteralPath $Path
            $plan = Get-NtfsLockdownPlan -AceList @($acl.Access) -Account $account -UserName $UserName
            $modify = [System.Security.AccessControl.FileSystemRights]::Modify

            if ($plan.Status -eq 'Exists') {
                & $addStep 'NTFS' 'Exists' "$account has Modify (folder locked down)"
            }
            elseif ($PSCmdlet.ShouldProcess($Path, "Lock down NTFS and grant Modify to $account")) {
                # Break inheritance but keep the inherited entries as explicit copies so
                # SYSTEM/Administrators survive; the broad identities are purged below.
                if ($acl.PSObject.Properties['AreAccessRulesProtected'] -and -not $acl.AreAccessRulesProtected) {
                    $acl.SetAccessRuleProtection($true, $true)
                }
                foreach ($ace in $plan.BroadAces) {
                    $null = $acl.PurgeAccessRules($ace.IdentityReference)
                }
                if ($plan.NeedsModify) {
                    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                        $account, $modify, 'ContainerInherit, ObjectInherit', 'None', 'Allow')
                    $acl.AddAccessRule($rule)
                }
                Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
                & $addStep 'NTFS' 'Updated' "locked down; Modify granted to $account"
            }
            else { & $addStep 'NTFS' 'WhatIf' "would lock down NTFS and grant Modify to $account" }
        }
        else {
            $status = if ($dryRun) { 'WhatIf' } else { 'Skipped' }
            $detail = if ($dryRun) { "would lock down NTFS and grant Modify to $account" } else { "folder '$Path' missing" }
            & $addStep 'NTFS' $status $detail
        }
    }
    catch {
        & $addStep 'NTFS' 'Failed' $_.Exception.Message
    }

    # ---- 4. SMB share -------------------------------------------------------
    try {
        $share = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
        if ($share) {
            if ($share.Path.TrimEnd('\') -ne $Path.TrimEnd('\')) {
                # Never repoint an existing share: something else may depend on it.
                & $addStep 'Share' 'Failed' "'$ShareName' already exists for '$($share.Path)'. Use -ShareName to pick another name."
            }
            else {
                $access = Get-SmbShareAccess -Name $ShareName |
                    Where-Object { $_.AccountName -eq 'Everyone' -and $_.AccessControlType -eq 'Allow' -and $_.AccessRight -in 'Change', 'Full' }
                if ($access) {
                    & $addStep 'Share' 'Exists' "\\$env:COMPUTERNAME\$ShareName (Everyone: Full Control)"
                }
                elseif ($PSCmdlet.ShouldProcess($ShareName, 'Grant Full Control to Everyone')) {
                    $null = Grant-SmbShareAccess -Name $ShareName -AccountName 'Everyone' -AccessRight Full -Force -ErrorAction Stop
                    & $addStep 'Share' 'Updated' 'Full Control granted to Everyone'
                }
                else { & $addStep 'Share' 'WhatIf' 'would grant Full Control to Everyone' }
            }
        }
        elseif ($PSCmdlet.ShouldProcess("\\$env:COMPUTERNAME\$ShareName", 'Create SMB share')) {
            $null = New-SmbShare -Name $ShareName -Path $Path -FullAccess Everyone `
                -Description 'MFP scan-to-folder destination (New-ScanShare)' -ErrorAction Stop
            & $addStep 'Share' 'Created' "\\$env:COMPUTERNAME\$ShareName"
        }
        else { & $addStep 'Share' 'WhatIf' "would create \\$env:COMPUTERNAME\$ShareName" }
    }
    catch {
        & $addStep 'Share' 'Failed' $_.Exception.Message
    }

    # ---- 5. Firewall --------------------------------------------------------
    if ($SkipFirewall) {
        & $addStep 'Firewall' 'Skipped' '-SkipFirewall'
    }
    else {
        try {
            $dedicated = Get-NetFirewallRule -Name 'ScanShare-SMB-In' -ErrorAction SilentlyContinue
            $groupRules = Get-NetFirewallRule -Direction Inbound -Group '@FirewallAPI.dll,-28502' -ErrorAction SilentlyContinue
            if (-not $groupRules) {
                $groupRules = Get-NetFirewallRule -Direction Inbound -DisplayGroup 'File and Printer Sharing*' -ErrorAction SilentlyContinue
            }

            $candidateRules = @($dedicated | Where-Object { $null -ne $_ }) + @($groupRules | Where-Object { $null -ne $_ })
            $portFilters = $candidateRules | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            $smbRuleNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($pf in $portFilters) {
                if ($pf.LocalPort -contains '445') {
                    $null = $smbRuleNames.Add($pf.InstanceID)
                }
            }

            $smbCandidateRules = @($candidateRules | Where-Object { $smbRuleNames.Contains($_.Name) })
            $plan = Get-SmbFirewallPlan -Rules $smbCandidateRules

            $needsAddressUpdate = $false
            if ($plan.DedicatedRule -and $PSBoundParameters.ContainsKey('RemoteAddress')) {
                $currentAddressFilter = $plan.DedicatedRule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
                $currentAddresses = @(if ($currentAddressFilter) { $currentAddressFilter.RemoteAddress })
                $needsAddressUpdate = $currentAddresses.Count -eq 0 -or
                    [bool](Compare-Object -ReferenceObject $currentAddresses -DifferenceObject $RemoteAddress)
            }

            if ($plan.Status -eq 'Exists' -and -not $needsAddressUpdate) {
                & $addStep 'Firewall' 'Exists' 'SMB-In (TCP 445) enabled'
            }
            else {
                $didWork = $false
                $actions = [System.Collections.Generic.List[string]]::new()
                $whatIfs = [System.Collections.Generic.List[string]]::new()

                if ($plan.RulesToEnable.Count -gt 0) {
                    $targetDesc = 'File and Printer Sharing (SMB-In)'
                    if ($PSCmdlet.ShouldProcess($targetDesc, 'Enable firewall rule')) {
                        $plan.RulesToEnable | Enable-NetFirewallRule -ErrorAction Stop
                        $actions.Add("enabled $($plan.RulesToEnable.Count) SMB-In rule(s)")
                        $didWork = $true
                    }
                    else {
                        $whatIfs.Add("would enable $($plan.RulesToEnable.Count) SMB-In rule(s)")
                    }
                }

                if ($plan.DedicatedAction -eq 'Create') {
                    $profDesc = $plan.DedicatedProfiles -join ', '
                    if ($PSCmdlet.ShouldProcess("Inbound TCP 445 ($profDesc)", 'Create dedicated SMB scan firewall rule')) {
                        $null = New-NetFirewallRule -Name 'ScanShare-SMB-In' -DisplayName 'ScanShare SMB Inbound (TCP 445)' `
                            -Direction Inbound -Protocol TCP -LocalPort 445 -Profile $plan.DedicatedProfiles -Action Allow `
                            -RemoteAddress $RemoteAddress -ErrorAction Stop
                        $actions.Add('created dedicated SMB-In rule (TCP 445)')
                        $didWork = $true
                    }
                    else {
                        $whatIfs.Add('would create dedicated SMB-In rule (TCP 445)')
                    }
                }
                elseif ($plan.DedicatedAction -eq 'Update' -or ($plan.DedicatedRule -and $needsAddressUpdate)) {
                    $profDesc = if ($plan.DedicatedProfiles.Count -gt 0) { $plan.DedicatedProfiles } else { $plan.DedicatedRule.Profile }
                    $profDescStr = ($profDesc -split ',\s*' | Select-Object -Unique) -join ', '
                    if ($PSCmdlet.ShouldProcess("ScanShare-SMB-In ($profDescStr)", 'Update dedicated firewall rule')) {
                        $params = @{
                            Name    = 'ScanShare-SMB-In'
                            Enabled = 'True'
                        }
                        if ($plan.DedicatedProfiles.Count -gt 0) {
                            $params['Profile'] = $plan.DedicatedProfiles
                        }
                        if ($needsAddressUpdate) {
                            $params['RemoteAddress'] = $RemoteAddress
                        }
                        Set-NetFirewallRule @params -ErrorAction Stop
                        $actions.Add('updated dedicated SMB-In rule')
                        $didWork = $true
                    }
                    else {
                        $updateDetail = if ($needsAddressUpdate) {
                            "would update dedicated SMB-In rule (remote address: $($RemoteAddress -join ', '))"
                        } else {
                            "would update dedicated SMB-In rule profiles to $profDescStr"
                        }
                        $whatIfs.Add($updateDetail)
                    }
                }
                elseif ($plan.DedicatedAction -eq 'Enable') {
                    if ($PSCmdlet.ShouldProcess('ScanShare-SMB-In', 'Enable dedicated firewall rule')) {
                        Enable-NetFirewallRule -Name 'ScanShare-SMB-In' -ErrorAction Stop
                        $actions.Add('enabled dedicated SMB-In rule')
                        $didWork = $true
                    }
                    else {
                        $whatIfs.Add('would enable dedicated SMB-In rule')
                    }
                }

                if ($dryRun) {
                    & $addStep 'Firewall' 'WhatIf' ($whatIfs -join '; ')
                }
                elseif ($didWork) {
                    $status = if ($plan.DedicatedAction -eq 'Create') { 'Created' } else { 'Updated' }
                    & $addStep 'Firewall' $status ($actions -join '; ')
                }
            }
        }
        catch {
            & $addStep 'Firewall' 'Failed' $_.Exception.Message
        }
    }

    $activeProfiles = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object IPv4Connectivity -ne 'NoTraffic')
    $publicProfiles = @($activeProfiles | Where-Object NetworkCategory -eq 'Public')
    if ($publicProfiles.Count -gt 0) {
        $pubNames = ($publicProfiles | ForEach-Object { "'$($_.Name)'" }) -join ', '
        Write-Warning "Active network profile ($pubNames) is set to 'Public'. Windows Firewall blocks incoming SMB scans on Public networks."
        Write-Host "  To allow copier scans, change to Private in PowerShell (Admin):" -ForegroundColor Yellow
        foreach ($p in $publicProfiles) {
            Write-Host "    Set-NetConnectionProfile -Name '$($p.Name)' -NetworkCategory Private" -ForegroundColor Yellow
        }
    }

    # ---- 6. Verify ----------------------------------------------------------
    $verification = $null
    if (-not $dryRun) {
        if (Get-Command Test-FileShare -ErrorAction SilentlyContinue) {
            $verification = Test-FileShare -Hostname $env:COMPUTERNAME -PortList 445 -ForceSmb
            $vStatus = if ($verification) { @($verification.Status)[0] } else { $null }
            $status = if ($vStatus -eq 'OPEN') { 'Passed' } else { 'Failed' }
            & $addStep 'Listener' $status "TCP 445 $vStatus on $env:COMPUTERNAME"
        }

        $shareFailed = @($steps | Where-Object { $_.Step -eq 'Share' -and $_.Status -eq 'Failed' }).Count -gt 0
        if ($shareFailed) {
            & $addStep 'Access' 'Skipped' 'share creation failed'
        }
        elseif ($null -ne $Password -and $Password.Length -gt 0) {
            $driveName = "ScanVerify_$([System.IO.Path]::GetRandomFileName() -replace '[^a-zA-Z0-9]','')"
            $drive = $null
            try {
                $cred = [System.Management.Automation.PSCredential]::new($account, $Password)
                $drive = New-PSDrive -Name $driveName -PSProvider FileSystem -Root "\\127.0.0.1\$ShareName" `
                    -Credential $cred -Scope Local -ErrorAction Stop

                $testFileName = ".scantest_$([System.IO.Path]::GetRandomFileName())"
                $testPath = "${driveName}:\${testFileName}"
                $null = New-Item -Path $testPath -ItemType File -Value 'ScanShare write test' -Force -ErrorAction Stop
                if (Test-Path -LiteralPath $testPath) {
                    Remove-Item -LiteralPath $testPath -Force -ErrorAction SilentlyContinue
                    & $addStep 'Access' 'Passed' "authenticated and wrote test file via \\127.0.0.1\$ShareName"
                }
                else {
                    & $addStep 'Access' 'Failed' 'could not verify test file creation'
                }
            }
            catch {
                $msg = $_.Exception.Message
                if ($msg -match '1219') {
                    $msg = 'conflicting network credentials cached by Windows (error 1219)'
                }
                elseif ($msg -match '1326') {
                    $msg = 'logon failure: unknown user name or bad password'
                }
                & $addStep 'Access' 'Failed' $msg
            }
            finally {
                if ($drive) {
                    $null = Remove-PSDrive -Name $driveName -Force -ErrorAction SilentlyContinue
                }
            }
        }
        else {
            & $addStep 'Access' 'Skipped' 'password not available in this session'
        }
    }

    $failed = @($steps | Where-Object Status -eq 'Failed').Count
    Write-Host ''
    if (-not $dryRun -and $failed -eq 0) {
        $ip = Get-PrimaryIPv4Address

        Write-Host 'Enter on the copier:' -ForegroundColor Cyan
        Write-Host "  Host / server : $env:COMPUTERNAME$(if ($ip) { "  (or $ip)" })"
        Write-Host "  Share / path  : $ShareName"
        Write-Host "  Full path     : \\$env:COMPUTERNAME\$ShareName"
        Write-Host "  User name     : $UserName   (some models need $account)"
        Write-Host '  Protocol      : SMB, port 445'
        Write-Host ''
    }
    elseif ($failed) {
        Write-Warning "$failed step(s) failed - see above."
    }

    [pscustomobject]@{
        UncPath      = "\\$env:COMPUTERNAME\$ShareName"
        Account      = $account
        Path         = $Path
        Steps        = $steps.ToArray()
        Verification = $verification
    }
}
