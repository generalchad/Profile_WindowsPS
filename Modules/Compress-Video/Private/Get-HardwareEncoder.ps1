function Get-HardwareEncoder {
    <#
    .SYNOPSIS
        Resolves which HEVC encoder to use based on -HardwareAccel and
        whether the encoder actually initializes on this machine.

    .DESCRIPTION
        Internal helper. Not exported. "Compiled in" is not "works at
        runtime": a full ffmpeg build lists hevc_nvenc/hevc_qsv/hevc_amf
        even when the matching driver is absent, and then fails on the
        first real encode (e.g. NVENC cannot load nvcuda.dll without an
        NVIDIA driver). So instead of grepping `ffmpeg -encoders`, each
        candidate is validated with a one-frame null encode and only the
        ones that exit cleanly are considered available. Results are
        cached per session in $script:AvailableEncoders.

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
            $script:AvailableEncoders = @{
                NVENC = Test-EncoderInitializes -Encoder 'hevc_nvenc'
                QSV   = Test-EncoderInitializes -Encoder 'hevc_qsv'
                AMF   = Test-EncoderInitializes -Encoder 'hevc_amf'
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
            Write-Warning "Requested hardware encoder '$HardwareAccel' could not initialize on this machine. Falling back to CPU (libx265)."
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

function Test-EncoderInitializes {
    <#
    .SYNOPSIS
        Returns $true only if ffmpeg can actually open the given encoder
        on this machine (not merely that it is compiled in).

    .DESCRIPTION
        Internal helper. Not exported. Runs a one-frame null encode, which
        forces the encoder to initialize (load its driver/DLL, allocate a
        session) without writing a file. A missing driver - e.g. NVENC
        without nvcuda.dll - makes ffmpeg exit non-zero, so the encoder is
        reported unavailable and callers fall back to the next candidate.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Encoder
    )

    process {
        try {
            $null = & ffmpeg -hide_banner -v error -f lavfi -i "color=black:s=32x32:d=0.1" -frames:v 1 -c:v $Encoder -f null - 2>&1
            return ($LASTEXITCODE -eq 0)
        } catch {
            return $false
        }
    }
}
