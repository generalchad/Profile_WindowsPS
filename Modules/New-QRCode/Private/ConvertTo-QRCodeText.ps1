function ConvertTo-QRCodeText {
    <#
    .SYNOPSIS
        Builds a QR payload string for a preset scan target.

    .DESCRIPTION
        Shared by New-QRCode and Show-QRCode so the command line and the dialog
        produce identical payloads. Wi-Fi, email, SMS and phone use QRCoder's
        PayloadGenerator (which handles the format-specific escaping); vCard and
        geo are emitted directly.

        Requires QRCoder to be loaded; callers initialize it first.

    .PARAMETER Kind
        Text, Wifi, VCard, Email, Sms, Phone, or Geo.

    .PARAMETER Values
        The field values for the chosen kind. Missing keys are treated as empty.

    .OUTPUTS
        System.String. The payload to encode.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Text', 'Wifi', 'VCard', 'Email', 'Sms', 'Phone', 'Geo')]
        [string]$Kind,

        [Parameter()]
        [hashtable]$Values = @{}
    )

    switch ($Kind) {
        'Text' {
            return [string]$Values['Text']
        }

        'Wifi' {
            $auth = [QRCoder.PayloadGenerator+WiFi+Authentication]($Values['Auth'])
            $wifi = [QRCoder.PayloadGenerator+WiFi]::new(
                [string]$Values['Ssid'],
                [string]$Values['Password'],
                $auth,
                [bool]$Values['Hidden'],
                $false
            )
            return $wifi.ToString()
        }

        'VCard' {
            # vCard text values escape backslash, semicolon, comma and newline.
            $esc = {
                param([string]$Value)
                [string]$Value -replace '\\', '\\' -replace ';', '\;' -replace ',', '\,' -replace "`r?`n", '\n'
            }

            $fullName = [string]$Values['FullName']
            $firstName = [string]$Values['FirstName']
            $lastName = [string]$Values['LastName']
            if ([string]::IsNullOrWhiteSpace($firstName) -and [string]::IsNullOrWhiteSpace($lastName) -and $fullName) {
                $parts = $fullName.Trim() -split '\s+'
                if ($parts.Count -gt 1) {
                    $firstName = $parts[0]
                    $lastName = ($parts[1..($parts.Count - 1)] -join ' ')
                }
                else {
                    $firstName = $fullName
                }
            }

            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('BEGIN:VCARD')
            $lines.Add('VERSION:3.0')
            $lines.Add("N:$(& $esc $lastName);$(& $esc $firstName);;;")
            $lines.Add("FN:$(& $esc $fullName)")
            if ($Values['Organization']) { $lines.Add("ORG:$(& $esc $Values['Organization'])") }
            if ($Values['JobTitle']) { $lines.Add("TITLE:$(& $esc $Values['JobTitle'])") }
            # vCard 3.0 phone types: CELL renders as "Mobile" on import; a bare
            # TYPE=VOICE has no labelled slot and lands under "Other".
            foreach ($group in @(
                    @{ Type = 'CELL'; Numbers = $Values['Mobile'] }
                    @{ Type = 'WORK'; Numbers = $Values['Work'] }
                    @{ Type = 'HOME'; Numbers = $Values['Home'] }
                    @{ Type = 'FAX'; Numbers = $Values['Fax'] }
                )) {
                foreach ($number in @($group.Numbers)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$number)) {
                        $lines.Add("TEL;TYPE=$($group.Type):$(& $esc $number)")
                    }
                }
            }
            if ($Values['Email']) { $lines.Add("EMAIL:$(& $esc $Values['Email'])") }
            if ($Values['Website']) { $lines.Add("URL:$(& $esc $Values['Website'])") }
            if ($Values['Note']) { $lines.Add("NOTE:$(& $esc $Values['Note'])") }
            $lines.Add('END:VCARD')
            return ($lines -join "`r`n")
        }

        'Email' {
            $mail = [QRCoder.PayloadGenerator+Mail]::new(
                [string]$Values['To'],
                [string]$Values['Subject'],
                [string]$Values['Body'],
                [QRCoder.PayloadGenerator+Mail+MailEncoding]::MAILTO
            )
            return $mail.ToString()
        }

        'Sms' {
            $sms = [QRCoder.PayloadGenerator+SMS]::new(
                [string]$Values['Number'],
                [string]$Values['Body'],
                [QRCoder.PayloadGenerator+SMS+SMSEncoding]::SMSTO
            )
            return $sms.ToString()
        }

        'Phone' {
            return ([QRCoder.PayloadGenerator+PhoneNumber]::new([string]$Values['Number'])).ToString()
        }

        'Geo' {
            # geo: needs invariant decimal separators, whatever the host locale.
            $lat = ([double]$Values['Latitude']).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $lon = ([double]$Values['Longitude']).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            return "geo:$lat,$lon"
        }
    }
}
