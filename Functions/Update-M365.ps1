<#
.SYNOPSIS
    Launches the Office update process.

.DESCRIPTION
    Launches the Office Click-to-Run update installer.

.PARAMETER C2RClientPath
    The path to the Office Click-to-Run client executable.
    By default, this is set to "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe".

.PARAMETER C2R_args
    The arguments to pass to the Office Click-to-Run client executable.
    By default, this is set to "/update user". 
    Documentation is seemingly not available for the C2R client so it's not recommended to change.
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$C2RClientPath = "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe",

    [Parameter(Position = 1)]
    [string]$C2R_args = "/update user"
)

$C2RClientName = [System.IO.Path]::GetFileName($C2RClientPath)

try {
    Write-Verbose "Attemping to launch $C2RClientName..."
    Write-Verbose "C2R Command: $C2RClientPath $C2R_args"
    Start-Process -FilePath $C2RClientPath -ArgumentList $C2R_args
}
catch {
    Write-Warning "Failed to start Office update process: $_"
    Write-Debug "C2RClientPath: $C2RClientPath"
    Write-Debug "C2R_args: $C2R_args"
    Write-Debug "Line: $($_.InvocationInfo.ScriptLineNumber)"
}