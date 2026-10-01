# =====================================================================
# New-QRCode.Tests.ps1 - generation and render contract verification
#
# Downloads QRCoder into a scratch library folder, so the first run needs
# network access; subsequent runs reuse the download.
#
# Run:
#   pwsh -NoProfile -File .\Modules\New-QRCode\Tests\New-QRCode.Tests.ps1
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
$manifestPath = Join-Path $moduleRoot 'New-QRCode.psd1'

Import-Module $manifestPath -Force

Write-Host "`n--- Testing New-QRCode ---`n" -ForegroundColor Cyan

Test-Case 'Manifest exports New-QRCode, Show-QRCode and Install-QRCoder' {
    (Get-Command New-QRCode -ErrorAction Stop).Name -eq 'New-QRCode' -and
    (Get-Command Show-QRCode -ErrorAction Stop).Name -eq 'Show-QRCode' -and
    (Get-Command Install-QRCoder -ErrorAction Stop).Name -eq 'Install-QRCoder'
}

# Regression: the first-use auto-install used to hand an empty version to the
# downloader, whose -Version is mandatory. Runs before QRCoder is loaded so
# Initialize-QRCoder takes the install branch; the download core is stubbed.
Test-Case 'Auto-install supplies a resolved version to the downloader' {
    $module = Get-Module New-QRCode
    $originals = & $module {
        [pscustomobject]@{
            Request = (Get-Item Function:\Request-QRCoderInstall).ScriptBlock
            Latest  = (Get-Item Function:\Get-QRCoderLatestVersion).ScriptBlock
            Save    = (Get-Item Function:\Save-QRCoderLibrary).ScriptBlock
        }
    }
    $env:NEWQRCODE_LIB = Join-Path $env:TEMP 'New-QRCode-test-autoinstall'
    Remove-Item -LiteralPath $env:NEWQRCODE_LIB -Recurse -Force -ErrorAction SilentlyContinue

    try {
        & $module {
            Set-Item Function:\Request-QRCoderInstall { $true }
            Set-Item Function:\Get-QRCoderLatestVersion { '9.9.9' }
            Set-Item Function:\Save-QRCoderLibrary {
                param(
                    [Parameter(Mandatory)] [string] $Version,
                    [Parameter(Mandatory)] [string] $Destination
                )
                Set-Variable -Name TestSavedVersion -Value $Version -Scope Script
                throw 'stop-after-capture'
            }
        }

        try { & $module { Initialize-QRCoder } | Out-Null } catch { }

        (& $module { Get-Variable -Name TestSavedVersion -Scope Script -ValueOnly }) -eq '9.9.9'
    }
    finally {
        & $module {
            param($o)
            Set-Item Function:\Request-QRCoderInstall $o.Request
            Set-Item Function:\Get-QRCoderLatestVersion $o.Latest
            Set-Item Function:\Save-QRCoderLibrary $o.Save
        } $originals
    }
}

$env:NEWQRCODE_LIB = Join-Path $env:TEMP 'New-QRCode-test-lib'
$scratch = Join-Path $env:TEMP 'New-QRCode-test-output'
Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue

$libraryReady = $false
try {
    Install-QRCoder -Destination $env:NEWQRCODE_LIB | Out-Null
    $libraryReady = $true
}
catch {
    Write-Host "  [SKIP] QRCoder unavailable, generation tests not run: $($_.Exception.Message)" -ForegroundColor Yellow
}

if ($libraryReady) {
    Test-Case 'Console render emits half/full block glyphs' {
        $rendered = & { New-QRCode 'https://example.com' -Console 6>&1 | Out-String }
        $rendered -match [char]0x2588 -or
        $rendered -match [char]0x2580 -or
        $rendered -match [char]0x2584
    }

    Test-Case 'PNG output is written and non-trivial' {
        $png = Join-Path $scratch 'hello.png'
        New-QRCode 'Hello' -Path $png -PixelsPerModule 4 | Out-Null
        (Test-Path -LiteralPath $png) -and (Get-Item -LiteralPath $png).Length -gt 100
    }

    Test-Case 'SVG output is written and starts with <svg' {
        $svg = Join-Path $scratch 'hello.svg'
        New-QRCode 'Hello' -Path $svg | Out-Null
        (Test-Path -LiteralPath $svg) -and
        ([System.IO.File]::ReadAllText($svg).TrimStart().StartsWith('<svg'))
    }

    Test-Case 'Extension drives Format when omitted' {
        $result = New-QRCode 'Hello' -Path (Join-Path $scratch 'inferred.svg')
        $result.Format -eq 'SVG'
    }

    Test-Case 'Directory -Path names files from the text' {
        $directory = Join-Path $scratch 'bulk'
        'https://one.example', 'https://two.example' | New-QRCode -Path $directory | Out-Null
        @(Get-ChildItem -LiteralPath $directory -Filter '*.png').Count -eq 2
    }

    Test-Case 'Pipeline input returns one object per string' {
        @(New-QRCode -Text @('a', 'b', 'c') -Console 6>$null).Count -eq 3
    }

    Test-Case 'Wi-Fi preset builds a WIFI payload' {
        (New-QRCode -Ssid 'Office' -WifiPassword 'hunter2' -Console 6>$null).Text -match '^WIFI:T:WPA;S:Office;P:hunter2;'
    }

    Test-Case 'vCard preset labels phone numbers by type' {
        $vcard = (New-QRCode -FullName 'Jane Doe' `
                -VCardMobile '+15550000001' -VCardWorkPhone '+15550000002' `
                -VCardHomePhone '+15550000003' -VCardFax '+15550000004' `
                -VCardEmail jane@example.com -Console 6>$null).Text
        $vcard.StartsWith('BEGIN:VCARD') -and $vcard -match 'FN:Jane Doe' -and
        $vcard.Contains('TEL;TYPE=CELL:+15550000001') -and
        $vcard.Contains('TEL;TYPE=WORK:+15550000002') -and
        $vcard.Contains('TEL;TYPE=HOME:+15550000003') -and
        $vcard.Contains('TEL;TYPE=FAX:+15550000004')
    }

    Test-Case 'Email, SMS, phone and geo presets use their schemes' {
        $email = (New-QRCode -EmailTo a@b.com -Subject Hi -Console 6>$null).Text
        $sms = (New-QRCode -SmsNumber '+15551234567' -SmsBody hi -Console 6>$null).Text
        $phone = (New-QRCode -PhoneNumber '+15551234567' -Console 6>$null).Text
        $geo = (New-QRCode -Latitude 47.6062 -Longitude -122.3321 -Console 6>$null).Text
        $email.StartsWith('mailto:') -and $sms.StartsWith('SMSTO:') -and $phone.StartsWith('tel:') -and $geo -eq 'geo:47.6062,-122.3321'
    }

    Test-Case 'CSV batch generates one labeled file per row' {
        $csv = Join-Path $scratch 'codes.csv'
        $directory = Join-Path $scratch 'batch'
        @("Text,Label", "https://one.example,One", "https://two.example,Two") |
            Set-Content -LiteralPath $csv
        $results = @(New-QRCode -InputFile $csv -Path $directory)
        $results.Count -eq 2 -and
        (Test-Path -LiteralPath (Join-Path $directory 'One.png')) -and
        (Test-Path -LiteralPath (Join-Path $directory 'Two.png'))
    }

    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nTest Results: $($script:Pass) Passed, $($script:Fail) Failed`n" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) {
    exit 1
}
