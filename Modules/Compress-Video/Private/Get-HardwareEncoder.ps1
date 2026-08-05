function Get-HardwareEncoder {
    <#
    .SYNOPSIS
        Resolves which HEVC encoder to use based on -HardwareAccel and
        the encoders actually compiled into the local ffmpeg build.

    .DESCRIPTION
        Internal helper. Not exported. Probes `ffmpeg -hide_banner -encoders`
        once per session (cached in $script:AvailableEncoders) and maps the
        requested acceleration mode to a concrete ffmpeg -c:v value.

        Priority order for 'Auto': NVENC > QSV > AMF > CPU (libx265).

    .PARAMETER HardwareAccel
        One of 'Auto', 'None', 'NVENC', 'QSV', 'AMF'.

    .OUTPUTS
        PSCustomObject with:
            Encoder   - the ffmpeg -c:v value to use (e.g. 'hevc_nvenc', 'libx265')
            IsHardware - $true if a GPU encoder was resolved, $false for CPU
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Auto', 'None', 'NVENC', 'QSV', 'AMF')]
        [string]$HardwareAccel = 'Auto'
    )

    process {
        if ($HardwareAccel -eq 'None') {
            return [PSCustomObject]@{ Encoder = 'libx265'; IsHardware = $false }
        }

        # Under Set-StrictMode, referencing an unset script-scope variable
        # throws, so the cache must be probed via Test-Path variable:
        # rather than a plain truthiness check on first-ever access.
        if (-not (Test-Path Variable:script:AvailableEncoders) -or -not $script:AvailableEncoders) {
            try {
                $raw = & ffmpeg -hide_banner -encoders 2>&1 | Out-String
            } catch {
                $raw = ""
            }
            $script:AvailableEncoders = @{
                NVENC = ($raw -match 'hevc_nvenc')
                QSV   = ($raw -match 'hevc_qsv')
                AMF   = ($raw -match 'hevc_amf')
            }
        }

        $map = @{
            NVENC = 'hevc_nvenc'
            QSV   = 'hevc_qsv'
            AMF   = 'hevc_amf'
        }

        if ($HardwareAccel -ne 'Auto') {
            if ($script:AvailableEncoders[$HardwareAccel]) {
                return [PSCustomObject]@{ Encoder = $map[$HardwareAccel]; IsHardware = $true }
            }
            Write-Warning "Requested hardware encoder '$HardwareAccel' was not found in this ffmpeg build. Falling back to CPU (libx265)."
            return [PSCustomObject]@{ Encoder = 'libx265'; IsHardware = $false }
        }

        # Auto: NVENC > QSV > AMF > CPU
        foreach ($candidate in @('NVENC', 'QSV', 'AMF')) {
            if ($script:AvailableEncoders[$candidate]) {
                return [PSCustomObject]@{ Encoder = $map[$candidate]; IsHardware = $true }
            }
        }

        return [PSCustomObject]@{ Encoder = 'libx265'; IsHardware = $false }
    }
}
