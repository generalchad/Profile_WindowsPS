function Format-OpsxSize {
    <#
    .SYNOPSIS
        Renders a byte count as a human readable string.
    .DESCRIPTION
        Uses binary units (1 KB = 1024 bytes) so reported figures match what
        Windows Explorer and disc imaging tools display.

        Negative values keep their sign rather than being shown as an absolute
        value, so a CHD set that grew larger than its source is stated plainly.
    .PARAMETER Bytes
        Size in bytes.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [double]$Bytes
    )

    process {
        $sign = if ($Bytes -lt 0) { '-' } else { '' }
        $abs = [Math]::Abs($Bytes)

        if ($abs -ge 1TB) { return '{0}{1:N2} TB' -f $sign, ($abs / 1TB) }
        if ($abs -ge 1GB) { return '{0}{1:N2} GB' -f $sign, ($abs / 1GB) }
        if ($abs -ge 1MB) { return '{0}{1:N2} MB' -f $sign, ($abs / 1MB) }
        if ($abs -ge 1KB) { return '{0}{1:N2} KB' -f $sign, ($abs / 1KB) }
        return '{0}{1:N0} B' -f $sign, $abs
    }
}
