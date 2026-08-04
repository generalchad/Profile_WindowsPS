function New-OpsxJob {
    <#
    .SYNOPSIS
        Creates a conversion job record.
    .DESCRIPTION
        One shape carries a job from planning through execution to reporting, so
        the preview, the batch runner and the summary all read the same fields.

        Result fields are initialised here and filled in by Invoke-ChdmanBatch.
    .PARAMETER Source
        The image file handed to chdman.
    .PARAMETER OutputPath
        Final CHD path.
    .PARAMETER Command
        chdman subcommand, createcd or createdvd.
    .PARAMETER Dependencies
        Track files referenced by the source, used for post-conversion cleanup.
    .PARAMETER SourceBytes
        Combined size of the source and its dependencies.
    .OUTPUTS
        PSCustomObject with PSTypeName 'Optimize-PSX.Job'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$Source,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$Command,

        [AllowEmptyCollection()]
        [string[]]$Dependencies = @(),

        [long]$SourceBytes = 0
    )

    [pscustomobject]@{
        PSTypeName   = 'Optimize-PSX.Job'

        # Planning
        Action       = 'Convert'
        Reason       = $null
        Name         = $Source.Name
        SourcePath   = $Source.FullName
        Directory    = $Source.DirectoryName
        Extension    = $Source.Extension
        OutputPath   = $OutputPath
        # 'Game.chd' -> 'Game.chd.tmp'. Suffixing the finished name rather
        # than replacing its extension keeps the temporary file sorted next
        # to its eventual output and makes an abandoned one obvious.
        TempPath     = "$OutputPath$script:TempChdSuffix"
        Command      = $Command
        Dependencies = @($Dependencies)
        SourceBytes  = $SourceBytes

        # Execution
        Status       = 'Pending'
        ExitCode     = $null
        OutputBytes  = 0
        Ratio        = $null
        Duration     = [timespan]::Zero
        Error        = $null
        Slot         = $null
    }
}
