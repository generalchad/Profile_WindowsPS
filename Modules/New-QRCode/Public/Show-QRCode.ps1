function Show-QRCode {
    <#
    .SYNOPSIS
        Opens a Windows Forms dialog that builds and previews a QR code.

    .DESCRIPTION
        A graphical front end for New-QRCode. Pick a payload type (text/URL,
        Wi-Fi, vCard, email, SMS, phone, geo), fill in the fields, and click
        Generate. From the dialog you can copy the image to the clipboard, save a
        PNG or SVG, or print it.

        The dialog is a convenience wrapper: New-QRCode stays the supported
        command-line entry point and the headless path, and the same payload
        builders feed both.

        Windows Forms is loaded only when the dialog opens, so importing the module
        stays fast and headless sessions are unaffected.

    .EXAMPLE
        Show-QRCode

    .OUTPUTS
        None. Use New-QRCode for scripted output.

    .NOTES
        Windows only; requires an interactive desktop. The first use downloads the
        QRCoder library (see Install-QRCoder).
    #>
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue

    # The dialog drives QRCoder directly for the preview, so make sure it is
    # present before the form appears rather than failing on the first Generate.
    $null = Initialize-QRCoder

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $typeMap = @('Text', 'Wifi', 'VCard', 'Email', 'Sms', 'Phone', 'Geo')
    $typeLabels = @('Text / URL', 'Wi-Fi network', 'Contact (vCard)', 'Email', 'SMS', 'Phone call', 'Location (geo)')

    $toolTip = [System.Windows.Forms.ToolTip]::new()
    $toolTip.AutoPopDelay = 30000
    $toolTip.InitialDelay = 400
    $toolTip.ReshowDelay = 100
    $toolTip.ShowAlways = $true

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'New QR Code'
    $form.ClientSize = [System.Drawing.Size]::new(700, 534)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Font = [System.Drawing.Font]::new('Segoe UI', 9)

    $groups = @{}

    # A short, faint dotted leader in the gap left of a field so the eye connects
    # the label across the empty label column. A 1px line proved too faint to see.
    function New-Dash {
        param([Parameter(Mandatory)][int]$Top)
        $dash = [System.Windows.Forms.Label]::new()
        $dash.Text = '.....'
        $dash.AutoSize = $false
        $dash.Font = [System.Drawing.Font]::new('Segoe UI', 8)
        $dash.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
        $dash.Location = [System.Drawing.Point]::new(110, $Top)
        $dash.Size = [System.Drawing.Size]::new(18, 23)
        $dash.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
        $form.Controls.Add($dash)
        return $dash
    }

    function New-Field {
        param(
            [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Group,
            [Parameter(Mandatory)][string]$Label,
            [Parameter(Mandatory)][int]$Top,
            [Parameter()][int]$Width = 280,
            [Parameter()][switch]$Multiline,
            [Parameter()][int]$Height = 23,
            [Parameter()][string]$Hint
        )

        $caption = [System.Windows.Forms.Label]::new()
        $caption.Text = $Label
        $caption.Location = [System.Drawing.Point]::new(15, ($Top + 3))
        $caption.Size = [System.Drawing.Size]::new(94, 20)
        $caption.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $form.Controls.Add($caption)
        $Group.Add($caption)
        $Group.Add((New-Dash -Top $Top))

        $box = [System.Windows.Forms.TextBox]::new()
        $box.Location = [System.Drawing.Point]::new(130, $Top)
        $box.Size = [System.Drawing.Size]::new($Width, $Height)
        if ($Multiline) {
            $box.Multiline = $true
            $box.AcceptsReturn = $true
            $box.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
        }
        if ($Hint) { $toolTip.SetToolTip($box, $Hint) }
        $form.Controls.Add($box)
        $Group.Add($box)

        return $box
    }

    # Type selector.
    $lblType = [System.Windows.Forms.Label]::new()
    $lblType.Text = '&Type'
    $lblType.Location = [System.Drawing.Point]::new(15, 21)
    $lblType.Size = [System.Drawing.Size]::new(94, 20)
    $lblType.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $form.Controls.Add($lblType)

    $typeCombo = [System.Windows.Forms.ComboBox]::new()
    $typeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $typeCombo.Location = [System.Drawing.Point]::new(130, 18)
    $typeCombo.Size = [System.Drawing.Size]::new(280, 23)
    $typeCombo.Items.AddRange($typeLabels)
    $typeCombo.SelectedIndex = 0
    $form.Controls.Add($typeCombo)
    $null = New-Dash -Top 18

    # Representative type icons (Segoe MDL2 Assets) fill the band between the Type
    # row and the fields; clicking one switches type and the active one is tinted.
    #   E71B Link, E701 Wifi, E779 ContactInfo, E715 Mail, E8BD Message,
    #   E717 Phone, E707 MapPin
    $typeIcons = @([char]0xE71B, [char]0xE701, [char]0xE779, [char]0xE715, [char]0xE8BD, [char]0xE717, [char]0xE707)
    $iconButtons = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $typeIcons.Count; $i++) {
        $icon = [System.Windows.Forms.Label]::new()
        $icon.Text = $typeIcons[$i]
        $icon.Font = [System.Drawing.Font]::new('Segoe MDL2 Assets', 24)
        $icon.Location = [System.Drawing.Point]::new((15 + $i * 56), 46)
        $icon.Size = [System.Drawing.Size]::new(48, 44)
        $icon.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $icon.Cursor = [System.Windows.Forms.Cursors]::Hand
        $icon.Tag = $i
        $toolTip.SetToolTip($icon, $typeLabels[$i])
        $icon.Add_Click({
            param($sender, $e)
            $typeCombo.SelectedIndex = [int]$sender.Tag
        })
        $form.Controls.Add($icon)
        $iconButtons.Add($icon)
    }

    function Update-TypeIcons {
        for ($i = 0; $i -lt $iconButtons.Count; $i++) {
            $iconButtons[$i].ForeColor = if ($i -eq $typeCombo.SelectedIndex) {
                [System.Drawing.Color]::FromArgb(31, 78, 120)
            }
            else {
                [System.Drawing.Color]::FromArgb(190, 190, 190)
            }
        }
    }

    # Text / URL: labelled like the other groups, which frees the band above the
    # fields for the representative type icons.
    $textGroup = [System.Collections.Generic.List[object]]::new()
    $txtText = New-Field -Group $textGroup -Label 'Text / &URL' -Top 92 -Width 280 -Multiline -Height 318
    $txtText.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $txtText.WordWrap = $false
    $txtText.Font = [System.Drawing.Font]::new('Consolas', 9)
    $txtText.Text = 'https://'
    $groups['Text'] = $textGroup

    # Wi-Fi.
    $wifiGroup = [System.Collections.Generic.List[object]]::new()
    $txtSsid = New-Field -Group $wifiGroup -Label 'SS&ID' -Top 92 -Hint 'Wi-Fi network name'
    $txtWifiPassword = New-Field -Group $wifiGroup -Label 'Pass&word' -Top 125 -Hint 'Leave blank for an open network'
    $lblAuth = [System.Windows.Forms.Label]::new()
    $lblAuth.Text = 'Secu&rity'
    $lblAuth.Location = [System.Drawing.Point]::new(15, 161)
    $lblAuth.Size = [System.Drawing.Size]::new(94, 20)
    $lblAuth.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $form.Controls.Add($lblAuth)
    $wifiGroup.Add($lblAuth)
    $cboAuth = [System.Windows.Forms.ComboBox]::new()
    $cboAuth.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cboAuth.Location = [System.Drawing.Point]::new(130, 158)
    $cboAuth.Size = [System.Drawing.Size]::new(120, 23)
    $cboAuth.Items.AddRange(@('WPA', 'WPA2', 'WEP', 'nopass'))
    $cboAuth.SelectedIndex = 0
    $form.Controls.Add($cboAuth)
    $wifiGroup.Add($cboAuth)
    $wifiGroup.Add((New-Dash -Top 158))
    $chkHidden = [System.Windows.Forms.CheckBox]::new()
    $chkHidden.Text = 'Hi&dden network'
    $chkHidden.Location = [System.Drawing.Point]::new(130, 190)
    $chkHidden.Size = [System.Drawing.Size]::new(280, 22)
    $form.Controls.Add($chkHidden)
    $wifiGroup.Add($chkHidden)
    $groups['Wifi'] = $wifiGroup

    # vCard.
    $vcardGroup = [System.Collections.Generic.List[object]]::new()
    $txtFullName = New-Field -Group $vcardGroup -Label 'F&ull name' -Top 92
    $txtMobile = New-Field -Group $vcardGroup -Label '&Mobile' -Top 122
    $txtWork = New-Field -Group $vcardGroup -Label '&Work' -Top 152
    $txtHome = New-Field -Group $vcardGroup -Label 'H&ome' -Top 182
    $txtFax = New-Field -Group $vcardGroup -Label 'Fa&x' -Top 212
    $txtVCardEmail = New-Field -Group $vcardGroup -Label 'Ema&il' -Top 242
    $txtOrg = New-Field -Group $vcardGroup -Label 'Organi&zation' -Top 272
    $txtTitle = New-Field -Group $vcardGroup -Label '&Job title' -Top 302
    $txtWebsite = New-Field -Group $vcardGroup -Label 'We&bsite' -Top 332
    $txtNote = New-Field -Group $vcardGroup -Label '&Note' -Top 362 -Multiline -Height 45
    $groups['VCard'] = $vcardGroup

    # Email.
    $emailGroup = [System.Collections.Generic.List[object]]::new()
    $txtEmailTo = New-Field -Group $emailGroup -Label 'T&o' -Top 92
    $txtSubject = New-Field -Group $emailGroup -Label 'Sub&ject' -Top 125
    $txtEmailBody = New-Field -Group $emailGroup -Label '&Body' -Top 158 -Multiline -Height 160
    $groups['Email'] = $emailGroup

    # SMS.
    $smsGroup = [System.Collections.Generic.List[object]]::new()
    $txtSmsNumber = New-Field -Group $smsGroup -Label '&Number' -Top 92
    $txtSmsBody = New-Field -Group $smsGroup -Label '&Message' -Top 125 -Multiline -Height 160
    $groups['Sms'] = $smsGroup

    # Phone.
    $phoneGroup = [System.Collections.Generic.List[object]]::new()
    $txtPhoneNumber = New-Field -Group $phoneGroup -Label '&Number' -Top 92
    $groups['Phone'] = $phoneGroup

    # Geo.
    $geoGroup = [System.Collections.Generic.List[object]]::new()
    $txtLatitude = New-Field -Group $geoGroup -Label 'Lat&itude' -Top 92
    $txtLongitude = New-Field -Group $geoGroup -Label 'Lo&ngitude' -Top 125
    $groups['Geo'] = $geoGroup

    # Options sit under the input column so the lower-left stays in use.
    $eccLevels = @('L', 'M', 'Q', 'H')

    $lblEcc = [System.Windows.Forms.Label]::new()
    $lblEcc.Text = '&Error level'
    $lblEcc.Location = [System.Drawing.Point]::new(15, 419)
    $lblEcc.Size = [System.Drawing.Size]::new(70, 20)
    $form.Controls.Add($lblEcc)

    $trkEcc = [System.Windows.Forms.TrackBar]::new()
    $trkEcc.AutoSize = $false
    $trkEcc.Location = [System.Drawing.Point]::new(82, 412)
    $trkEcc.Size = [System.Drawing.Size]::new(88, 34)
    $trkEcc.Minimum = 0
    $trkEcc.Maximum = 3
    $trkEcc.TickFrequency = 1
    $trkEcc.SmallChange = 1
    $trkEcc.LargeChange = 1
    $trkEcc.Value = 2
    $toolTip.SetToolTip($trkEcc, 'Error-correction level L/M/Q/H: higher survives more damage but grows the code')
    $form.Controls.Add($trkEcc)

    $lblEccValue = [System.Windows.Forms.Label]::new()
    $lblEccValue.Text = $eccLevels[$trkEcc.Value]
    $lblEccValue.Location = [System.Drawing.Point]::new(172, 419)
    $lblEccValue.Size = [System.Drawing.Size]::new(24, 20)
    $lblEccValue.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblEccValue.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($lblEccValue)

    $lblSize = [System.Windows.Forms.Label]::new()
    $lblSize.Text = '&Size'
    $lblSize.Location = [System.Drawing.Point]::new(204, 419)
    $lblSize.Size = [System.Drawing.Size]::new(28, 20)
    $form.Controls.Add($lblSize)
    $numSize = [System.Windows.Forms.NumericUpDown]::new()
    $numSize.Location = [System.Drawing.Point]::new(234, 415)
    $numSize.Size = [System.Drawing.Size]::new(48, 23)
    $numSize.Minimum = 2
    $numSize.Maximum = 40
    $numSize.Value = 10
    $toolTip.SetToolTip($numSize, 'Pixels per module in the saved file')
    $form.Controls.Add($numSize)

    $lblFormat = [System.Windows.Forms.Label]::new()
    $lblFormat.Text = '&Format'
    $lblFormat.Location = [System.Drawing.Point]::new(292, 419)
    $lblFormat.Size = [System.Drawing.Size]::new(50, 20)
    $form.Controls.Add($lblFormat)
    $cboFormat = [System.Windows.Forms.ComboBox]::new()
    $cboFormat.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cboFormat.Location = [System.Drawing.Point]::new(346, 415)
    $cboFormat.Size = [System.Drawing.Size]::new(64, 23)
    $cboFormat.Items.AddRange(@('PNG', 'SVG'))
    $cboFormat.SelectedIndex = 0
    $form.Controls.Add($cboFormat)

    # Preview column.
    $preview = [System.Windows.Forms.PictureBox]::new()
    $preview.Location = [System.Drawing.Point]::new(430, 18)
    $preview.Size = [System.Drawing.Size]::new(255, 255)
    $preview.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $preview.BackColor = [System.Drawing.Color]::White
    $preview.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::CenterImage
    $form.Controls.Add($preview)

    $lblInfo = [System.Windows.Forms.Label]::new()
    $lblInfo.Location = [System.Drawing.Point]::new(430, 276)
    $lblInfo.Size = [System.Drawing.Size]::new(255, 18)
    $lblInfo.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($lblInfo)

    $txtPayloadOut = [System.Windows.Forms.TextBox]::new()
    $txtPayloadOut.Location = [System.Drawing.Point]::new(430, 298)
    $txtPayloadOut.Size = [System.Drawing.Size]::new(255, 110)
    $txtPayloadOut.Multiline = $true
    $txtPayloadOut.ReadOnly = $true
    $txtPayloadOut.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $txtPayloadOut.BackColor = [System.Drawing.Color]::White
    $txtPayloadOut.Font = [System.Drawing.Font]::new('Consolas', 8)
    $form.Controls.Add($txtPayloadOut)

    $lblStatus = [System.Windows.Forms.Label]::new()
    $lblStatus.Location = [System.Drawing.Point]::new(15, 492)
    $lblStatus.Size = [System.Drawing.Size]::new(670, 30)
    $lblStatus.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($lblStatus)

    function New-Action {
        param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][int]$Left, [Parameter()][int]$Width = 100)
        $button = [System.Windows.Forms.Button]::new()
        $button.Text = $Text
        $button.Location = [System.Drawing.Point]::new($Left, 452)
        $button.Size = [System.Drawing.Size]::new($Width, 32)
        $form.Controls.Add($button)
        return $button
    }

    # A first run "plays" the code into existence; once generated, the same
    # button means "regenerate", so its icon switches after the first success.
    $btnGenerate = New-Action -Text "$([char]0x25B6)  &Generate" -Left 15 -Width 120
    $btnGenerate.Font = [System.Drawing.Font]::new('Segoe UI Symbol', 9)
    $toolTip.SetToolTip($btnGenerate, 'Generate the QR code from the fields (Enter or Alt+Enter)')
    $btnCopy = New-Action -Text '&Copy image' -Left 145 -Width 105
    $toolTip.SetToolTip($btnCopy, 'Copy the QR code image to the clipboard')
    $btnSave = New-Action -Text 'Save &as...' -Left 258 -Width 100
    $toolTip.SetToolTip($btnSave, 'Save the code as a PNG or SVG file')
    $btnPrint = New-Action -Text '&Print' -Left 366 -Width 74
    $toolTip.SetToolTip($btnPrint, 'Print the code')
    $btnHelp = New-Action -Text '&Help' -Left 546 -Width 64
    $btnClose = New-Action -Text 'C&lose' -Left 618 -Width 67

    $collect = {
        switch ($typeMap[$typeCombo.SelectedIndex]) {
            'Text' { [string]$txtText.Text }
            'Wifi' {
                ConvertTo-QRCodeText -Kind Wifi -Values @{
                    Ssid     = $txtSsid.Text
                    Password = $txtWifiPassword.Text
                    Auth     = $cboAuth.SelectedItem
                    Hidden   = $chkHidden.Checked
                }
            }
            'VCard' {
                ConvertTo-QRCodeText -Kind VCard -Values @{
                    FullName     = $txtFullName.Text
                    Mobile       = $txtMobile.Text
                    Work         = $txtWork.Text
                    Home         = $txtHome.Text
                    Fax          = $txtFax.Text
                    Email        = $txtVCardEmail.Text
                    Organization = $txtOrg.Text
                    JobTitle     = $txtTitle.Text
                    Website      = $txtWebsite.Text
                    Note         = $txtNote.Text
                }
            }
            'Email' {
                ConvertTo-QRCodeText -Kind Email -Values @{
                    To      = $txtEmailTo.Text
                    Subject = $txtSubject.Text
                    Body    = $txtEmailBody.Text
                }
            }
            'Sms' {
                ConvertTo-QRCodeText -Kind Sms -Values @{ Number = $txtSmsNumber.Text; Body = $txtSmsBody.Text }
            }
            'Phone' {
                ConvertTo-QRCodeText -Kind Phone -Values @{ Number = $txtPhoneNumber.Text }
            }
            'Geo' {
                # Accept both 47.6 and 47,6 regardless of the host locale.
                [double]$lat = 0
                [double]$lon = 0
                $null = [double]::TryParse(($txtLatitude.Text -replace ',', '.'), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$lat)
                $null = [double]::TryParse(($txtLongitude.Text -replace ',', '.'), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$lon)
                ConvertTo-QRCodeText -Kind Geo -Values @{ Latitude = $lat; Longitude = $lon }
            }
        }
    }

    function Show-Group {
        param([Parameter(Mandatory)][string]$Kind)
        foreach ($name in $groups.Keys) {
            $visible = $name -eq $Kind
            foreach ($control in $groups[$name]) {
                $control.Visible = $visible
                if ($control -isnot [System.Windows.Forms.Label]) { $control.TabStop = $visible }
            }
        }
    }

    function Clear-Preview {
        if ($preview.Image) {
            $preview.Image.Dispose()
            $preview.Image = $null
        }
        $txtPayloadOut.Text = ''
        $lblInfo.Text = ''
    }

    $render = {
        try {
            $payload = [string](& $collect)
            if ([string]::IsNullOrWhiteSpace($payload)) {
                Clear-Preview
                $lblStatus.Text = 'Enter a value first.'
                $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
                return
            }

            $data = Get-QRCodeData -Text $payload -ECCLevel $eccLevels[$trkEcc.Value]
            $modules = $data.ModuleMatrix.Count
            $pixels = [int][Math]::Max(2, [Math]::Floor(250 / $modules))
            $bitmap = [QRCoder.QRCode]::new($data).GetGraphic($pixels, [System.Drawing.Color]::Black, [System.Drawing.Color]::White, $true)

            Clear-Preview
            $preview.Image = $bitmap
            $txtPayloadOut.Text = $payload
            $lblInfo.Text = "Version $($data.Version) - $modules modules"
            $lblStatus.Text = 'Generated.'
            $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
            $btnGenerate.Text = "$([char]0x21BB)  &Generate"
        }
        catch {
            Clear-Preview
            $lblStatus.Text = $_.Exception.Message
            $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
        }
    }

    # Editing a field invalidates the shown code, so the preview never disagrees
    # with the fields (and Copy/Print can't send a stale image).
    $invalidate = {
        Clear-Preview
        $lblStatus.Text = 'Fields changed - click Generate.'
        $lblStatus.ForeColor = [System.Drawing.Color]::DimGray
    }

    foreach ($name in $groups.Keys) {
        foreach ($control in $groups[$name]) {
            if ($control -is [System.Windows.Forms.TextBox]) { $control.Add_TextChanged($invalidate) }
        }
    }
    $cboAuth.Add_SelectedIndexChanged($invalidate)
    $chkHidden.Add_CheckedChanged($invalidate)
    $trkEcc.Add_ValueChanged({
        $lblEccValue.Text = $eccLevels[$trkEcc.Value]
        & $invalidate
    })

    $typeCombo.Add_SelectedIndexChanged({
        Show-Group -Kind $typeMap[$typeCombo.SelectedIndex]
        Update-TypeIcons
        & $invalidate
    })

    $btnGenerate.Add_Click({ & $render })

    # Enter reaches Generate through AcceptButton; Alt+Enter is not an accept key,
    # so catch it explicitly. KeyPreview lets the form see it before a focused
    # multiline box (whose AcceptsReturn would otherwise swallow it).
    $form.KeyPreview = $true
    $form.Add_KeyDown({
        param($sender, $e)
        if ($e.Alt -and ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter)) {
            $e.SuppressKeyPress = $true
            & $render
        }
    })

    $btnCopy.Add_Click({
        if (-not $preview.Image) {
            $lblStatus.Text = 'Generate a code first.'
            $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
            return
        }
        try {
            [System.Windows.Forms.Clipboard]::SetImage($preview.Image)
            $lblStatus.Text = 'Image copied to the clipboard.'
            $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        catch {
            $lblStatus.Text = "Copy failed: $($_.Exception.Message)"
            $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
        }
    })

    $btnSave.Add_Click({
        $payload = [string](& $collect)
        if ([string]::IsNullOrWhiteSpace($payload)) {
            $lblStatus.Text = 'Nothing to save yet.'
            $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
            return
        }

        $format = [string]$cboFormat.SelectedItem
        $extension = if ($format -eq 'SVG') { 'svg' } else { 'png' }
        $dialog = [System.Windows.Forms.SaveFileDialog]::new()
        $dialog.Filter = if ($format -eq 'SVG') { 'SVG image (*.svg)|*.svg' } else { 'PNG image (*.png)|*.png' }
        $dialog.FileName = 'qrcode.' + $extension

        try {
            if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
                New-QRCode -Text $payload -Path $dialog.FileName -Format $format -ECCLevel $eccLevels[$trkEcc.Value] -PixelsPerModule ([int]$numSize.Value) | Out-Null
                $lblStatus.Text = "Saved $($dialog.FileName)"
                $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
            }
        }
        catch {
            $lblStatus.Text = "Save failed: $($_.Exception.Message)"
            $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
        }
        finally {
            $dialog.Dispose()
        }
    })

    $btnPrint.Add_Click({
        if (-not $preview.Image) {
            $lblStatus.Text = 'Generate a code first.'
            $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
            return
        }

        $document = [System.Drawing.Printing.PrintDocument]::new()
        $document.DocumentName = 'QR Code'
        $document.add_PrintPage({
            param($sender, $e)
            $image = $preview.Image
            $bounds = $e.MarginBounds
            $scale = [Math]::Min(($bounds.Width / $image.Width), ($bounds.Height / $image.Height))
            $width = [int]($image.Width * $scale)
            $height = [int]($image.Height * $scale)
            $x = $bounds.Left + [int](($bounds.Width - $width) / 2)
            $y = $bounds.Top + [int](($bounds.Height - $height) / 2)
            $e.Graphics.DrawImage($image, $x, $y, $width, $height)
        })

        $dialog = [System.Windows.Forms.PrintDialog]::new()
        $dialog.Document = $document
        try {
            if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
                $document.Print()
            }
        }
        catch {
            $lblStatus.Text = "Print failed: $($_.Exception.Message)"
            $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
        }
        finally {
            $dialog.Dispose()
            $document.Dispose()
        }
    })

    $btnClose.Add_Click({ $form.Close() })

    $helpGuide = @'
