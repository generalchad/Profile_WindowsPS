function Get-VideoDuration {
    <#
    .SYNOPSIS
        Returns the duration (in seconds) of a media file using ffprobe.

    .DESCRIPTION
        Internal helper. Not exported. Returns $null if ffprobe cannot
        determine a duration (e.g. corrupt/incomplete file).
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    process {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }

        try {
            $raw = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -- "$Path" 2>$null
            $value = ($raw | Select-Object -First 1)
            if ($value -and [double]::TryParse($value, [ref]([double]0))) {
                return [double]$value
            }
            return $null
        } catch {
            return $null
        }
    }
}
