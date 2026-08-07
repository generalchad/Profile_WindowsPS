# =====================================================================
# _Config.ps1 - Default configuration and JSON config file management
#
# Loaded FIRST by the module loader. Provides $script:DefaultConfig and
# the Get-/Save- helpers used by both the Public config cmdlets and the
# main Compress-Video pipeline to resolve effective settings.
# =====================================================================

# Hardcoded, safe-by-default configuration. Never mutated directly -
# Get-CompressVideoConfig merges this with any JSON overrides on disk.
$script:DefaultConfig = [ordered]@{
    DefaultExtensions = @(".avi", ".flv", ".mp4", ".mov", ".mkv", ".wmv", ".ts", ".m4v")

    # Codec / quality settings. Video codec/encoder is resolved at runtime
    # by Get-HardwareEncoder based on HardwareAccel below.
    Crf           = 28
    Preset        = "medium"
    AudioCodec    = "aac"
    AudioBitrate  = "128k"

    # 'Auto' probes ffmpeg for nvenc/qsv/amf and picks the best available,
    # falling back to CPU (libx265) if none are found. Explicit values:
    # 'None', 'NVENC', 'QSV', 'AMF' bypass probing entirely.
    HardwareAccel = "Auto"

    # $null = auto-resolved at runtime (1 for CPU encoding, 2 for GPU).
    # Set an explicit integer here to always override auto-resolution.
    ThrottleLimit = $null

    # Process priority applied to every spawned ffmpeg process so
    # compression never starves the foreground/interactive session.
    # One of: Idle, BelowNormal, Normal.
    Priority = "BelowNormal"

    SkipLog = $false

    # Tolerance (as a fraction, e.g. 0.01 = 1%) used by resume-detection
    # when comparing an existing output's duration against the source.
    ResumeDurationTolerance = 0.01
}

$script:ConfigDirectory = Join-Path $HOME ".config\Compress-Video"
$script:ConfigPath      = Join-Path $script:ConfigDirectory "config.json"

function Get-CompressVideoConfigInternal {
    <#
    .SYNOPSIS
        Returns the effective configuration: defaults merged with any
        JSON overrides found on disk. Internal helper, not exported.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    process {
        $effective = [ordered]@{}
        foreach ($key in $script:DefaultConfig.Keys) {
            $effective[$key] = $script:DefaultConfig[$key]
        }

        if (Test-Path -LiteralPath $script:ConfigPath) {
            try {
                $json = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
                foreach ($prop in $json.PSObject.Properties) {
                    if ($effective.Contains($prop.Name)) {
                        $effective[$prop.Name] = $prop.Value
                    }
                }
            } catch {
                Write-Warning "Compress-Video: failed to parse config at '$script:ConfigPath': $_. Using defaults."
            }
        }

        return $effective
    }
}

function Save-CompressVideoConfigInternal {
    <#
    .SYNOPSIS
        Writes the supplied configuration hashtable/dictionary to the
        JSON config file, creating the directory if necessary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Config
    )

    process {
        if (-not (Test-Path -LiteralPath $script:ConfigDirectory)) {
            New-Item -Path $script:ConfigDirectory -ItemType Directory -Force | Out-Null
        }

        $Config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:ConfigPath -Encoding utf8
    }
}
