function Build-FFmpegArgs {
    <#
    .SYNOPSIS
        Builds the ffmpeg argument array for a single encode job.

    .DESCRIPTION
        Internal helper. Not exported. Combines the resolved video
        encoder (CPU or GPU) with the effective config's CRF/preset and
        audio settings, and substitutes the input/output paths.

        NVENC/QSV/AMF use different quality-control flags than libx265,
        so the encoder-specific args are branched here rather than
        forcing one flag set on all encoders.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$InputPath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$Encoder,

        [Parameter(Mandatory)]
        [int]$Crf,

        [Parameter(Mandatory)]
        [string]$Preset,

        [Parameter(Mandatory)]
        [string]$AudioCodec,

        [Parameter(Mandatory)]
        [string]$AudioBitrate,

        [Parameter()]
        [string[]]$ExtraArgs
    )

    process {
        $args = @('-y', '-i', $InputPath, '-c:v', $Encoder)

        switch -Regex ($Encoder) {
            'nvenc' {
                # NVENC uses -cq for constant-quality mode; presets are p1-p7 (fast->slow)
                # but the libx265-style preset names are commonly accepted as aliases too.
                $args += @('-preset', $Preset, '-cq', "$Crf", '-rc', 'vbr')
            }
            'qsv' {
                $args += @('-preset', $Preset, '-global_quality', "$Crf")
            }
            'amf' {
                $args += @('-quality', $Preset, '-rc', 'cqp', '-qp_i', "$Crf", '-qp_p', "$Crf")
            }
            default {
                # CPU: libx265
                $args += @('-preset', $Preset, '-crf', "$Crf")
            }
        }

        $args += @('-c:a', $AudioCodec, '-b:a', $AudioBitrate)

        if ($ExtraArgs) { $args += $ExtraArgs }

        $args += $OutputPath

        return $args
    }
}
