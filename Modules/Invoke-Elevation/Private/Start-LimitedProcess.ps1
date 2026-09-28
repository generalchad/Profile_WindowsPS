# =====================================================================
# Start-LimitedProcess.ps1 - launch a process with the current user's
#                            non-elevated (filtered) token
#
# WHY THIS EXISTS
#
# De-elevation used runas /trustlevel:0x20000, which builds the child from a
# SAFER restricted token: Administrators is present but "deny only". ShellExecute's
# runas verb has no unfiltered token to elevate from, so a Start-Process -Verb RunAs
# inside that child silently relaunches at the restricted level, with no UAC prompt.
# The whole runas -> elevate -> runas chain then collapses to unelevated processes.
#
# Instead, take a filtered token - the linked (TokenLinkedToken) half of the UAC
# split token, or the desktop shell's (explorer.exe) token - duplicate it as a
# primary token, and CreateProcessWithTokenW. That is a normal, non-elevated token:
# Test-Elevation is $false and the child can elevate again later. No password
# prompt, and unlike the SAFER token it keeps normal user semantics (profile,
# mapped-drive access, etc.).
#
# CreateProcessWithTokenW needs the handle to carry TOKEN_ASSIGN_PRIMARY,
# TOKEN_DUPLICATE, TOKEN_QUERY, TOKEN_ADJUST_DEFAULT and TOKEN_ADJUST_SESSIONID
# (the last two are undocumented). Neither source handle has them all, so
# DuplicateTokenEx always runs first.
#
# The interop is compiled lazily on first use, not at import: the module is
# autoloaded and most invocations never de-elevate.
# =====================================================================

