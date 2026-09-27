function Get-NtfsLockdownPlan {
    <#
    .SYNOPSIS
        Decides which NTFS access-control entries must be removed and whether the
        scan account still needs Modify rights.

    .DESCRIPTION
        Inspects the folder's access-control entries and identifies inherited
        "broad" identities (Everyone, Authenticated Users, Users, Creator Owner,
        etc.) that grant access beyond the scan account. The caller uses the result
        to break inheritance, purge those entries, and grant the scan account
        Modify, leaving only SYSTEM, Administrators, and the scan account.

    .PARAMETER AceList
        Array of access-control entry descriptors. Each entry should expose
        IdentityReference.Value, AccessControlType, and FileSystemRights.

    .PARAMETER Account
        Full account identity (e.g. "PC\scanner").

    .PARAMETER UserName
        Bare account name (e.g. "scanner").

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [object[]]$AceList = @(),

        [Parameter()]
        [string]$Account,

        [Parameter()]
        [string]$UserName
    )

    $broadNames = @('Everyone', 'Authenticated Users', 'Users', 'Creator Owner', 'Interactive', 'Anonymous Logon', 'Guests')
    $modify = [System.Security.AccessControl.FileSystemRights]::Modify

    $broadAces = @($AceList | Where-Object {
        $identity = $_.IdentityReference.Value
        if ($identity -eq $Account -or $identity -eq $UserName) { return $false }
        $suffix = ($identity -split '\\')[-1].Trim()
        $broadNames -contains $suffix
    })

    $hasModify = [bool]($AceList | Where-Object {
        $_.IdentityReference.Value -in $Account, $UserName -and
        $_.AccessControlType -eq 'Allow' -and
        ($_.FileSystemRights -band $modify) -eq $modify
    })

    [pscustomobject]@{
        Status          = if ($broadAces.Count -eq 0 -and $hasModify) { 'Exists' } else { 'Update' }
        BroadIdentities = @($broadAces | ForEach-Object { $_.IdentityReference.Value })
        BroadAces       = $broadAces
        NeedsModify     = -not $hasModify
    }
}
