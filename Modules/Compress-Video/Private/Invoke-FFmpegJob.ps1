function Invoke-FFmpegJob {
    <#
    .SYNOPSIS
        Runs a single ffmpeg encode as a child process with a controlled
        priority class, waits for completion, and returns a result object.

    .DESCRIPTION
        Internal helper. Not exported. Uses Start-Process rather than the
        `&` call operator so the process's PriorityClass can be set right
        after launch - this keeps compression from starving the
        interactive session's CPU/GPU scheduling, per the module's
        "never saturate the PC" design goal.

    .PARAMETER Priority
        One of Idle, BelowNormal, Normal. Applied via
        System.Diagnostics.Process.PriorityClass.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$InputFile,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string[]]$FFmpegArgs,

        [Parameter()]
        [ValidateSet('Idle', 'BelowNormal', 'Normal')]
        [string]$Priority = 'BelowNormal',

        [switch]$DeleteSource
    )

    process {
        try {
            $stdErrPath = [System.IO.Path]::GetTempFileName()

            $startInfo = @{
                FilePath               = 'ffmpeg'
                ArgumentList           = $FFmpegArgs
                NoNewWindow            = $true
                PassThru               = $true
                RedirectStandardError  = $stdErrPath
                Wait                   = $false
            }

            $proc = Start-Process @startInfo

            try {
                $priorityMap = @{
                    'Idle'        = [System.Diagnostics.ProcessPriorityClass]::Idle
                    'BelowNormal' = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
                    'Normal'      = [System.Diagnostics.ProcessPriorityClass]::Normal
                }
                $proc.PriorityClass = $priorityMap[$Priority]
            } catch {
                Write-Verbose "Could not set process priority: $_"
            }

            $proc.WaitForExit()
            $exitCode = $proc.ExitCode

            if ($exitCode -eq 0) {
                $outputItem = Get-Item $OutputPath -ErrorAction SilentlyContinue

                if ($DeleteSource -and $outputItem) {
                    Remove-Item $InputFile.FullName -Force
                    Write-Verbose "Deleted source: $($InputFile.FullName)"
                }

                return [PSCustomObject]@{
                    Success    = $true
                    InputFile  = $InputFile
                    OutputFile = $outputItem
                    Error      = $null
                }
            } else {
                $stderrText = if (Test-Path $stdErrPath) { Get-Content $stdErrPath -Raw } else { "" }
                throw "FFmpeg exited with code $exitCode. $stderrText"
            }
        }
        catch {
            return [PSCustomObject]@{
                Success    = $false
                InputFile  = $InputFile
                OutputFile = $null
                Error      = $_
            }
        }
        finally {
            if ($stdErrPath -and (Test-Path $stdErrPath)) {
                Remove-Item $stdErrPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