$script:ProcessLauncherInterop = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace InvokeElevation.Native
{
    public static class ProcessLauncher
    {
        private const int TokenLinkedToken = 19;
        private const int PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        private const int TOKEN_ASSIGN_PRIMARY = 0x0001;
        private const int TOKEN_DUPLICATE = 0x0002;
        private const int TOKEN_QUERY = 0x0008;
        private const int TOKEN_ADJUST_DEFAULT = 0x0080;
        private const int TOKEN_ADJUST_SESSIONID = 0x0100;
        private const int TOKEN_RIGHTS = TOKEN_ASSIGN_PRIMARY | TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ADJUST_DEFAULT | TOKEN_ADJUST_SESSIONID;
        private const int SecurityImpersonation = 2;
        private const int TokenPrimary = 1;
        private const int LOGON_WITH_PROFILE = 0x00000001;
        private const int CREATE_NEW_CONSOLE = 0x00000010;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct STARTUPINFO
        {
            public int cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public int dwX;
            public int dwY;
            public int dwXSize;
            public int dwYSize;
            public int dwXCountChars;
            public int dwYCountChars;
            public int dwFillAttribute;
            public int dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TOKEN_LINKED_TOKEN
        {
            public IntPtr LinkedToken;
        }

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(IntPtr processHandle, int desiredAccess, out IntPtr tokenHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool GetTokenInformation(IntPtr tokenHandle, int tokenInformationClass, ref TOKEN_LINKED_TOKEN tokenInformation, int tokenInformationLength, out int returnLength);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool DuplicateTokenEx(IntPtr existingToken, int desiredAccess, IntPtr tokenAttributes, int impersonationLevel, int tokenType, out IntPtr newToken);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr GetShellWindow();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern int GetWindowThreadProcessId(IntPtr hWnd, out int processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(int desiredAccess, bool inheritHandle, int processId);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool CreateProcessWithTokenW(
            IntPtr hToken,
            int dwLogonFlags,
            string lpApplicationName,
            string lpCommandLine,
            int dwCreationFlags,
            IntPtr lpEnvironment,
            string lpCurrentDirectory,
            ref STARTUPINFO lpStartupInfo,
            out PROCESS_INFORMATION lpProcessInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hObject);

        // Returns the new process ID, or 0. A null error means no filtered token
        // could be obtained (no linked token and no desktop shell) and the caller
        // should fall back; a non-null error is a real failure and is thrown.
        public static int Start(string applicationName, string commandLine, string workingDirectory, out string error)
        {
            error = null;
            string lastError = null;

            IntPtr linked = GetLinkedToken();
            if (linked != IntPtr.Zero)
            {
                int linkedPid = TryCreate(linked, "linked token", applicationName, commandLine, workingDirectory, out lastError);
                CloseHandle(linked);
                if (linkedPid != 0) return linkedPid;
            }

            IntPtr shell = GetShellToken();
            if (shell != IntPtr.Zero)
            {
                int shellPid = TryCreate(shell, "shell token", applicationName, commandLine, workingDirectory, out lastError);
                CloseHandle(shell);
                if (shellPid != 0) return shellPid;
            }

            error = lastError;
            return 0;
        }

        private static int TryCreate(IntPtr token, string source, string applicationName, string commandLine, string workingDirectory, out string error)
        {
            STARTUPINFO startupInfo = new STARTUPINFO();
            startupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            PROCESS_INFORMATION processInfo = new PROCESS_INFORMATION();

            if (!CreateProcessWithTokenW(token, LOGON_WITH_PROFILE, applicationName, commandLine, CREATE_NEW_CONSOLE, IntPtr.Zero, workingDirectory, ref startupInfo, out processInfo))
            {
                error = source + " launch failed: " + new Win32Exception(Marshal.GetLastWin32Error()).Message;
                return 0;
            }

            CloseHandle(processInfo.hThread);
            CloseHandle(processInfo.hProcess);
            error = null;
            return processInfo.dwProcessId;
        }

        private static IntPtr GetLinkedToken()
        {
            IntPtr token = IntPtr.Zero;
            IntPtr linked = IntPtr.Zero;

            try
            {
                if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, out token)) return IntPtr.Zero;

                TOKEN_LINKED_TOKEN linkedInfo = new TOKEN_LINKED_TOKEN();
                int returnLength = 0;
                int linkedInfoSize = Marshal.SizeOf(typeof(TOKEN_LINKED_TOKEN));
                if (!GetTokenInformation(token, TokenLinkedToken, ref linkedInfo, linkedInfoSize, out returnLength)) return IntPtr.Zero;
                linked = linkedInfo.LinkedToken;

                IntPtr primary = IntPtr.Zero;
                if (!DuplicateTokenEx(linked, TOKEN_RIGHTS, IntPtr.Zero, SecurityImpersonation, TokenPrimary, out primary)) return IntPtr.Zero;
                return primary;
            }
            finally
            {
                if (linked != IntPtr.Zero) CloseHandle(linked);
                if (token != IntPtr.Zero) CloseHandle(token);
            }
        }

        private static IntPtr GetShellToken()
        {
            IntPtr shellWindow = GetShellWindow();
            if (shellWindow == IntPtr.Zero) return IntPtr.Zero;

            int shellProcessId;
            if (GetWindowThreadProcessId(shellWindow, out shellProcessId) == 0) return IntPtr.Zero;

            IntPtr shellProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, shellProcessId);
            if (shellProcess == IntPtr.Zero) return IntPtr.Zero;

            IntPtr token = IntPtr.Zero;
            try
            {
                if (!OpenProcessToken(shellProcess, TOKEN_DUPLICATE, out token)) return IntPtr.Zero;

                IntPtr primary = IntPtr.Zero;
                if (!DuplicateTokenEx(token, TOKEN_RIGHTS, IntPtr.Zero, SecurityImpersonation, TokenPrimary, out primary)) return IntPtr.Zero;
                return primary;
            }
            finally
            {
                if (token != IntPtr.Zero) CloseHandle(token);
                CloseHandle(shellProcess);
            }
        }
    }
}
'@

function Start-LimitedProcess {
    <#
    .SYNOPSIS
        Starts a process with the current user's non-elevated (filtered) token.

    .DESCRIPTION
        Runs the given command as a normal, non-elevated process, using either the
        linked (UAC-limited) token or the desktop shell's token. The new process
        reports unelevated but can still elevate via the runas verb, unlike the
        SAFER restricted token produced by runas /trustlevel.

        Returns the new process ID, or $null when no filtered token is available,
        in which case the caller should fall back to another mechanism.

    .PARAMETER FilePath
        Full path of the executable, or $null to resolve the first token of
        CommandLine through the usual search path.

    .PARAMETER CommandLine
        The complete command line, with any embedded quoting already applied.

    .PARAMETER WorkingDirectory
        Starting directory for the new process.

    .NOTES
        Private helper. Not exported. Requires an elevated session (the linked
        token only exists under a UAC split token). Throws Win32Exception on a
        native launch failure.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [string] $FilePath,

        [Parameter(Mandatory)]
        [string] $CommandLine,

        [string] $WorkingDirectory
    )

    if (-not ('InvokeElevation.Native.ProcessLauncher' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition $script:ProcessLauncherInterop
    }

    $nativeError = $null
    $newProcessId = [InvokeElevation.Native.ProcessLauncher]::Start(
        $FilePath,
        $CommandLine,
        $WorkingDirectory,
        [ref] $nativeError
    )

    if ($nativeError) {
        throw [System.ComponentModel.Win32Exception]::new($nativeError)
    }

    if ($newProcessId -eq 0) { return $null }

    return [int] $newProcessId
}
