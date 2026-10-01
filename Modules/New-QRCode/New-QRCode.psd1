@{
    RootModule           = 'New-QRCode.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '55f48fef-0674-4dd2-b302-3dd4b6ae7d51'
    Author               = 'Timothy W. Brown'
    CompanyName          = 'Timothy W. Brown'
    Copyright            = '(c) Timothy W. Brown. Authored with LLM assistance (Anthropic Claude, Google Gemini, DeepSeek). All rights reserved.'

    Description          = 'Renders text, URLs, and preset payloads (Wi-Fi, vCard, email, SMS, phone, geo) to a QR code in the console, a PNG/SVG file, or a Windows Forms dialog. Uses the QRCoder library, which is downloaded on demand with Install-QRCoder and is never tracked in the repository.'

    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @('New-QRCode', 'Show-QRCode', 'Install-QRCoder')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    FileList             = @(
        'New-QRCode.psd1'
        'New-QRCode.psm1'
        'Public/New-QRCode.ps1'
        'Public/Show-QRCode.ps1'
        'Public/Install-QRCoder.ps1'
        'Private/ConvertTo-QRCodeText.ps1'
        'Private/Get-QRCodeData.ps1'
        'Private/Get-QRCoderLibDirectory.ps1'
        'Private/Get-QRCoderLatestVersion.ps1'
        'Private/Get-QRCodeOutputPath.ps1'
        'Private/Get-QRCodeSlug.ps1'
        'Private/Initialize-QRCoder.ps1'
        'Private/Request-QRCoderInstall.ps1'
        'Private/Save-QRCoderLibrary.ps1'
        'Private/Write-QRCodeConsole.ps1'
        'Tests/New-QRCode.Tests.ps1'
    )

    PrivateData          = @{
        PSData = @{
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
            Tags       = @('QRCode', 'QR', 'Barcode', 'PNG', 'SVG', 'Console')
            ProjectUri = 'https://github.com/genchadt/Profile_WindowsPS'
        }
    }
}
