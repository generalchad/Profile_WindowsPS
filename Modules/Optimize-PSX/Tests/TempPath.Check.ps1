# =====================================================================
# TempPath.Check.ps1 - Guards the temporary output naming
#
# $script:TempChdSuffix is appended to an output path that already ends
# in .chd. Spelling the suffix '.chd.tmp' therefore produced
# 'Game.chd.chd.tmp', which was cosmetic but made abandoned artefacts
# hard to recognise and hard to glob for.
#
#   pwsh -NoProfile -File .\Tests\TempPath.Check.ps1
# =====================================================================

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'Optimize-PSX.psd1') -Force
$module = Get-Module -Name Optimize-PSX

$failures = 0

function Test-Case {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Condition,
        [string]$Detail
    )

    if ($Condition) {
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } else {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor DarkGray }
        $script:failures++
    }
}

Write-Host 'Temporary path naming' -ForegroundColor Cyan

# New-OpsxJob is private, so it is invoked inside the module's own scope.
$tempPath = & $module {
    $source = [System.IO.FileInfo]::new('E:\games\Game.cue')
    (New-OpsxJob -Source $source -OutputPath 'E:\games\Game.chd' -Command 'createcd').TempPath
}

Test-Case -Name "temp path is 'Game.chd.tmp'" `
          -Condition ($tempPath -eq 'E:\games\Game.chd.tmp') `
          -Detail "got: '$tempPath'"

Test-Case -Name 'temp path does not double the .chd extension' `
          -Condition ($tempPath -notmatch '\.chd\.chd') `
          -Detail "got: '$tempPath'"

Test-Case -Name 'temp path sits beside its output' `
          -Condition ([System.IO.Path]::GetDirectoryName($tempPath) -eq 'E:\games')

Write-Host ''
if ($failures -eq 0) {
    Write-Host 'Temporary path naming is correct.' -ForegroundColor Green
    exit 0
}

Write-Host "$failures check(s) failed." -ForegroundColor Red
exit 1
