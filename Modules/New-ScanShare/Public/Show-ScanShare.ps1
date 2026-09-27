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

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'New Scan Share'
    $form.ClientSize = [System.Drawing.Size]::new(660, 650)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Font = [System.Drawing.Font]::new('Segoe UI', 9)

    function New-LabeledInput {
        param(
            [Parameter(Mandatory)][string]$Label,
            [Parameter(Mandatory)][int]$Top,
            [Parameter()][int]$Width = 495,
            [Parameter()][switch]$Password
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
        $form.Controls.Add($box)

        return $box
    }

    function New-Option {
        param(
            [Parameter(Mandatory)][string]$Text,
            [Parameter(Mandatory)][int]$Top
        )

        $check = [System.Windows.Forms.CheckBox]::new()
        $check.Text = $Text
        $check.Location = [System.Drawing.Point]::new(152, $Top)
        $check.Size = [System.Drawing.Size]::new(440, 22)
        $form.Controls.Add($check)

        return $check
    }

    function New-Action {
        param(
            [Parameter(Mandatory)][string]$Text,
            [Parameter(Mandatory)][int]$Left,
            [Parameter()][int]$Width = 90
        )

        $button = [System.Windows.Forms.Button]::new()
        $button.Text = $Text
        $button.Location = [System.Drawing.Point]::new($Left, 286)
        $button.Size = [System.Drawing.Size]::new($Width, 28)
        $form.Controls.Add($button)

        return $button
    }

    $txtPath = New-LabeledInput -Label 'Destination folder' -Top 18
    $txtPath.Text = 'C:\Scans'
    $txtShare = New-LabeledInput -Label 'Share name' -Top 50
    $txtShare.Text = 'Scans'
    $txtUser = New-LabeledInput -Label 'User name' -Top 82
    $txtUser.Text = 'scanner'
    $txtPassword = New-LabeledInput -Label 'Password' -Top 114 -Width 300 -Password
    $txtRemote = New-LabeledInput -Label 'Remote address' -Top 146

    $lblRemoteHint = [System.Windows.Forms.Label]::new()
    $lblRemoteHint.Text = "Blank = LocalSubnet. Comma-separate ranges (e.g. 10.20.0.0/16) or 'Any'."
    $lblRemoteHint.Location = [System.Drawing.Point]::new(152, 170)
    $lblRemoteHint.Size = [System.Drawing.Size]::new(495, 18)
    $lblRemoteHint.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($lblRemoteHint)

    $chkReset = New-Option -Text 'Reset password of an existing account' -Top 198
    $chkSkipFw = New-Option -Text 'Skip firewall changes (-SkipFirewall)' -Top 224
    $chkSkipVerify = New-Option -Text 'Skip verification probes (-SkipVerification)' -Top 250

    $btnPreview = New-Action -Text 'Preview' -Left 152
    $btnCreate = New-Action -Text 'Create' -Left 248
    $btnCopy = New-Action -Text 'Copy settings' -Left 344 -Width 110
    $btnCopy.Enabled = $false
    $btnClose = New-Action -Text 'Close' -Left 552

    $lblStatus = [System.Windows.Forms.Label]::new()
    $lblStatus.Location = [System.Drawing.Point]::new(15, 324)
    $lblStatus.Size = [System.Drawing.Size]::new(630, 20)

    $txtResults = [System.Windows.Forms.TextBox]::new()
    $txtResults.Location = [System.Drawing.Point]::new(15, 350)
    $txtResults.Size = [System.Drawing.Size]::new(630, 285)
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
            -ResetPassword:$chkReset.Checked -SkipFirewall:$chkSkipFw.Checked -SkipVerification:$chkSkipVerify.Checked
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

    $btnCreate.Add_Click({
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
                    Start-Process -FilePath $exe -Verb RunAs -ArgumentList '-NoExit', '-Command', 'Show-ScanShare' -ErrorAction Stop
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
    })

    $btnCopy.Add_Click({
        $summary = [string]$txtResults.Tag
        if ([string]::IsNullOrEmpty($summary)) { return }
        Set-Clipboard -Value $summary
        $lblStatus.Text = 'Copier settings copied to clipboard.'
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    })

    $btnClose.Add_Click({ $form.Close() })

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
