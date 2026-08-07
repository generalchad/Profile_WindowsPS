function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped, color-coded log line to the host.

    .DESCRIPTION
        Internal helper used by Optimize-VMX to produce consistent status output.
        Not exported from the module.

    .PARAMETER Level
        The severity/category of the message (e.g. INFO, WARN, ERR, ACTION, OK).

    .PARAMETER Message
        The primary message text.

    .PARAMETER Detail
        Optional secondary detail appended after the message.
    #>
    param(
        [string]$Level,
        [string]$Message,
        [string]$Detail = ""
    )

    $colors = @{ "INFO"="Gray"; "WARN"="Yellow"; "ERR"="Red"; "ACTION"="Cyan"; "OK"="DarkGray" }
    Write-Host ("$(Get-Date -Format 'HH:mm:ss') [$($Level.PadRight(4).Substring(0,4))] ") -NoNewline -ForegroundColor $colors[$Level]
    Write-Host $Message -NoNewline -ForegroundColor $colors[$Level]
    if ($Detail) { Write-Host " : $Detail" -ForegroundColor DarkGray } else { Write-Host "" }
}