QR CODE GENERATOR - QUICK GUIDE

WHAT THIS DOES
  Builds a QR code from text or a preset payload. Pick a type, fill in the
  fields, then click Generate. From there you can copy the image, save a
  PNG/SVG, or print it. The generated code is standard: phone cameras and
  scanner apps open the link, join the Wi-Fi network, add the contact, and
  so on. The icon strip below the type box is a shortcut: click an icon to
  switch type.

TYPES
  Text / URL     Any text. With a scheme (https://, mailto:, tel:) the camera
                 offers to open it in the matching app.
  Wi-Fi network  Encodes SSID, password and security so phones can join without
                 typing. Use "nopass" for an open network.
  Contact        A vCard the camera can save to contacts. Enter numbers under
                 Mobile, Work, Home or Fax so they import with the right label.
  Email          Opens a pre-filled message. Subject and body are optional.
  SMS            Opens a text message to the number, optionally pre-filled.
  Phone call     Dials the number.
  Location       Opens the coordinates in a maps app.

OPTIONS
  Error level    Slider L/M/Q/H - higher survives more damage but makes the
                 code denser. Q is a good default; use H if it will be printed
                 small or partly covered.
  Size           Pixels per module in the saved file (not the on-screen preview).
  Format         PNG for photos and documents, SVG for print/vector.

BUTTONS
  Generate       Builds the code from the current fields. Editing a field
                 clears the preview until you generate again.
  Copy image     Puts the bitmap on the clipboard (paste into chat, docs, ...).
  Save as...     Writes a PNG or SVG file.
  Print          Sends the image to a printer.

KEYBOARD
  Enter / Alt+Enter             Generate.
  Alt+G  Alt+C  Alt+A  Alt+P    Generate, Copy, Save as, Print.
  Alt+H  Alt+L                  Help, Close.
  Alt+T  Alt+E  Alt+S  Alt+F    Type, Error level, Size, Format.
  Every field has its own shortcut too: press Alt plus the underlined letter in
  its label (for example Alt+I for SSID, Alt+N for Phone).

NOTES
  Quotation marks are not required; they become part of the value. Scan the
  result once before publishing it, since verification is only as good as the
  encoded value.
'@

    $btnHelp.Add_Click({
        $helpForm = [System.Windows.Forms.Form]::new()
        $helpForm.Text = 'QR Code help'
        $helpForm.ClientSize = [System.Drawing.Size]::new(620, 540)
        $helpForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
        $helpForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $helpForm.MaximizeBox = $false
        $helpForm.MinimizeBox = $false
        $helpForm.Font = [System.Drawing.Font]::new('Segoe UI', 9)

        $helpText = [System.Windows.Forms.RichTextBox]::new()
        $helpText.Location = [System.Drawing.Point]::new(15, 15)
        $helpText.Size = [System.Drawing.Size]::new(590, 470)
        $helpText.ReadOnly = $true
        $helpText.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
        $helpText.WordWrap = $true
        $helpText.DetectUrls = $false
        $helpText.BackColor = [System.Drawing.Color]::White
        $helpText.Font = [System.Drawing.Font]::new('Consolas', 9)

        # A here-string carries LF-only line endings; the native edit control only
        # breaks on CRLF, so normalize before assigning or the guide renders as one
        # paragraph.
        $newLine = [Environment]::NewLine
        $helpLines = $helpGuide -split "`r?`n"
        $helpText.Text = ($helpLines -join $newLine)

        $headingFont = [System.Drawing.Font]::new('Consolas', 9, [System.Drawing.FontStyle]::Bold)
        $headingColor = [System.Drawing.Color]::FromArgb(31, 78, 120)
        $offset = 0
        foreach ($line in $helpLines) {
            if ($line -match '^[A-Z][A-Z0-9 /-]{2,}$') {
                $helpText.Select($offset, $line.Length)
                $helpText.SelectionFont = $headingFont
                $helpText.SelectionColor = $headingColor
            }
            elseif ($line -match '^  [A-Z][A-Za-z ()]+$') {
                $helpText.Select($offset, $line.Length)
                $helpText.SelectionFont = $headingFont
            }
            $offset += $line.Length + $newLine.Length
        }
        $helpText.Select(0, 0)

        $btnHelpClose = [System.Windows.Forms.Button]::new()
        $btnHelpClose.Text = 'Close'
        $btnHelpClose.Location = [System.Drawing.Point]::new(515, 497)
        $btnHelpClose.Size = [System.Drawing.Size]::new(90, 28)

        $helpForm.Controls.Add($helpText)
        $helpForm.Controls.Add($btnHelpClose)
        $helpForm.AcceptButton = $btnHelpClose
        $helpForm.CancelButton = $btnHelpClose
        $btnHelpClose.Add_Click({ $helpForm.Close() })

        try {
            $null = $helpForm.ShowDialog($form)
        }
        finally {
            $helpForm.Dispose()
        }
    })

    $form.AcceptButton = $btnGenerate
    $form.CancelButton = $btnClose
    $form.Add_Shown({
        Show-Group -Kind $typeMap[$typeCombo.SelectedIndex]
        Update-TypeIcons
        $lblStatus.Text = 'Fill in the fields and click Generate.'
        $txtText.Focus() | Out-Null
    })

    try {
        $null = $form.ShowDialog()
    }
    finally {
        if ($preview.Image) { $preview.Image.Dispose() }
        $form.Dispose()
    }
}
