# =====================================================================
# LocalAccountRights.ps1 - LSA user-rights assignment for local accounts
#
# WHY THIS EXISTS
#
# The LocalAccounts module manages local users and groups but has no
# concept of user rights (privileges). Hardening the scan account - so a
# leaked password cannot be used for console, RDP, batch or service logon
# - means editing the local security policy's "Log on as ... denied"
# assignments, which is only reachable through the LSA APIs.
#
# secedit was rejected: importing a USER_RIGHTS template rewrites every
# right in the file and can clobber a concurrent GPO policy refresh.
# LsaAddAccountRights adds exactly the requested rights and nothing else.
#
# The P/Invoke layer is compiled as C# 5 so it also loads under Windows
# PowerShell 5.1, whose Add-Type uses the pre-Roslyn CodeDom compiler.
# =====================================================================

if (-not ('ScanShare.Native.LsaRights' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;

namespace ScanShare.Native
{
    public static class LsaRights
    {
        private const int POLICY_LOOKUP_NAMES = 0x00000800;
        private const int POLICY_CREATE_ACCOUNT = 0x00000010;
        private const int STATUS_SUCCESS = 0;
        private const int STATUS_OBJECT_NAME_NOT_FOUND = unchecked((int)0xC0000034);

        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_UNICODE_STRING
        {
            internal ushort Length;
            internal ushort MaximumLength;
            internal IntPtr Buffer;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_OBJECT_ATTRIBUTES
        {
            internal int Length;
            internal IntPtr RootDirectory;
            internal IntPtr ObjectName;
            internal int Attributes;
            internal IntPtr SecurityDescriptor;
            internal IntPtr SecurityQualityOfService;
        }

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern int LsaOpenPolicy(
            IntPtr SystemName,
            ref LSA_OBJECT_ATTRIBUTES ObjectAttributes,
            int DesiredAccess,
            out IntPtr PolicyHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern int LsaClose(IntPtr ObjectHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern int LsaAddAccountRights(
            IntPtr PolicyHandle,
            byte[] AccountSid,
            LSA_UNICODE_STRING[] UserRights,
            int CountOfRights);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern int LsaEnumerateAccountRights(
            IntPtr PolicyHandle,
            byte[] AccountSid,
            out IntPtr UserRights,
            out int CountOfRights);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern int LsaFreeMemory(IntPtr Buffer);

        [DllImport("advapi32.dll")]
        private static extern int LsaNtStatusToWinError(int Status);

        public static string[] EnumerateRights(string accountName)
        {
            if (accountName == null) throw new ArgumentNullException("accountName");

            byte[] sid = ToSidBytes(accountName);
            IntPtr policy = OpenPolicy();
            IntPtr rightsBuffer = IntPtr.Zero;
            int count = 0;

            try
            {
                int status = LsaEnumerateAccountRights(policy, sid, out rightsBuffer, out count);
                if (status == STATUS_OBJECT_NAME_NOT_FOUND) return new string[0];
                if (status != STATUS_SUCCESS) throw new Win32Exception(LsaNtStatusToWinError(status));

                List<string> rights = new List<string>(count);
                int stride = Marshal.SizeOf(typeof(LSA_UNICODE_STRING));
                for (int i = 0; i < count; i++)
                {
                    IntPtr item = (IntPtr)(rightsBuffer.ToInt64() + (i * stride));
                    LSA_UNICODE_STRING entry = (LSA_UNICODE_STRING)Marshal.PtrToStructure(item, typeof(LSA_UNICODE_STRING));
                    rights.Add(Marshal.PtrToStringUni(entry.Buffer, entry.Length / 2));
                }
                return rights.ToArray();
            }
            finally
            {
                if (rightsBuffer != IntPtr.Zero) LsaFreeMemory(rightsBuffer);
                if (policy != IntPtr.Zero) LsaClose(policy);
            }
        }

        public static void AddRights(string accountName, string[] rights)
        {
            if (accountName == null) throw new ArgumentNullException("accountName");
            if (rights == null || rights.Length == 0) return;

            byte[] sid = ToSidBytes(accountName);
            IntPtr policy = OpenPolicy();
            LSA_UNICODE_STRING[] nativeRights = new LSA_UNICODE_STRING[rights.Length];

            try
            {
                for (int i = 0; i < rights.Length; i++)
                {
                    nativeRights[i] = ToUnicodeString(rights[i]);
                }
                int status = LsaAddAccountRights(policy, sid, nativeRights, rights.Length);
                if (status != STATUS_SUCCESS) throw new Win32Exception(LsaNtStatusToWinError(status));
            }
            finally
            {
                for (int i = 0; i < nativeRights.Length; i++)
                {
                    if (nativeRights[i].Buffer != IntPtr.Zero) Marshal.FreeHGlobal(nativeRights[i].Buffer);
                }
                if (policy != IntPtr.Zero) LsaClose(policy);
            }
        }

        private static IntPtr OpenPolicy()
        {
            LSA_OBJECT_ATTRIBUTES attributes = new LSA_OBJECT_ATTRIBUTES();
            attributes.Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));

            IntPtr handle = IntPtr.Zero;
            int status = LsaOpenPolicy(IntPtr.Zero, ref attributes, POLICY_LOOKUP_NAMES | POLICY_CREATE_ACCOUNT, out handle);
            if (status != STATUS_SUCCESS) throw new Win32Exception(LsaNtStatusToWinError(status));
            return handle;
        }

        private static byte[] ToSidBytes(string accountName)
        {
            NTAccount account = new NTAccount(accountName);
            SecurityIdentifier sid = (SecurityIdentifier)account.Translate(typeof(SecurityIdentifier));
            byte[] bytes = new byte[sid.BinaryLength];
            sid.GetBinaryForm(bytes, 0);
            return bytes;
        }

        private static LSA_UNICODE_STRING ToUnicodeString(string value)
        {
            LSA_UNICODE_STRING result = new LSA_UNICODE_STRING();
            result.Buffer = Marshal.StringToHGlobalUni(value);
            result.Length = (ushort)(value.Length * 2);
            result.MaximumLength = (ushort)((value.Length + 1) * 2);
            return result;
        }
    }
}
'@
}

function Get-LocalAccountRight {
    <#
    .SYNOPSIS
        Lists the user rights (privileges) assigned to a local account.

    .DESCRIPTION
        Reads the local security policy through LsaEnumerateAccountRights. Returns
        an empty array when the account has no rights rather than an error.

    .PARAMETER AccountName
        Account identity, e.g. "PC\scanner".

    .OUTPUTS
        String[]. Well-known right names (e.g. SeDenyInteractiveLogonRight).

    .NOTES
        Private helper. Not exported. Requires an elevated session.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$AccountName
    )

    $rights = [ScanShare.Native.LsaRights]::EnumerateRights($AccountName)
    if ($null -eq $rights) { return @() }
    return @($rights)
}

function Add-LocalAccountRight {
    <#
    .SYNOPSIS
        Assigns one or more user rights to a local account.

    .DESCRIPTION
        Adds the rights through LsaAddAccountRights. The call is idempotent: rights
        already held are left unchanged. Only the requested rights are touched; no
        other policy assignment is read or rewritten.

    .PARAMETER AccountName
        Account identity, e.g. "PC\scanner".

    .PARAMETER Right
        One or more well-known right names (e.g. SeDenyServiceLogonRight).

    .NOTES
        Private helper. Not exported. Requires an elevated session and throws a
        Win32Exception when LSA refuses the assignment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AccountName,

        [Parameter(Mandatory)]
        [string[]]$Right
    )

    [ScanShare.Native.LsaRights]::AddRights($AccountName, $Right)
}
