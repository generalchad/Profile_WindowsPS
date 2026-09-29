# =====================================================================
# Install-ScanShare.Tests.ps1 - Installer & Packaging Verification Suite
#
# End-to-end tests for the New-ScanShare portable installer. It builds the
# real Dist zip, extracts it, then drives Install-ScanShare.ps1 and
# Uninstall-ScanShare.ps1 over the shipped package.
#
# Covers: artifact layout, install, idempotency, version handling, fresh-
# process autoload on PowerShell 7 and Windows PowerShell 5.1, the Desktop
# shortcut, uninstall, and the failure paths (missing/corrupt bundle,
# blocked root, unreadable existing install, launch failure, .cmd wrapper).
#
# Nothing is written to the real user module paths or Desktop: every install
# targets a temp root, and any pre-existing "New Scan Share.lnk" is backed
# up and restored.
#
# Run:
#   pwsh -NoProfile -File .\Modules\New-ScanShare\Tests\Install-ScanShare.Tests.ps1
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:Pass = 0
$script:Fail = 0

function Test-Case {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Body
    )

    try {
        $result = & $Body
        if ($result) {
            Write-Host "  [PASS] $Name" -ForegroundColor Green
            $script:Pass++
        }
        else {
            Write-Host "  [FAIL] $Name" -ForegroundColor Red
            $script:Fail++
        }
    }
    catch {
        Write-Host "  [FAIL] $Name : $($_.Exception.Message)" -ForegroundColor Red
        $script:Fail++
    }
}

$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
$deployRoot = Join-Path $moduleRoot 'Deploy'
$moduleName = 'New-ScanShare'
$manifestName = 'New-ScanShare.psd1'
$sourceVersion = [version](Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot $manifestName))['ModuleVersion']

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'New Scan Share.lnk'
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$pathSeparator = [System.IO.Path]::PathSeparator

$sandbox = Join-Path $env:TEMP ("ScanShare-InstallTests-" + [guid]::NewGuid().ToString('n'))
$psModulePath0 = $env:PSModulePath
$shortcutBackup = Join-Path $sandbox 'shortcut-backup.lnk'
$hadShortcut = Test-Path -LiteralPath $shortcutPath

function New-TempRoot {
    param([Parameter(Mandatory)][string]$Name)
    $path = Join-Path $sandbox $Name
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Add-VersionedModule {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Version,
        [string]$Psm1 = 'function Test-Stub { }'
    )
    $target = Join-Path $Root $moduleName
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $manifest = "@{ RootModule = '$moduleName.psm1'; ModuleVersion = '$Version'; GUID = 'b735b035-cf82-4c2a-a47e-13783d33079e' }"
    Set-Content -LiteralPath (Join-Path $target $manifestName) -Value $manifest
    Set-Content -LiteralPath (Join-Path $target "$moduleName.psm1") -Value $Psm1
    return $target
}

function New-PackageCopy {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Package
    )
    $dest = Join-Path $sandbox $Name
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $Package '*') -Destination $dest -Recurse -Force
    return $dest
}

function Get-InstalledManifestVersion {
    param([Parameter(Mandatory)][string]$Root)
    ([version](Import-PowerShellDataFile -LiteralPath (Join-Path $Root "$moduleName\$manifestName"))['ModuleVersion'])
}

New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

