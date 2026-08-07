function Set-VMXSetting {
    <#
    .SYNOPSIS
        Sets or appends a key/value pair within an in-memory VMX content array.

    .DESCRIPTION
        Internal helper used by Optimize-VMX. Scans the supplied array of VMX file
        lines for the given key and replaces its value; if the key is not present,
        it is appended as a new line. Not exported from the module.

    .PARAMETER ContentLines
        The array of lines representing the current VMX file content.

    .PARAMETER Key
        The VMX setting key to set (e.g. "tools.syncTime").

    .PARAMETER Value
        The value to assign to the key.
    #>
    param(
        $ContentLines,
        $Key,
        $Value
    )

    $escapedKey = [regex]::Escape($Key)
    $found = $false
    $newLines = @()

    foreach ($line in $ContentLines) {
        # Matches exact key regardless of whitespace padding around the equals sign
        if ($line -match "^\s*$escapedKey\s*=") {
            $newLines += "$Key = `"$Value`""
            $found = $true
        } else {
            $newLines += $line
        }
    }

    if (-not $found) { $newLines += "$Key = `"$Value`"" }
    return ,$newLines
}
