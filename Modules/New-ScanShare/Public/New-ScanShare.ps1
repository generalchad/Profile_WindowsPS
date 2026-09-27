function New-ScanShare {
    <#
    .SYNOPSIS
        Sets up an SMB scan-to-folder destination on this PC for an MFP in one step.

    .DESCRIPTION
        Creates (or reuses) everything a copier needs to scan to this machine:

          1. A local account for the MFP to authenticate as (password never expires,
             cannot be changed by the account).
          2. The destination folder.
          3. NTFS Modify rights on the folder for that account.
          4. An SMB share granting the account Change access.
          5. The inbound "File and Printer Sharing (SMB-In)" firewall rules.

        Every step is idempotent - existing items are reused and only missing
        pieces are created - so it is safe to re-run to repair a half-working setup.
        Finally it runs Test-FileShare against the share so the result is verified,
        and prints the exact values to enter on the copier's address book.

    .PARAMETER Path
        Folder to receive scans. Created if missing. Defaults to C:\Scans.

    .PARAMETER ShareName
        SMB share name. Defaults to "Scans".

    .PARAMETER UserName
        Local account the MFP authenticates as. Defaults to "scanner".

    .PARAMETER Password
        Password for the account, as a SecureString. Prompted for when a new
        account is created and none is supplied. Ignored for an existing account
        unless -ResetPassword is given.

    .PARAMETER ResetPassword
        Set -Password on an account that already exists.

    .PARAMETER SkipFirewall
        Leave firewall rules untouched (e.g. when managed by Group Policy).

    .OUTPUTS
        PSCustomObject with the share UNC path, account, local path, per-step
        results and the Test-FileShare verification.

    .EXAMPLE
        New-ScanShare

        Creates C:\Scans shared as \\<PC>\Scans for local user "scanner",
        prompting for the password.

    .EXAMPLE
        New-ScanShare -Path D:\Scans\Xerox -ShareName XeroxScans -UserName xerox -WhatIf

        Shows every change that would be made without applying any of them.

    .NOTES
        Requires elevation. The account is local to this PC; on the copier use
        "<PC name>\<UserName>" (or just the user name on most models) as the login.
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

        [securestring]$Password,

        [switch]$ResetPassword,

        [switch]$SkipFirewall
    )

    $resolvedPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
    $root = [System.IO.Path]::GetPathRoot($resolvedPath)
    if ($resolvedPath -ne $root) {
        $Path = $resolvedPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    } else {
        $Path = $resolvedPath
    }

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
            $modify = [System.Security.AccessControl.FileSystemRights]::Modify
            $hasModify = $acl.Access | Where-Object {
                $_.IdentityReference.Value -in $account, $UserName -and
                $_.AccessControlType -eq 'Allow' -and
                ($_.FileSystemRights -band $modify) -eq $modify
            }
            if ($hasModify) {
                & $addStep 'NTFS' 'Exists' "$account has Modify"
            }
            elseif ($PSCmdlet.ShouldProcess($Path, "Grant Modify to $account")) {
                $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                    $account, $modify, 'ContainerInherit, ObjectInherit', 'None', 'Allow')
                $acl.AddAccessRule($rule)
                Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
                & $addStep 'NTFS' 'Created' "Modify granted to $account"
            }
            else { & $addStep 'NTFS' 'WhatIf' "would grant Modify to $account" }
        }
        else {
            $status = if ($dryRun) { 'WhatIf' } else { 'Skipped' }
            $detail = if ($dryRun) { "would grant Modify to $account" } else { "folder '$Path' missing" }
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
                    Where-Object { $_.AccountName -in $account, $UserName -and $_.AccessControlType -eq 'Allow' -and $_.AccessRight -in 'Change', 'Full' }
                if ($access) {
                    & $addStep 'Share' 'Exists' "\\$env:COMPUTERNAME\$ShareName"
                }
                elseif ($PSCmdlet.ShouldProcess($ShareName, "Grant Change to $account")) {
                    $null = Grant-SmbShareAccess -Name $ShareName -AccountName $account -AccessRight Change -Force -ErrorAction Stop
                    & $addStep 'Share' 'Updated' "Change granted to $account"
                }
                else { & $addStep 'Share' 'WhatIf' "would grant Change to $account" }
            }
        }
        elseif ($PSCmdlet.ShouldProcess("\\$env:COMPUTERNAME\$ShareName", 'Create SMB share')) {
            $null = New-SmbShare -Name $ShareName -Path $Path -ChangeAccess $account `
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
            # Matched by group resource id and port rather than display name, which is
            # localized. Public-profile rules are deliberately left alone: enabling
            # SMB on untrusted networks is not needed for a copier on the LAN.
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

            $rules = @($candidateRules | Where-Object {
                $smbRuleNames.Contains($_.Name) -and
                $_.Profile -notmatch 'Public|Any'
            })

            $disabled = @($rules | Where-Object Enabled -eq 'False')
            if ($rules.Count -eq 0) {
                if ($PSCmdlet.ShouldProcess('Inbound TCP 445', 'Create dedicated SMB scan firewall rule')) {
                    $null = New-NetFirewallRule -Name 'ScanShare-SMB-In' -DisplayName 'ScanShare SMB Inbound (TCP 445)' `
                        -Direction Inbound -Protocol TCP -LocalPort 445 -Profile Domain, Private -Action Allow `
                        -RemoteAddress LocalSubnet -ErrorAction Stop
                    & $addStep 'Firewall' 'Created' 'created dedicated SMB-In rule (TCP 445)'
                } else {
                    & $addStep 'Firewall' 'WhatIf' 'would create dedicated SMB-In rule (TCP 445)'
                }
            }
            elseif ($disabled.Count -eq 0) {
                & $addStep 'Firewall' 'Exists' 'SMB-In (TCP 445) enabled'
            }
            elseif ($PSCmdlet.ShouldProcess('File and Printer Sharing (SMB-In)', 'Enable firewall rule')) {
                $disabled | Enable-NetFirewallRule -ErrorAction Stop
                & $addStep 'Firewall' 'Updated' "enabled $($disabled.Count) SMB-In rule(s)"
            }
            else { & $addStep 'Firewall' 'WhatIf' "would enable $($disabled.Count) SMB-In rule(s)" }
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
    if (-not $dryRun -and (Get-Command Test-FileShare -ErrorAction SilentlyContinue)) {
        $verification = Test-FileShare -Hostname $env:COMPUTERNAME -PortList 445 -ForceSmb
        $status = if ($verification.Status -eq 'OPEN') { 'Passed' } else { 'Failed' }
        & $addStep 'Verify' $status "TCP 445 $($verification.Status) on $env:COMPUTERNAME"
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
