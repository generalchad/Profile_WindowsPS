function Get-ScanSharePlan {
    <#
    .SYNOPSIS
        Produces a read-only summary of what New-ScanShare intends to do.

    .DESCRIPTION
        Runs the same detections the main function performs (account, folder, NTFS,
        share, firewall, verification) without changing anything, and returns one
        description per step. The caller prints these before the confirmation
        prompts so a "Yes to All" is an informed decision.

    .PARAMETER Path
        Destination folder path.

    .PARAMETER Account
        Full account identity (e.g. "PC\scanner").

    .PARAMETER UserName
        Bare account name (e.g. "scanner").

    .PARAMETER ShareName
        SMB share name.

    .PARAMETER SkipFirewall
        Whether firewall rules are left untouched.

    .PARAMETER ResetPassword
        Whether -ResetPassword was requested.

    .PARAMETER HasPassword
        Whether a password is available for the credentialed access probe.

    .PARAMETER VerifyAvailable
        Whether Test-FileShare is available for the listener check.

    .NOTES
        Private helper. Not exported. Best-effort: callers should tolerate failures.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter()][string]$Path,
        [Parameter()][string]$Account,
        [Parameter()][string]$UserName,
        [Parameter()][string]$ShareName,
        [Parameter()][switch]$SkipFirewall,
        [Parameter()][switch]$ResetPassword,
        [Parameter()][bool]$HasPassword,
        [Parameter()][bool]$VerifyAvailable
    )

    $items = [System.Collections.Generic.List[object]]::new()

    # Account
    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if (-not $user) {
        $accountDesc = "Create local user $Account (password never expires)"
    }
    elseif ($ResetPassword) {
        $accountDesc = "Reset password for $Account"
    }
    elseif ($user.PasswordExpires) {
        $accountDesc = "Set $Account password to never expire"
    }
    elseif (-not $user.Enabled) {
        $accountDesc = "Enable $Account"
    }
    else {
        $accountDesc = "No change ($Account already exists)"
    }
    $items.Add([pscustomobject]@{ Step = 'Account'; Description = $accountDesc })

    # Folder
    $folderExists = [bool](Test-Path -LiteralPath $Path -PathType Container)
    if ($folderExists) {
        $items.Add([pscustomobject]@{ Step = 'Folder'; Description = "No change ($Path already exists)" })
    }
    else {
        $items.Add([pscustomobject]@{ Step = 'Folder'; Description = "Create $Path" })
    }

    # NTFS
    if ($folderExists) {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($acl) {
            $ntfsPlan = Get-NtfsLockdownPlan -AceList @($acl.Access) -Account $Account -UserName $UserName
            if ($ntfsPlan.Status -eq 'Exists') {
                $ntfsDesc = "No change ($Account already has Modify; folder locked down)"
            }
            else {
                $ntfsDesc = "Lock down permissions; grant Modify to $Account"
            }
        }
        else {
            $ntfsDesc = "Lock down permissions; grant Modify to $Account"
        }
    }
    else {
        $ntfsDesc = "Lock down permissions; grant Modify to $Account (after creating folder)"
    }
    $items.Add([pscustomobject]@{ Step = 'NTFS'; Description = $ntfsDesc })

    # Share
    $share = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
    if ($share) {
        if ($share.Path.TrimEnd('\') -ne $Path.TrimEnd('\')) {
            $shareDesc = "FAIL: '$ShareName' is already shared from '$($share.Path)'"
        }
        else {
            $access = Get-SmbShareAccess -Name $ShareName |
                Where-Object { $_.AccountName -eq 'Everyone' -and $_.AccessControlType -eq 'Allow' -and $_.AccessRight -in 'Change', 'Full' }
            if ($access) {
                $shareDesc = "No change ($ShareName exists; Everyone: Full Control)"
            }
            else {
                $shareDesc = "Grant Everyone: Full Control on \\$env:COMPUTERNAME\$ShareName"
            }
        }
    }
    else {
        $shareDesc = "Create \\$env:COMPUTERNAME\$ShareName (Everyone: Full Control)"
    }
    $items.Add([pscustomobject]@{ Step = 'Share'; Description = $shareDesc })

    # Firewall
    if ($SkipFirewall) {
        $items.Add([pscustomobject]@{ Step = 'Firewall'; Description = 'Skipped (-SkipFirewall)' })
    }
    else {
        $candidates = Get-SmbFirewallCandidates
        $fwPlan = Get-SmbFirewallPlan -Rules $candidates
        if ($fwPlan.Status -eq 'Exists') {
            $items.Add([pscustomobject]@{ Step = 'Firewall'; Description = 'No change (SMB-In already enabled)' })
        }
        else {
            $items.Add([pscustomobject]@{ Step = 'Firewall'; Description = 'Enable/create SMB firewall rule (TCP 445)' })
        }
    }

    # Verification (listener + access)
    if ($VerifyAvailable) {
        $items.Add([pscustomobject]@{ Step = 'Listener'; Description = 'Check SMB listener (TCP 445)' })
    }
    else {
        $items.Add([pscustomobject]@{ Step = 'Listener'; Description = 'Skipped (Test-FileShare not installed)' })
    }

    if ($HasPassword) {
        $items.Add([pscustomobject]@{ Step = 'Access'; Description = "Write/delete a test file as $Account" })
    }
    else {
        $items.Add([pscustomobject]@{ Step = 'Access'; Description = 'Skipped (no password available)' })
    }

    $items.ToArray()
}
