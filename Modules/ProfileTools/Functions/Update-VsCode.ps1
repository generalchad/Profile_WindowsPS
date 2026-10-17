function Update-VsCode {
    <#
    .SYNOPSIS
        Updates extensions for VS Code and/or VS Code Insiders.
    .DESCRIPTION
        Resolves the command-line executables for VS Code ('code') and VS Code Insiders
        ('code-insiders') and triggers automated extension updates via '--update-extensions'.
        Checks whether either editor process is active and warns that a window reload may be
        required to complete the extension lifecycle.
    .PARAMETER Stable
        Updates extensions for stable VS Code only.
    .PARAMETER Insiders
        Updates extensions for VS Code Insiders only.
    .EXAMPLE
        Update-VsCode
        Updates extensions for both Stable and Insiders editions if installed.
    .EXAMPLE
        Update-VsCode -Insiders
        Updates extensions exclusively for VS Code Insiders.
    #>
    [CmdletBinding()]
    param (
        [switch]$Stable,
        [switch]$Insiders
    )

    $updateStable = $true
    $updateInsiders = $true

    if ($Stable -and -not $Insiders) { $updateInsiders = $false }
    if ($Insiders -and -not $Stable) { $updateStable = $false }

    # --- Stable Build Execution ---
    if ($updateStable) {
        $codeCmd = @(Get-Command "code" -CommandType Application -ErrorAction SilentlyContinue)[0]

        if ($codeCmd) {
            if (Get-Process -Name "Code" -ErrorAction SilentlyContinue) {
                Write-Warning "VS Code (Stable) is currently open. Extensions will update, but a reload may be required."
            }
            Write-Host "Checking for VS Code (Stable) extension updates..." -ForegroundColor Cyan
            Invoke-VsCodeExtensionUpdate -Executable $codeCmd.Source
        } elseif ($Stable) {
            # Only surface a missing executable when Stable was explicitly requested;
            # on an auto run the edition is simply not installed and is skipped.
            Write-Warning "VS Code (Stable) executable 'code' was not found in your system PATH."
        }
    }

    # --- Insiders Build Execution ---
    if ($updateInsiders) {
        $insidersCmd = @(Get-Command "code-insiders" -CommandType Application -ErrorAction SilentlyContinue)[0]

        if ($insidersCmd) {
            if (Get-Process -Name "Code - Insiders" -ErrorAction SilentlyContinue) {
                Write-Warning "VS Code Insiders is currently open. Extensions will update, but a reload may be required."
            }
            Write-Host "Checking for updates to Help docs..." -ForegroundColor Cyan
            Update-Help -Force -ErrorAction SilentlyContinue
            Write-Host "Checking for VS Code Insiders extension updates..." -ForegroundColor Cyan
            Invoke-VsCodeExtensionUpdate -Executable $insidersCmd.Source
        } elseif ($Insiders) {
            # Only surface a missing executable when Insiders was explicitly requested;
            # on an auto run the edition is simply not installed and is skipped.
            Write-Warning "VS Code Insiders executable 'code-insiders' was not found in your system PATH."
        }
    }
}

function Invoke-VsCodeExtensionUpdate {
    <#
    .SYNOPSIS
        Runs '--update-extensions' for a VS Code CLI, silencing the DEP0169
        url.parse() deprecation warning only while the CLI still emits it.
    .DESCRIPTION
        VS Code's Electron-as-Node CLI calls the deprecated url.parse(), which the
        bundled Node reports as DEP0169 on stderr. That warning and its
        --trace-deprecation hint are stripped from the CLI output and, when found,
        reported with a one-line notice. Once VS Code stops emitting it nothing
        matches, so the suppression and the notice retire themselves.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Executable
    )

    $output = & $Executable --update-extensions 2>&1
    $dep0169 = $false
    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $output) {
        $line = [string]$item
        if ($line -match '\[DEP0169\]' -or $line -match '--trace-deprecation') {
            $dep0169 = $true
            continue
        }
        $kept.Add($item)
    }
    if ($dep0169) {
        Write-Host 'Warning DEP0169 silenced.' -ForegroundColor DarkGray
    }
    $kept
}
