function Test-FFTools {
    <#
    .SYNOPSIS
        Verifies that both ffmpeg and ffprobe are available on the PATH.

    .DESCRIPTION
        Internal helper. Not exported from the module. ffprobe is required
        for resume/skip detection, so both tools are validated together.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    process {
        $ok = $true

        if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
            Write-Error "FFmpeg is not installed or not in the system's PATH."
            $ok = $false
        }

        if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
            Write-Error "ffprobe is not installed or not in the system's PATH. It ships alongside FFmpeg."
            $ok = $false
        }

        return $ok
    }
}
