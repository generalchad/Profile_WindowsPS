function Update-VsCode {
    <#
    .SYNOPSIS
        Updates extensions for VS Code and/or VS Code Insiders
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
            & $codeCmd.Source --update-extensions
        } else {
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
            Write-Host "Checking for VS Code Insiders extension updates..." -ForegroundColor Cyan
            & $insidersCmd.Source --update-extensions
        } else {
            Write-Warning "VS Code Insiders executable 'code-insiders' was not found in your system PATH."
        }
    }
}
