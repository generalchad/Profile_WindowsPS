function Read-SubtitleSample {
    <#
    .SYNOPSIS
        Encoding-aware reader that returns clean dialogue lines from a subtitle file.
    .DESCRIPTION
        A large share of non-English subtitles ship as Windows-125x rather than
        UTF-8. Decoding those as UTF-8 produces mojibake and would poison any
        content based language detection, so this reads bytes and picks an
        encoding deliberately:

          1. Honour a BOM when present (UTF-8 / UTF-16 LE / UTF-16 BE).
          2. Otherwise attempt STRICT UTF-8; if it throws, the file is not UTF-8.
          3. Fall back to a codepage guess based on which legacy range dominates.

        Sequence numbers, timecodes, ASS/SSA headers and markup are stripped so
        the caller receives dialogue text only.
    .PARAMETER Path
        Full path to the subtitle file.
    .PARAMETER LineCount
        Maximum number of dialogue lines to return.
    .PARAMETER MaxBytes
        Cap on how much of the file is read. Subtitle files are small, and the
        opening lines are enough for detection.
    .OUTPUTS
        String array of dialogue lines. Empty array on any failure.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [Parameter(Position = 1)]
        [int]$LineCount = 200,

        [Parameter(Position = 2)]
        [int]$MaxBytes = 65536
    )

    try {
        $Stream = [System.IO.File]::OpenRead($Path)
        try {
            $Length = [Math]::Min([int]$Stream.Length, $MaxBytes)
            if ($Length -le 0) { return @() }
            $Bytes = [byte[]]::new($Length)
            $Read = $Stream.Read($Bytes, 0, $Length)
            if ($Read -lt $Length) { $Bytes = $Bytes[0..($Read - 1)] }
        } finally {
            $Stream.Dispose()
        }
    } catch {
        Write-Verbose "Read-SubtitleSample: unable to read '$Path': $_"
        return @()
    }

    if ($Bytes.Count -eq 0) { return @() }

    $Text = $null

    # --- 1. BOM sniffing -------------------------------------------------
    if ($Bytes.Count -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        $Text = [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Count - 3)
    }
    elseif ($Bytes.Count -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        $Text = [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Count - 2)
    }
    elseif ($Bytes.Count -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        $Text = [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Count - 2)
    }

    # --- 2. Strict UTF-8 attempt ----------------------------------------
    if ($null -eq $Text) {
        try {
            $Strict = [System.Text.UTF8Encoding]::new($false, $true)
            $Text = $Strict.GetString($Bytes)
        } catch {
            $Text = $null   # Not valid UTF-8: fall through to legacy codepages.
        }
    }

    # --- 3. Legacy codepage fallback ------------------------------------
    if ($null -eq $Text) {
        # Register the code page provider once; .NET Core omits legacy pages by default.
        if (-not $script:CodePagesRegistered) {
            try {
                [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
            } catch {
                Write-Verbose "Read-SubtitleSample: code page provider unavailable: $_"
            }
            $script:CodePagesRegistered = $true
        }

        # Cyrillic text in CP1251 clusters in 0xC0-0xFF; Latin-1/1252 accents
        # cluster lower. This is a coarse split but works well in practice.
        $High = @($Bytes | Where-Object { $_ -ge 0xC0 })
        $Mid  = @($Bytes | Where-Object { $_ -ge 0x80 -and $_ -lt 0xC0 })
        $CodePage = if ($High.Count -gt ($Mid.Count * 2) -and $High.Count -gt 20) { 1251 } else { 1252 }

        foreach ($Candidate in @($CodePage, 1252, 28591)) {
            try {
                $Text = [System.Text.Encoding]::GetEncoding($Candidate).GetString($Bytes)
                break
            } catch {
                continue
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    # --- Strip subtitle scaffolding --------------------------------------
    $Lines = $Text -split "`r?`n"
    $Dialogue = [System.Collections.Generic.List[string]]::new()

    foreach ($Line in $Lines) {
        if ($Dialogue.Count -ge $LineCount) { break }

        $L = $Line.Trim()
        if ([string]::IsNullOrWhiteSpace($L)) { continue }
        if ($L -match '^\d+$') { continue }                                   # SRT sequence number
        if ($L -match '\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->') { continue }     # SRT timecode
        if ($L -match '^\[(?:Script Info|V4\+? Styles|Events|Fonts|Graphics)\]') { continue }
        if ($L -match '^(?:Title|ScriptType|Collisions|PlayDepth|Timer|WrapStyle|Style|Format|Comment|ScaledBorderAndShadow|YCbCr Matrix|PlayResX|PlayResY|Original\w*|Last Style Storage|Audio File|Video File):') { continue }
        if ($L -match '^WEBVTT') { continue }

        # ASS/SSA dialogue: text is the 10th comma delimited field.
        if ($L -match '^Dialogue:') {
            $Parts = $L -split ',', 10
            if ($Parts.Count -eq 10) { $L = $Parts[9] } else { continue }
        }

        $L = $L -replace '\{\\[^}]*\}', ''        # ASS override tags
        $L = $L -replace '<[^>]+>', ''            # HTML markup
        $L = $L -replace '\\N|\\n', ' '           # ASS line breaks
        $L = $L -replace '^\s*[-–—]\s*', ''       # Leading dialogue dash
        $L = $L.Trim()

        if (-not [string]::IsNullOrWhiteSpace($L)) { $Dialogue.Add($L) }
    }

    return $Dialogue.ToArray()
}
