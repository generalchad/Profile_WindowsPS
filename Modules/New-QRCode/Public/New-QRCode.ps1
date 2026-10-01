function New-QRCode {
    <#
    .SYNOPSIS
        Renders text, a URL, or a preset payload (Wi-Fi, vCard, email, SMS, phone,
        geo) as a QR code in the console and/or to a PNG or SVG file.

    .DESCRIPTION
        Encodes each input with the QRCoder library and renders it. With no -Path
        the code is drawn in the console; -Console forces console output even when
        a file is written, so both can be produced in one call.

        Besides free text (-Text), the common scan targets are built from their
        parts: -Ssid (Wi-Fi), -FullName (vCard), -EmailTo, -SmsNumber,
        -PhoneNumber, and -Latitude/-Longitude (geo). -InputFile reads a CSV with a
        Text column and an optional Label column and generates one code per row.

        QRCoder is not bundled with this module. The first call offers to download
        it; in a non-interactive host, run Install-QRCoder first.

    .PARAMETER Text
        One or more strings to encode. Accepts pipeline input.

    .PARAMETER InputFile
        A CSV file with a Text column and an optional Label column. One QR code is
        generated per row; Label overrides the file name in directory mode.

    .PARAMETER Ssid
        Wi-Fi network name (SSID). Selects the Wi-Fi payload.

    .PARAMETER WifiPassword
        Wi-Fi password. Omit for an open network (use -WifiAuth nopass).

    .PARAMETER WifiAuth
        Wi-Fi security: WPA (default), WPA2, WEP, or nopass.

    .PARAMETER WifiHidden
        Mark the SSID as hidden.

    .PARAMETER FullName
        Contact display name. Selects the vCard payload.

    .PARAMETER FirstName
        Optional given name; derived from FullName when omitted.

    .PARAMETER LastName
        Optional family name; derived from FullName when omitted.

    .PARAMETER VCardMobile
        One or more mobile numbers, emitted as TEL;TYPE=CELL (shown as "Mobile").

    .PARAMETER VCardWorkPhone
        One or more work numbers, emitted as TEL;TYPE=WORK.

    .PARAMETER VCardHomePhone
        One or more home numbers, emitted as TEL;TYPE=HOME.

    .PARAMETER VCardFax
        One or more fax numbers, emitted as TEL;TYPE=FAX.

    .PARAMETER VCardEmail
        Contact email address.

    .PARAMETER Organization
        Optional organization name.

    .PARAMETER JobTitle
        Optional job title.

    .PARAMETER Website
        Optional website URL.

    .PARAMETER Note
        Optional contact note.

    .PARAMETER EmailTo
        Recipient address. Selects the email payload.

    .PARAMETER Subject
        Optional email subject.

    .PARAMETER Body
        Optional email body.

    .PARAMETER SmsNumber
        Destination number. Selects the SMS payload.

    .PARAMETER SmsBody
        Optional SMS body.

    .PARAMETER PhoneNumber
        Phone number to dial. Selects the phone payload.

    .PARAMETER Latitude
        Geo latitude. Selects the geo payload.

    .PARAMETER Longitude
        Geo longitude. Selects the geo payload.

    .PARAMETER ECCLevel
        Error-correction level: L (7%), M (15%), Q (25%), or H (30%). Defaults to Q.

    .PARAMETER Path
        Where to write the code. A path that is a directory (or has no extension)
        generates the file name from the Label or the text; a file path is used as
        given. When multiple inputs share a directory, each gets its own file.

    .PARAMETER Format
        PNG (default) or SVG. Inferred from a .svg -Path when omitted.

    .PARAMETER PixelsPerModule
        Module size in pixels for file output. Defaults to 10.

    .PARAMETER Console
        Draw the code in the console. Implied when -Path is not supplied.

    .OUTPUTS
        PSCustomObject per input (Text, Label, ECCLevel, Version, Modules, Format,
        Path, Console).

    .EXAMPLE
        New-QRCode 'https://example.com'

    .EXAMPLE
        New-QRCode -Ssid 'Office' -WifiPassword 'hunter2' -Console

    .EXAMPLE
        New-QRCode -FullName 'Jane Doe' -VCardMobile '+15551234567' -VCardEmail jane@example.com -Path .\jane.png

    .EXAMPLE
        New-QRCode -EmailTo help@example.com -Subject 'Support' -Console

    .EXAMPLE
        New-QRCode -InputFile .\codes.csv -Path .\codes -Format SVG
    #>
    [CmdletBinding(DefaultParameterSetName = 'Text', SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Text')]
        [Alias('Content', 'Value', 'InputObject')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Text,

        [Parameter(Mandatory, ParameterSetName = 'Csv')]
        [ValidateNotNullOrEmpty()]
        [string]$InputFile,

        [Parameter(Mandatory, ParameterSetName = 'Wifi')]
        [string]$Ssid,
        [Parameter(ParameterSetName = 'Wifi')]
        [string]$WifiPassword,
        [Parameter(ParameterSetName = 'Wifi')]
        [ValidateSet('WPA', 'WPA2', 'WEP', 'nopass')]
        [string]$WifiAuth = 'WPA',
        [Parameter(ParameterSetName = 'Wifi')]
        [switch]$WifiHidden,

        [Parameter(Mandatory, ParameterSetName = 'VCard')]
        [string]$FullName,
        [Parameter(ParameterSetName = 'VCard')]
        [string]$FirstName,
        [Parameter(ParameterSetName = 'VCard')]
        [string]$LastName,
        [Parameter(ParameterSetName = 'VCard')]
        [string[]]$VCardMobile,
        [Parameter(ParameterSetName = 'VCard')]
        [string[]]$VCardWorkPhone,
        [Parameter(ParameterSetName = 'VCard')]
        [string[]]$VCardHomePhone,
        [Parameter(ParameterSetName = 'VCard')]
        [string[]]$VCardFax,
        [Parameter(ParameterSetName = 'VCard')]
        [string]$VCardEmail,
        [Parameter(ParameterSetName = 'VCard')]
        [string]$Organization,
        [Parameter(ParameterSetName = 'VCard')]
        [string]$JobTitle,
        [Parameter(ParameterSetName = 'VCard')]
        [string]$Website,
        [Parameter(ParameterSetName = 'VCard')]
        [string]$Note,

        [Parameter(Mandatory, ParameterSetName = 'Email')]
        [string]$EmailTo,
        [Parameter(ParameterSetName = 'Email')]
        [string]$Subject,
        [Parameter(ParameterSetName = 'Email')]
        [string]$Body,

        [Parameter(Mandatory, ParameterSetName = 'Sms')]
        [string]$SmsNumber,
        [Parameter(ParameterSetName = 'Sms')]
        [string]$SmsBody,

        [Parameter(Mandatory, ParameterSetName = 'Phone')]
        [string]$PhoneNumber,

        [Parameter(Mandatory, ParameterSetName = 'Geo')]
        [double]$Latitude,
        [Parameter(Mandatory, ParameterSetName = 'Geo')]
        [double]$Longitude,

        [Parameter()]
        [ValidateSet('L', 'M', 'Q', 'H')]
        [string]$ECCLevel = 'Q',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateSet('PNG', 'SVG')]
        [string]$Format,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$PixelsPerModule = 10,

        [Parameter()]
        [switch]$Console
    )

    begin {
        Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue

        try {
            $null = Initialize-QRCoder
        }
        catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'QRCoderUnavailable',
                [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                $null
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $writeFile = $PSBoundParameters.ContainsKey('Path')
        $writeConsole = $Console.IsPresent -or -not $writeFile

        if (-not $Format) {
            $Format = if ($writeFile -and [System.IO.Path]::GetExtension($Path) -ieq '.svg') { 'SVG' } else { 'PNG' }
        }

        $index = 0
        $presetItem = $null
        $csvItems = $null

        switch ($PSCmdlet.ParameterSetName) {
            'Wifi' {
                $presetItem = @{
                    Text  = ConvertTo-QRCodeText -Kind Wifi -Values @{
                        Ssid     = $Ssid
                        Password = $WifiPassword
                        Auth     = $WifiAuth
                        Hidden   = $WifiHidden.IsPresent
                    }
                    Label = $Ssid
                }
            }
            'VCard' {
                $presetItem = @{
                    Text  = ConvertTo-QRCodeText -Kind VCard -Values @{
                        FullName     = $FullName
                        FirstName    = $FirstName
                        LastName     = $LastName
                        Mobile       = $VCardMobile
                        Work         = $VCardWorkPhone
                        Home         = $VCardHomePhone
                        Fax          = $VCardFax
                        Email        = $VCardEmail
                        Organization = $Organization
                        JobTitle     = $JobTitle
                        Website      = $Website
                        Note         = $Note
                    }
                    Label = $FullName
                }
            }
            'Email' {
                $presetItem = @{
                    Text  = ConvertTo-QRCodeText -Kind Email -Values @{
                        To      = $EmailTo
                        Subject = $Subject
                        Body    = $Body
                    }
                    Label = $EmailTo
                }
            }
            'Sms' {
                $presetItem = @{
                    Text  = ConvertTo-QRCodeText -Kind Sms -Values @{ Number = $SmsNumber; Body = $SmsBody }
                    Label = $SmsNumber
                }
            }
            'Phone' {
                $presetItem = @{
                    Text  = ConvertTo-QRCodeText -Kind Phone -Values @{ Number = $PhoneNumber }
                    Label = $PhoneNumber
                }
            }
            'Geo' {
                $presetItem = @{
                    Text  = ConvertTo-QRCodeText -Kind Geo -Values @{ Latitude = $Latitude; Longitude = $Longitude }
                    Label = "$Latitude,$Longitude"
                }
            }
            'Csv' {
                $csvItems = [System.Collections.Generic.List[object]]::new()
                foreach ($row in Import-Csv -LiteralPath $InputFile) {
                    $rowText = $null
                    foreach ($column in 'Text', 'Content', 'InputObject') {
                        if ($row.PSObject.Properties[$column]) {
                            $rowText = [string]$row.$column
                            break
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace($rowText)) {
                        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                            [System.FormatException]::new("The CSV file '$InputFile' has a row without a Text value."),
                            'QRCodeCsvRowMissingText',
                            [System.Management.Automation.ErrorCategory]::InvalidData,
                            $row
                        )
                        $PSCmdlet.ThrowTerminatingError($errorRecord)
                    }
                    $label = if ($row.PSObject.Properties['Label']) { [string]$row.Label } else { $null }
                    $csvItems.Add(@{ Text = $rowText; Label = $label })
                }
            }
        }
    }

    process {
        $batch = switch ($PSCmdlet.ParameterSetName) {
            'Text' { foreach ($entry in $Text) { @{ Text = $entry; Label = $null } } }
            'Csv' { $csvItems }
            default { $presetItem }
        }

        foreach ($item in @($batch)) {
            $index++

            try {
                $data = Get-QRCodeData -Text $item.Text -ECCLevel $ECCLevel
            }
            catch {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'QRCoderGenerationFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $item.Text
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            if ($writeConsole) {
                Write-QRCodeConsole -Matrix $data.ModuleMatrix
            }

            $outputPath = $null
            if ($writeFile) {
                $targetPath = Get-QRCodeOutputPath -Path $Path -Text $item.Text -Label $item.Label -Format $Format -Index $index
                if ($PSCmdlet.ShouldProcess($targetPath, "Write $Format QR code")) {
                    $parent = Split-Path -Path $targetPath -Parent
                    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                        $null = New-Item -ItemType Directory -Path $parent -Force
                    }

                    switch ($Format) {
                        'PNG' {
                            $bytes = [QRCoder.PngByteQRCode]::new($data).GetGraphic($PixelsPerModule, $true)
                            [System.IO.File]::WriteAllBytes($targetPath, $bytes)
                        }
                        'SVG' {
                            $svg = [QRCoder.SvgQRCode]::new($data).GetGraphic($PixelsPerModule)
                            [System.IO.File]::WriteAllText($targetPath, $svg, [System.Text.UTF8Encoding]::new($false))
                        }
                    }
                    $outputPath = $targetPath
                }
            }

            [PSCustomObject]@{
                Text     = $item.Text
                Label    = $item.Label
                ECCLevel = $ECCLevel
                Version  = $data.Version
                Modules  = $data.ModuleMatrix.Count
                Format   = if ($writeFile) { $Format } else { $null }
                Path     = $outputPath
                Console  = [bool]$writeConsole
            }
        }
    }
}