try {
    if ($hadShortcut) { Copy-Item -LiteralPath $shortcutPath -Destination $shortcutBackup -Force }

    # Build the exact artifact coworkers receive and extract it.
    $dist = Join-Path $sandbox 'dist'
    & (Join-Path $deployRoot 'New-ScanSharePackage.ps1') -OutputPath $dist | Out-Null
    $zip = Get-ChildItem -LiteralPath $dist -Filter '*.zip' | Select-Object -First 1
    $extract = Join-Path $sandbox 'extracted'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip.FullName, $extract)
    $package = Join-Path $extract 'New-ScanShare-Portable'
    $installer = Join-Path $package 'Install-ScanShare.ps1'
    $uninstaller = Join-Path $package 'Uninstall-ScanShare.ps1'

    Write-Host "`n--- 1. Packaged artifact ---`n" -ForegroundColor Cyan

    Test-Case 'Build produces a versioned portable zip' {
        $zip.Name -match '^New-ScanShare-Portable-\d+\.\d+\.\d+\.zip$'
    }

    Test-Case 'Package ships the module beside the installer' {
        (Test-Path -LiteralPath (Join-Path $package 'Install-ScanShare.cmd')) -and
        (Test-Path -LiteralPath (Join-Path $package 'Uninstall-ScanShare.ps1')) -and
        (Test-Path -LiteralPath (Join-Path $package "$moduleName\$manifestName"))
    }

    Test-Case 'Package excludes Tests and Deploy' {
        -not (Test-Path -LiteralPath (Join-Path $package "$moduleName\Tests")) -and
        -not (Test-Path -LiteralPath (Join-Path $package "$moduleName\Deploy"))
    }

    Write-Host "`n--- 2. Install ---`n" -ForegroundColor Cyan

    Test-Case 'Install copies the module to every requested root' {
        $r1 = New-TempRoot 'install-a'
        $r2 = New-TempRoot 'install-b'
        & $installer -ModulesPath $r1, $r2 -NoShortcut -NoLaunch | Out-Null
        (Test-Path -LiteralPath (Join-Path $r1 "$moduleName\$manifestName")) -and
        (Test-Path -LiteralPath (Join-Path $r2 "$moduleName\$manifestName"))
    }

    Test-Case 'Installed tree matches the source without Tests and Deploy' {
        $root = New-TempRoot 'install-tree'
        & $installer -ModulesPath $root -NoShortcut -NoLaunch | Out-Null
        # Get-Item canonicalizes 8.3 short roots so the relative-name slicing
        # matches the long FullName values Get-ChildItem returns.
        $sourceRoot = (Get-Item -LiteralPath $moduleRoot).FullName
        $sourceFiles = Get-ChildItem -Recurse -File $sourceRoot |
            Where-Object { @('Tests', 'Deploy') -notcontains ($_.FullName.Substring($sourceRoot.Length + 1) -split '\\')[0] } |
            ForEach-Object { $_.FullName.Substring($sourceRoot.Length + 1) } | Sort-Object
        $installedRoot = (Get-Item -LiteralPath (Join-Path $root $moduleName)).FullName
        $installedFiles = Get-ChildItem -Recurse -File $installedRoot |
            ForEach-Object { $_.FullName.Substring($installedRoot.Length + 1) } | Sort-Object
        ($sourceFiles -join '|') -eq ($installedFiles -join '|')
    }

    Test-Case 'Install creates missing module roots' {
        $root = Join-Path $sandbox 'deep\does\not\exist'
        & $installer -ModulesPath $root -NoShortcut -NoLaunch | Out-Null
        Test-Path -LiteralPath (Join-Path $root "$moduleName\$manifestName")
    }

    Test-Case 'Re-running install leaves the existing copy untouched' {
        $root = New-TempRoot 'install-idempotent'
        & $installer -ModulesPath $root -NoShortcut -NoLaunch | Out-Null
        $sentinel = Join-Path $root "$moduleName\sentinel.txt"
        Set-Content -LiteralPath $sentinel -Value 'x'
        & $installer -ModulesPath $root -NoShortcut -NoLaunch | Out-Null
        Test-Path -LiteralPath $sentinel
    }

    Test-Case '-Force replaces the installed copy' {
        $root = New-TempRoot 'install-force'
        & $installer -ModulesPath $root -NoShortcut -NoLaunch | Out-Null
        $sentinel = Join-Path $root "$moduleName\sentinel.txt"
        Set-Content -LiteralPath $sentinel -Value 'x'
        & $installer -ModulesPath $root -NoShortcut -NoLaunch -Force | Out-Null
        -not (Test-Path -LiteralPath $sentinel)
    }

    Test-Case 'Install skips a newer installed version' {
        $root = New-TempRoot 'install-newer'
        Add-VersionedModule -Root $root -Version '9.9.9' | Out-Null
        & $installer -ModulesPath $root -NoShortcut -NoLaunch | Out-Null
        (Get-InstalledManifestVersion -Root $root) -eq [version]'9.9.9'
    }

    Test-Case 'Install replaces an older installed version' {
        $root = New-TempRoot 'install-older'
        Add-VersionedModule -Root $root -Version '0.0.1' | Out-Null
        & $installer -ModulesPath $root -NoShortcut -NoLaunch | Out-Null
        (Get-InstalledManifestVersion -Root $root) -eq $sourceVersion
    }

    Write-Host "`n--- 3. Fresh-process autoload ---`n" -ForegroundColor Cyan

    Test-Case 'Installed module autoloads in a fresh PowerShell 7 process' {
        $root = New-TempRoot 'autoload-ps7'
        & $installer -ModulesPath $root -NoShortcut -NoLaunch | Out-Null
        $env:PSModulePath = "$root$pathSeparator$psModulePath0"
        try {
            $name = (& pwsh -NoProfile -ExecutionPolicy Bypass -Command '(Get-Command Show-ScanShare).Name')
        }
        finally {
            $env:PSModulePath = $psModulePath0
        }
        $name -eq 'Show-ScanShare'
    }

    Test-Case 'Installed module autoloads in Windows PowerShell 5.1' {
        $root = New-TempRoot 'autoload-51'
        & $installer -ModulesPath $root -NoShortcut -NoLaunch | Out-Null
        $env:PSModulePath = "$root$pathSeparator$psModulePath0"
        try {
            $name = (& $ps51 -NoProfile -ExecutionPolicy Bypass -Command '(Get-Command Show-ScanShare).Name')
        }
        finally {
            $env:PSModulePath = $psModulePath0
        }
        $name -eq 'Show-ScanShare'
    }

    Write-Host "`n--- 4. Desktop shortcut ---`n" -ForegroundColor Cyan

    Test-Case 'Install creates a shortcut that runs Show-ScanShare with Bypass' {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
        $root = New-TempRoot 'shortcut-create'
        & $installer -ModulesPath $root -NoLaunch | Out-Null
        if (-not (Test-Path -LiteralPath $shortcutPath)) { return $false }
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($shortcutPath)
        ($link.TargetPath -match '(?i)\\pwsh\.exe$|\\powershell\.exe$') -and
        ($link.Arguments -match 'ExecutionPolicy\s+Bypass') -and
        ($link.Arguments -match 'Show-ScanShare')
    }

    Test-Case 'Uninstall removes the Desktop shortcut' {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
        $root = New-TempRoot 'shortcut-remove'
        & $installer -ModulesPath $root -NoLaunch | Out-Null
        $created = Test-Path -LiteralPath $shortcutPath
        & $uninstaller -ModulesPath $root | Out-Null
        $created -and -not (Test-Path -LiteralPath $shortcutPath)
    }

    Write-Host "`n--- 5. Uninstall ---`n" -ForegroundColor Cyan

    Test-Case 'Uninstall removes the module from every root' {
        $r1 = New-TempRoot 'uninstall-a'
        $r2 = New-TempRoot 'uninstall-b'
        & $installer -ModulesPath $r1, $r2 -NoShortcut -NoLaunch | Out-Null
        & $uninstaller -ModulesPath $r1, $r2 -NoShortcut | Out-Null
        -not (Test-Path -LiteralPath (Join-Path $r1 $moduleName)) -and
        -not (Test-Path -LiteralPath (Join-Path $r2 $moduleName))
    }

    Test-Case 'Uninstall succeeds when nothing is installed' {
        $root = New-TempRoot 'uninstall-empty'
        & $uninstaller -ModulesPath $root -NoShortcut | Out-Null
        $true
    }

    Write-Host "`n--- 6. Exception handling ---`n" -ForegroundColor Cyan

    Test-Case 'Install fails clearly when the bundled module is missing' {
        $broken = New-PackageCopy -Name 'broken-missing' -Package $package
        Remove-Item -LiteralPath (Join-Path $broken $moduleName) -Recurse -Force
        try {
            & (Join-Path $broken 'Install-ScanShare.ps1') -ModulesPath (New-TempRoot 'x-missing') -NoShortcut -NoLaunch | Out-Null
            $false
        }
        catch {
            $_.Exception.Message -match 'Bundled module not found'
        }
    }

    Test-Case 'Install fails clearly when the bundled manifest is unreadable' {
        $broken = New-PackageCopy -Name 'broken-manifest' -Package $package
        Set-Content -LiteralPath (Join-Path $broken "$moduleName\$manifestName") -Value '@{ ModuleVersion = }'
        try {
            & (Join-Path $broken 'Install-ScanShare.ps1') -ModulesPath (New-TempRoot 'x-manifest') -NoShortcut -NoLaunch | Out-Null
            $false
        }
        catch {
            $_.Exception.Message -match 'could not be read'
        }
    }

    Test-Case 'Install fails clearly when a module root is a file' {
        $fileRoot = Join-Path $sandbox 'root-is-a-file'
        Set-Content -LiteralPath $fileRoot -Value 'x'
        try {
            & $installer -ModulesPath $fileRoot -NoShortcut -NoLaunch | Out-Null
            $false
        }
        catch {
            $_.Exception.Message -match 'is a file, not a folder'
        }
    }

    Test-Case 'Install recovers from an unreadable existing install' {
        $root = New-TempRoot 'recover'
        & $installer -ModulesPath $root -NoShortcut -NoLaunch | Out-Null
        Set-Content -LiteralPath (Join-Path $root "$moduleName\$manifestName") -Value '@{ ModuleVersion = }'
        $output = & $installer -ModulesPath $root -NoShortcut -NoLaunch 3>&1
        $warned = ($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object Message) -join ' '
        $recovered = (Get-InstalledManifestVersion -Root $root) -eq $sourceVersion
        $recovered -and ($warned -match 'unreadable')
    }

    Test-Case 'Install reports a launch failure without losing the install' {
        $root = New-TempRoot 'launch-fail'
        Add-VersionedModule -Root $root -Version '9.9.9' -Psm1 'function {' | Out-Null
        $threw = $false
        $message = ''
        try {
            & $installer -ModulesPath $root -NoShortcut | Out-Null
        }
        catch {
            $threw = $true
            $message = $_.Exception.Message
        }
        $threw -and ($message -match 'could not be opened') -and
        (Test-Path -LiteralPath (Join-Path $root "$moduleName\$manifestName"))
    }

    Test-Case 'The .cmd wrapper installs and exits 0' {
        $root = New-TempRoot 'cmd-wrapper'
        $cmd = Join-Path $package 'Install-ScanShare.cmd'
        & $cmd -ModulesPath $root -NoLaunch -NoShortcut | Out-Null
        ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath (Join-Path $root "$moduleName\$manifestName"))
    }

    Write-Host "`nTest Results: $($script:Pass) Passed, $($script:Fail) Failed`n" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
}
finally {
    $env:PSModulePath = $psModulePath0
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    if ($hadShortcut -and (Test-Path -LiteralPath $shortcutBackup)) {
        Copy-Item -LiteralPath $shortcutBackup -Destination $shortcutPath -Force
    }
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($script:Fail -gt 0) {
    exit 1
}
