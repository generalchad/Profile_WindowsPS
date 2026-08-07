function Set-CompressVideoConfig {
    <#
    .SYNOPSIS
        Persists one or more Compress-Video configuration overrides to
        the JSON config file.

    .DESCRIPTION
        Only the parameters you supply are changed; everything else keeps
        its current effective value (default or previously-saved
        override). Config is stored at
        $HOME\.config\Compress-Video\config.json.

    .PARAMETER Crf
        Constant rate factor / quality value passed to the encoder.
        Lower = higher quality/larger file. Typical range 18-32.

    .PARAMETER Preset
        Encoder speed/quality preset (e.g. 'medium', 'fast', 'p4').

    .PARAMETER AudioCodec
        ffmpeg audio codec, e.g. 'aac'.

    .PARAMETER AudioBitrate
        ffmpeg audio bitrate, e.g. '128k'.

    .PARAMETER HardwareAccel
        'Auto', 'None', 'NVENC', 'QSV', or 'AMF'.

    .PARAMETER ThrottleLimit
        Number of simultaneous ffmpeg jobs. Use -ThrottleLimit 0 to reset
        back to automatic resolution (1 for CPU, 2 for GPU).

    .PARAMETER Priority
        Process priority applied to ffmpeg jobs: Idle, BelowNormal, Normal.

    .PARAMETER DefaultExtensions
        Video file extensions considered by Compress-Video by default.

    .PARAMETER SkipLog
        Whether transcript logging is skipped by default.

    .PARAMETER ResumeDurationTolerance
        Fractional tolerance used by resume/skip detection (e.g. 0.01 = 1%).

    .PARAMETER Reset
        Deletes the JSON override file, reverting entirely to built-in
        defaults.

    .EXAMPLE
        Set-CompressVideoConfig -Crf 24 -Preset fast

    .EXAMPLE
        Set-CompressVideoConfig -HardwareAccel NVENC -ThrottleLimit 2

    .EXAMPLE
        Set-CompressVideoConfig -Reset
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [ValidateRange(0, 51)]
        [int]$Crf,

        [Parameter()]
        [string]$Preset,

        [Parameter()]
        [string]$AudioCodec,

        [Parameter()]
        [string]$AudioBitrate,

        [Parameter()]
        [ValidateSet('Auto', 'None', 'NVENC', 'QSV', 'AMF')]
        [string]$HardwareAccel,

        [Parameter()]
        [int]$ThrottleLimit,

        [Parameter()]
        [ValidateSet('Idle', 'BelowNormal', 'Normal')]
        [string]$Priority,

        [Parameter()]
        [string[]]$DefaultExtensions,

        [Parameter()]
        [Nullable[bool]]$SkipLog,

        [Parameter()]
        [double]$ResumeDurationTolerance,

        [Parameter()]
        [switch]$Reset
    )

    process {
        if ($Reset) {
            if ($PSCmdlet.ShouldProcess($script:ConfigPath, "Delete Compress-Video config override")) {
                if (Test-Path -LiteralPath $script:ConfigPath) {
                    Remove-Item -LiteralPath $script:ConfigPath -Force
                    Write-Host "Compress-Video configuration reset to defaults." -ForegroundColor Green
                } else {
                    Write-Host "No override file existed; already at defaults." -ForegroundColor Yellow
                }
            }
            return
        }

        $current = Get-CompressVideoConfigInternal

        if ($PSBoundParameters.ContainsKey('Crf')) { $current['Crf'] = $Crf }
        if ($PSBoundParameters.ContainsKey('Preset')) { $current['Preset'] = $Preset }
        if ($PSBoundParameters.ContainsKey('AudioCodec')) { $current['AudioCodec'] = $AudioCodec }
        if ($PSBoundParameters.ContainsKey('AudioBitrate')) { $current['AudioBitrate'] = $AudioBitrate }
        if ($PSBoundParameters.ContainsKey('HardwareAccel')) { $current['HardwareAccel'] = $HardwareAccel }
        if ($PSBoundParameters.ContainsKey('ThrottleLimit')) {
            $current['ThrottleLimit'] = if ($ThrottleLimit -le 0) { $null } else { $ThrottleLimit }
        }
        if ($PSBoundParameters.ContainsKey('Priority')) { $current['Priority'] = $Priority }
        if ($PSBoundParameters.ContainsKey('DefaultExtensions')) { $current['DefaultExtensions'] = $DefaultExtensions }
        if ($PSBoundParameters.ContainsKey('SkipLog')) { $current['SkipLog'] = [bool]$SkipLog }
        if ($PSBoundParameters.ContainsKey('ResumeDurationTolerance')) { $current['ResumeDurationTolerance'] = $ResumeDurationTolerance }

        if ($PSCmdlet.ShouldProcess($script:ConfigPath, "Save Compress-Video configuration")) {
            Save-CompressVideoConfigInternal -Config $current
            Write-Host "Compress-Video configuration saved to $script:ConfigPath" -ForegroundColor Green
            [PSCustomObject]$current
        }
    }
}
