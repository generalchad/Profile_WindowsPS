function Show-ScanShare {
    <#
    .SYNOPSIS
        Opens a small Windows Forms dialog that runs New-ScanShare.

    .DESCRIPTION
        Collects the scan-to-folder settings (destination, share name, account,
        password, optional remote address and switches) and drives New-ScanShare
        from a graphical form:

          * Preview runs the dry run (New-ScanShare -WhatIf) and shows the planned
            steps. It works without elevation.
          * Create performs the real setup. It requires elevation; when the session
            is not elevated the dialog offers to relaunch as administrator.

        The dialog is a convenience wrapper: New-ScanShare stays the supported
        command-line entry point and the headless path. Verification results are
        rendered from the object New-ScanShare returns, and the exact values to enter
        on the copier can be copied to the clipboard in one click.

        Each field carries an inline hint, and the destination folder has a Browse
        button that opens a directory picker. Quotation marks are not required in any
        field; they would become part of the value. A Help button opens a short,
        scrollable guide covering the fields, the options, and the values to enter on
        the copier.

        Windows Forms is loaded only when the dialog opens, so importing the module
        stays fast and headless sessions are unaffected.

    .EXAMPLE
        Show-ScanShare

        Opens the setup dialog with the same defaults as New-ScanShare.

    .OUTPUTS
        None. Results are shown in the dialog; use New-ScanShare for scripted output.

    .NOTES
        Runs on PowerShell 7 and Windows PowerShell 5.1 (Windows only). Requires an
        interactive desktop; use New-ScanShare directly for scripted or headless use.
        Creating the account, share and firewall rules needs an elevated session.
    #>
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    [System.Windows.Forms.Application]::EnableVisualStyles()

    # Hover hints. WinForms has no per-control "hint" property; a shared ToolTip is
    # the supported mechanism, and it is the only guidance available for the
    # checkboxes, whose purpose is not obvious from the label alone.
    $toolTip = [System.Windows.Forms.ToolTip]::new()
    $toolTip.AutoPopDelay = 30000
    $toolTip.InitialDelay = 400
    $toolTip.ReshowDelay = 100
    $toolTip.ShowAlways = $true

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'New Scan Share'
    $form.ClientSize = [System.Drawing.Size]::new(660, 706)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Font = [System.Drawing.Font]::new('Segoe UI', 9)

    function New-InfoButton {
        param(
            [Parameter(Mandatory)][string]$Text,
            [Parameter(Mandatory)][string]$Title,
            [Parameter(Mandatory)][int]$Left,
            [Parameter(Mandatory)][int]$Top
        )

        $button = [System.Windows.Forms.Button]::new()
        $button.Text = [char]0x2139
        $button.Font = [System.Drawing.Font]::new('Segoe UI Symbol', 9)
        $button.Location = [System.Drawing.Point]::new($Left, $Top)
        $button.Size = [System.Drawing.Size]::new(24, 24)
        $button.TabStop = $false
        $button.Tag = [pscustomobject]@{ Title = $Title; Detail = $Text }
        $form.Controls.Add($button)
        $toolTip.SetToolTip($button, 'Show detailed help')
        $button.Add_Click({
            param($sender, $e)
            [System.Windows.Forms.MessageBox]::Show($sender.Tag.Detail, $sender.Tag.Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        })

        return $button
    }

    function New-LabeledInput {
        param(
            [Parameter(Mandatory)][string]$Label,
            [Parameter(Mandatory)][int]$Top,
            [Parameter()][int]$Width = 448,
            [Parameter()][switch]$Password,
            [Parameter()][string]$Hint,
            [Parameter()][string]$Info,
            [Parameter()][int]$InfoLeft = 608
        )

        $caption = [System.Windows.Forms.Label]::new()
        $caption.Text = $Label
        $caption.Location = [System.Drawing.Point]::new(15, ($Top + 3))
        $caption.Size = [System.Drawing.Size]::new(130, 20)
        $caption.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
        $form.Controls.Add($caption)

        $box = [System.Windows.Forms.TextBox]::new()
        $box.Location = [System.Drawing.Point]::new(152, $Top)
        $box.Size = [System.Drawing.Size]::new($Width, 23)
        if ($Password) { $box.UseSystemPasswordChar = $true }
        if ($Hint) { $toolTip.SetToolTip($box, $Hint) }
        $form.Controls.Add($box)

        if ($Info) { $null = New-InfoButton -Text $Info -Title $Label -Left $InfoLeft -Top $Top }

        return $box
    }

    function New-Option {
        param(
            [Parameter(Mandatory)][string]$Text,
            [Parameter(Mandatory)][int]$Top,
            [Parameter()][int]$Width = 448,
            [Parameter()][string]$Hint,
            [Parameter()][string]$Info,
            [Parameter()][int]$InfoLeft = 608
        )

        $check = [System.Windows.Forms.CheckBox]::new()
        $check.Text = $Text
        $check.Location = [System.Drawing.Point]::new(152, $Top)
        $check.Size = [System.Drawing.Size]::new($Width, 22)
        if ($Hint) { $toolTip.SetToolTip($check, $Hint) }
        $form.Controls.Add($check)

        if ($Info) { $null = New-InfoButton -Text $Info -Title $Text -Left $InfoLeft -Top $Top }

        return $check
    }

    function New-Hint {
        param(
            [Parameter(Mandatory)][string]$Text,
            [Parameter(Mandatory)][int]$Top,
            [Parameter()][int]$Width = 495,
            [Parameter()][int]$Height = 18
        )

        $hint = [System.Windows.Forms.Label]::new()
        $hint.Text = $Text
        $hint.Location = [System.Drawing.Point]::new(152, $Top)
        $hint.Size = [System.Drawing.Size]::new($Width, $Height)
        $hint.ForeColor = [System.Drawing.Color]::DimGray
        $form.Controls.Add($hint)

        return $hint
    }

    function New-Action {
        param(
            [Parameter(Mandatory)][string]$Text,
            [Parameter(Mandatory)][int]$Left,
            [Parameter()][int]$Width = 90
        )

        $button = [System.Windows.Forms.Button]::new()
        $button.Text = $Text
        $button.Location = [System.Drawing.Point]::new($Left, 374)
        $button.Size = [System.Drawing.Size]::new($Width, 28)
        $form.Controls.Add($button)

        return $button
    }

    $txtPath = New-LabeledInput -Label '&Destination folder' -Top 18 -Width 352 `
        -Hint 'Folder that receives scans' `
        -Info 'Full path that receives scans, e.g. C:\Scans. Created if it does not exist. It must be a dedicated subfolder, not a drive root such as C:\. Use Browse to pick an existing folder.'
    $txtPath.Text = 'C:\Scans'

    $btnBrowse = [System.Windows.Forms.Button]::new()
    $btnBrowse.Text = '&Browse...'
    $btnBrowse.Location = [System.Drawing.Point]::new(510, 16)
    $btnBrowse.Size = [System.Drawing.Size]::new(90, 25)
    $form.Controls.Add($btnBrowse)
    $toolTip.SetToolTip($btnBrowse, 'Pick a folder')

    $btnBrowse.Add_Click({
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description = 'Select the scan destination folder'
        $dialog.ShowNewFolderButton = $true
        if (Test-Path -LiteralPath $txtPath.Text -PathType Container -ErrorAction SilentlyContinue) {
            $dialog.SelectedPath = $txtPath.Text
        }
        try {
            if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
                $txtPath.Text = $dialog.SelectedPath
            }
        }
        finally {
            $dialog.Dispose()
        }
    })

    $null = New-Hint -Top 44 -Text 'Full path (e.g. C:\Scans). Created if missing. Browse to pick a folder.'

    $txtShare = New-LabeledInput -Label '&Share name' -Top 72 `
        -Hint 'Name the copier connects to' `
        -Info 'Name the copier connects to (default "Scans"). Up to 80 characters; avoid \ / : * ? " < > | [ ] ; = + ,'
    $txtShare.Text = 'Scans'
    $txtUser = New-LabeledInput -Label '&User name' -Top 104 `
        -Hint 'Account the copier signs in as' `
        -Info 'Local account the copier signs in as (default "scanner"). Up to 20 characters; avoid \ / " [ ] : | < > + = ; , ? * @'
    $txtUser.Text = 'scanner'
    $txtPassword = New-LabeledInput -Label '&Password' -Top 136 -Width 300 -Password `
        -Hint 'Password for that account' `
        -Info 'Password for that account. Required for a new or reset account: Windows blocks network (SMB) logons for accounts with blank passwords.'

    $null = New-Hint -Top 164 -Height 34 -Text "Share name: max 80 chars. User name: max 20 chars. Password: max 128 chars.`nAvoid \ / : * ? `" < > | [ ] ; = + , @"

    $txtRemote = New-LabeledInput -Label '&Remote address' -Top 202 `
        -Hint 'Allowed source IP range' `
        -Info 'Optional. Source IP range allowed to reach SMB port 445. Blank = LocalSubnet; use a subnet such as 10.20.0.0/16 if the copier is on another VLAN, or Any to allow every network.'

    $null = New-Hint -Top 226 -Height 32 -Text 'Optional. Source IP range allowed to scan. Blank = LocalSubnet; e.g. 10.20.0.0/16 or Any.'

    $chkReset = New-Option -Text 'R&eset password of an existing account' -Top 264 `
        -Hint 'Set a new password on an existing account' `
        -Info 'Sets a new password on an account that already exists. Leave this clear to reuse the account and its current password.'
    $chkSkipHardening = New-Option -Text 'S&kip account hardening (-SkipAccountHardening)' -Top 290 `
        -Hint 'Leave logon rights untouched (GPO)' `
        -Info 'Leaves logon rights untouched. Use only when user-rights assignments are managed by Group Policy. Without this, the scan account is denied interactive, Remote Desktop, batch and service logon, and a reused account in a privileged group stops the setup.'
    $chkSkipFw = New-Option -Text 'Skip &firewall changes (-SkipFirewall)' -Top 316 `
        -Hint 'Leave Windows Firewall untouched (GPO)' `
        -Info 'Leaves Windows Firewall untouched. Use when the SMB inbound rules are managed by Group Policy.'
    $chkSkipVerify = New-Option -Text 'Sk&ip verification probes (-SkipVerification)' -Top 342 `
        -Hint 'Skip the listener and write/delete probes' `
        -Info 'Skips the SMB listener test and the credentialed write/delete test. Use when setup must not open a network connection or touch the share.'

    $btnPreview = New-Action -Text 'Pre&view' -Left 152
    $toolTip.SetToolTip($btnPreview, 'Preview planned changes')
    $btnCreate = New-Action -Text '&Create' -Left 248
    $toolTip.SetToolTip($btnCreate, 'Apply the setup (needs admin)')
    $btnCopy = New-Action -Text 'Cop&y settings' -Left 344 -Width 110
    $btnCopy.Enabled = $false
    $toolTip.SetToolTip($btnCopy, 'Copy copier settings')
    $btnHelp = New-Action -Text "$([char]0x2139)  &Help" -Left 462 -Width 80
    $btnHelp.Font = [System.Drawing.Font]::new('Segoe UI Symbol', 9)
    $toolTip.SetToolTip($btnHelp, 'Open the setup guide')
    $btnClose = New-Action -Text 'C&lose' -Left 552
    $toolTip.SetToolTip($btnClose, 'Close the dialog')

    $lblStatus = [System.Windows.Forms.Label]::new()
    $lblStatus.Location = [System.Drawing.Point]::new(15, 410)
    $lblStatus.Size = [System.Drawing.Size]::new(630, 20)

    $txtResults = [System.Windows.Forms.TextBox]::new()
    $txtResults.Location = [System.Drawing.Point]::new(15, 436)
    $txtResults.Size = [System.Drawing.Size]::new(630, 250)
    $txtResults.Multiline = $true
    $txtResults.ReadOnly = $true
    $txtResults.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $txtResults.WordWrap = $false
    $txtResults.Font = [System.Drawing.Font]::new('Consolas', 9)
    $txtResults.BackColor = [System.Drawing.Color]::White
    $txtResults.Text = "Choose Options and click Preview to see the plan, or Create to apply it."

    $form.Controls.Add($lblStatus)
    $form.Controls.Add($txtResults)

    if (Test-Elevation) {
        $lblStatus.Text = 'Elevated session.'
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    }
    else {
        $lblStatus.Text = 'Not elevated. Preview works; Create will offer to relaunch as administrator.'
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    }

    $collectSplat = {
        Get-ScanShareGuiSplat -Path $txtPath.Text -ShareName $txtShare.Text -UserName $txtUser.Text `
            -Password $txtPassword.Text -RemoteAddress $txtRemote.Text `
            -ResetPassword:$chkReset.Checked -SkipAccountHardening:$chkSkipHardening.Checked `
            -SkipFirewall:$chkSkipFw.Checked -SkipVerification:$chkSkipVerify.Checked
    }

    $btnPreview.Add_Click({
        $form.UseWaitCursor = $true
        $txtResults.Text = 'Running preview...'
        $form.Refresh()
        try {
            $splat = & $collectSplat
            $result = New-ScanShare @splat -WhatIf
            $render = Format-ScanShareResult -Result $result -DryRun -ShareName $txtShare.Text.Trim() -UserName $txtUser.Text.Trim()
            $txtResults.Text = $render.Text
            $txtResults.Tag = $render.Summary
            $btnCopy.Enabled = [bool]$render.Summary
            $lblStatus.Text = 'Preview complete - no changes were made.'
            $lblStatus.ForeColor = [System.Drawing.Color]::DimGray
        }
        catch {
            $txtResults.Text = "Error: $($_.Exception.Message)"
            $lblStatus.Text = 'Preview failed.'
            $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
        }
        finally {
            $form.UseWaitCursor = $false
        }
    })

    $createAction = {
        $userName = $txtUser.Text.Trim()
        $existingUser = $null
        try { $existingUser = Get-LocalUser -Name $userName -ErrorAction SilentlyContinue } catch { $existingUser = $null }

        # New-ScanShare prompts via Read-Host for a missing or reset account; the GUI
        # must collect the password itself so no console prompt can block the dialog.
        if ([string]::IsNullOrEmpty($txtPassword.Text) -and ($null -eq $existingUser -or $chkReset.Checked)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Enter a password. A new or reset local account cannot use a blank password over SMB.',
                'Password required',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        if (-not (Test-Elevation)) {
            $answer = [System.Windows.Forms.MessageBox]::Show(
                "Creating the account, share and firewall rules requires an elevated session.`n`nRelaunch as administrator now?",
                'Administrator required',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                $exe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
                try {
                    # The elevated child is a new process that must re-autoload this
                    # module; without Bypass a Restricted client (the Windows default
                    # under Windows PowerShell 5.1) blocks that import.
                    Start-Process -FilePath $exe -Verb RunAs -ArgumentList '-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', 'Show-ScanShare' -ErrorAction Stop
                    $form.Close()
                }
                catch {
                    [System.Windows.Forms.MessageBox]::Show("Could not relaunch: $($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
                }
            }
            return
        }

        $btnPreview.Enabled = $false
        $btnCreate.Enabled = $false
        $btnCopy.Enabled = $false
        $form.UseWaitCursor = $true
        $txtResults.Text = 'Applying changes...'
        $form.Refresh()
        try {
            $splat = & $collectSplat
            $result = New-ScanShare @splat -Confirm:$false
            $render = Format-ScanShareResult -Result $result -ShareName $txtShare.Text.Trim() -UserName $txtUser.Text.Trim()
            $txtResults.Text = $render.Text
            $txtResults.Tag = $render.Summary
            $btnCopy.Enabled = [bool]$render.Summary
            $lblStatus.Text = if ($render.Summary) { 'Setup complete.' } else { 'Finished with issues - review the results.' }
            $lblStatus.ForeColor = if ($render.Summary) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkGoldenrod }
        }
        catch {
            $txtResults.Text = "Error: $($_.Exception.Message)"
            $lblStatus.Text = 'Setup failed.'
            $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
        }
        finally {
            $form.UseWaitCursor = $false
            $btnPreview.Enabled = $true
            $btnCreate.Enabled = $true
        }
    }
    $btnCreate.Add_Click($createAction)

    $btnCopy.Add_Click({
        $summary = [string]$txtResults.Tag
        if ([string]::IsNullOrEmpty($summary)) { return }
        Set-Clipboard -Value $summary
        $lblStatus.Text = 'Copier settings copied to clipboard.'
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    })

    $btnClose.Add_Click({ $form.Close() })

    # Alt+Enter fires the primary action (Create), matching the AcceptButton.
    # KeyPreview lets the form see the key before a focused control handles it.
    $form.KeyPreview = $true
    $form.Add_KeyDown({
        param($sender, $e)
        if ($e.Alt -and ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter)) {
            $e.SuppressKeyPress = $true
            & $createAction
        }
    })

    $helpGuide = @'
SCAN-TO-FOLDER SETUP - QUICK GUIDE

WHAT THIS DOES
  Creates everything an office copier needs to scan to a folder on this PC:
  a local account for the copier, the destination folder, locked-down NTFS
  permissions, an SMB share, and the firewall rules that allow the scan.
  The account is hardened so it works only over SMB: interactive, Remote
  Desktop, batch and service logons are denied, so a leaked password cannot
  be used to sign in at the console or run a service. Every step is safe to
  re-run: existing pieces are reused, not duplicated.

HOW TO USE THIS DIALOG
  1. Fill in the fields (the defaults work for a first setup). Hover a control
     for a one-line hint, or click the small i button beside it for details.
  2. Click Preview to see exactly what would happen. Preview makes no changes
     and works without administrator rights.
  3. Click Create to apply it. This needs elevation; if the session is not
     elevated the dialog offers to relaunch as administrator.
  4. On success, click Copy settings, then enter those values on the copier.

FIELDS
  Destination folder
      Full path to receive scans, e.g. C:\Scans. Created if it does not exist.
      It must not be a drive root (C:\). Use Browse to pick a folder.

  Share name
      Name the copier connects to (default "Scans"). Up to 80 characters;
      avoid \ / : * ? " < > | [ ] ; = + ,

  User name
      Local account the copier signs in as (default "scanner"). Up to 20
      characters; avoid \ / " [ ] : | < > + = ; , ? * @

  Password
      Password for that account. Required for a new or reset account: Windows
      blocks network (SMB) logins for accounts with blank passwords.

  Remote address (optional)
      Source IP range allowed to reach this PC on SMB port 445. Leave blank
      for LocalSubnet. Use a subnet such as 10.20.0.0/16 if the copier is on
      another VLAN, or Any to allow every network.

  Quotation marks are not required in any field - they become part of the value.

OPTIONS
  Reset password of an existing account
      Sets a new password on an account that already exists.
  Skip account hardening
      Leaves logon rights untouched (use when user rights are managed by
      Group Policy). Without this, the scan account is denied interactive,
      Remote Desktop, batch and service logon, and a reused account already
      in a privileged group (Administrators, Backup Operators, ...) stops
      the setup before the share is created.
  Skip firewall changes
      Leaves Windows Firewall untouched (use when rules are managed by
      Group Policy).
  Skip verification probes
      Skips the SMB listener test and the credentialed write/delete test.

KEYBOARD
  Alt+Enter            Create (same as the Create button).
  Alt+D  Alt+S  Alt+U  Alt+P  Alt+R
                       Destination folder, Share name, User name, Password,
                       Remote address.
  Alt+B  Alt+V  Alt+C  Alt+Y  Alt+H  Alt+L
                       Browse, Preview, Create, Copy settings, Help, Close.
  Alt+E  Alt+K  Alt+F  Alt+I
                       Reset password, Skip account hardening, Skip firewall,
                       Skip verification.

ON THE COPIER
  Host / server : this PC name, or its IP address
  Share / path  : the Share name above
  Full path     : \\<PC name>\<share>  (Copy settings puts these on the clipboard)
  User name     : the account name; some models need <PC name>\<account>
  Protocol      : SMB, port 445

IF SOMETHING FAILS
  - "Access" step fails with error 1219: Windows already has conflicting
    credentials cached for this server. Disconnect existing sessions
    (net use * /delete) or reboot, then retry.
  - "Listener" step fails: the SMB server may be stopped. Check the "Server"
    service (LanmanServer) and that port 445 is listening.
  - Scans are refused on the network: an active network profile is "Public".
    In an elevated PowerShell run:
        Set-NetConnectionProfile -NetworkCategory Private
  - Account or password login errors on the copier: confirm the account is
    enabled and the password matches; re-run with "Reset password" checked.
  - "Hardening" step fails because the account is in a privileged group: the
    account is not safe to use as a scanner login. Choose a dedicated user
    name, or tick "Skip account hardening" if user rights are GPO-managed.

Verification uses Test-FileShare when it is available; without it the
Listener step is skipped automatically.
'@

    $btnHelp.Add_Click({
        $helpForm = [System.Windows.Forms.Form]::new()
        $helpForm.Text = 'Scan Share help'
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

    $form.AcceptButton = $btnCreate
    $form.CancelButton = $btnClose
    $form.Add_Shown({ $txtPath.Focus() | Out-Null })

    try {
        $null = $form.ShowDialog()
    }
    finally {
        $form.Dispose()
    }
}
