function Get-CompressVideoConfig {
    <#
    .SYNOPSIS
        Returns the effective Compress-Video configuration.

    .DESCRIPTION
        Merges the module's built-in defaults with any overrides saved
        via Set-CompressVideoConfig (stored as JSON under
        $HOME\.config\Compress-Video\config.json). Values not present in
        the JSON file fall back to the defaults, so partial overrides
        (e.g. just Crf) work as expected.

    .EXAMPLE
        Get-CompressVideoConfig

    .EXAMPLE
        (Get-CompressVideoConfig).Crf
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    process {
        $effective = Get-CompressVideoConfigInternal
        [PSCustomObject]$effective
    }
}
