@{
    RootModule           = 'Invoke-Elevation.psm1'
    ModuleVersion        = '1.1.0'
    GUID                 = '3f2a9c1e-7d54-4a2b-9e0f-6c8b1d4a7e21'
    Author               = 'Timothy W. Brown'
    CompanyName          = 'Timothy W. Brown'
    Copyright            = '(c) Timothy W. Brown. Authored with LLM assistance (Anthropic Claude, Google Gemini, DeepSeek). All rights reserved.'

    Description          = 'Relaunches the current Windows Terminal session elevated or unelevated, reusing the same profile and working directory, or runs a script block in a new elevated/unelevated session. Falls back to a new PowerShell host outside Windows Terminal.'

    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    RequiredModules      = @()

    FunctionsToExport    = @('Invoke-Elevation', 'Invoke-Unelevation')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('el', 'isudo', 'elevate', 'uel')

    PrivateData          = @{
        PSData = @{
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
            Tags         = @('Elevation', 'Unelevation', 'Administrator', 'RunAs', 'UAC', 'WindowsTerminal', 'Windows')
            ProjectUri   = 'https://github.com/genchadt/Profile_WindowsPS'
            ReleaseNotes = @'
1.1.0
- Add -Unelevate (aliases -u and the bare positional u) to open a non-elevated
  session via runas /trustlevel:0x20000; works only from an elevated session.
- Invoke-Elevation now accepts multiple positional flags (u, x, or u x).
- Add Invoke-Unelevation (alias uel) as the unelevated counterpart to el.
- Combine -Flag (alias -Close) with ValueFromRemainingArguments so old x
  shorthand keeps working.

1.0.0
- Initial release.
- Relaunches the current Windows Terminal profile/directory elevated via wt.exe.
- Falls back to an elevated pwsh/powershell host outside Windows Terminal.
- -ScriptBlock { ... } runs a command in the elevated session (passed via -EncodedCommand).
- -CloseCurrent exits the current session after the elevated window opens; -x and a
  bare positional x are accepted as shorthand.
- Aliases: el, isudo, elevate.
- UAC cancellation reports a warning instead of throwing.
'@
        }
    }
}
