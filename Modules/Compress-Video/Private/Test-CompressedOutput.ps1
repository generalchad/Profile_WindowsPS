function Test-CompressedOutput {
    <#
    .SYNOPSIS
        Determines whether an existing output file represents a complete,
        valid compression of the given input (resume/skip detection).

    .DESCRIPTION
        Internal helper. Not exported. Compares the input and output
        durations (via ffprobe) within a tolerance. If the output is
        missing, corrupt (no readable duration), or its duration deviates
        from the input beyond the tolerance, the result is 'Invalid' -
        callers should treat this as "needs (re)encoding".

    .PARAMETER InputPath
        Path to the source video.

    .PARAMETER OutputPath
        Path to the (possibly pre-existing) compressed output.

    .PARAMETER Tolerance
        Fractional tolerance (e.g. 0.01 = 1%) allowed between input and
        output durations before the output is considered invalid.

    .PARAMETER Strict
        When the source duration cannot be read, report 'Invalid' instead
        of the normal 'Complete'. Used by deletion-safety callers so a
        source is never deleted without being able to verify the output.

    .OUTPUTS
        PSCustomObject with:
            Status  - 'Complete', 'Missing', or 'Invalid'
            Reason  - human readable explanation
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$InputPath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [double]$Tolerance = 0.01,

        [Parameter()]
        [switch]$Strict
    )

    process {
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            return [PSCustomObject]@{ Status = 'Missing'; Reason = 'Output file does not exist' }
        }

        $outDuration = Get-VideoDuration -Path $OutputPath
        if ($null -eq $outDuration -or $outDuration -le 0) {
            return [PSCustomObject]@{ Status = 'Invalid'; Reason = 'Output file is corrupt or unreadable by ffprobe' }
        }

        $inDuration = Get-VideoDuration -Path $InputPath
        if ($null -eq $inDuration -or $inDuration -le 0) {
            if ($Strict) {
                # Deletion-safety callers must NOT trust an unverifiable
                # source - treat it as invalid so the source is never
                # deleted without proof.
                return [PSCustomObject]@{ Status = 'Invalid'; Reason = 'Source duration unreadable; cannot verify' }
            }
            # Skip-detection callers treat the existing output as complete
            # rather than blocking forever.
            return [PSCustomObject]@{ Status = 'Complete'; Reason = 'Source duration unreadable; trusting existing output' }
        }

        $delta = [Math]::Abs($inDuration - $outDuration) / $inDuration
        if ($delta -le $Tolerance) {
            return [PSCustomObject]@{ Status = 'Complete'; Reason = "Duration matches within tolerance ($([Math]::Round($delta*100,2))%)" }
        }

        return [PSCustomObject]@{ Status = 'Invalid'; Reason = "Duration mismatch: input=${inDuration}s output=${outDuration}s (delta $([Math]::Round($delta*100,2))%)" }
    }
}
