function Find-File {
    <#
    .SYNOPSIS
        Recursively finds files whose name contains a substring.
    .PARAMETER Name
        Substring to match against file names.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    Write-Debug "Find-File: Searching for files matching '$Name'"
    Get-ChildItem -Recurse -Filter "*$Name*" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
}

function Find-Text {
    <#
    .SYNOPSIS
        Searches file contents (or pipeline input) for a regex.
    .DESCRIPTION
        When -Path is supplied, searches the given files; otherwise searches
        piped input. Select-String returns the matching lines.
    .PARAMETER Regex
        Regular expression to match.
    .PARAMETER Path
        Files to search. Defaults to pipeline input when omitted.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Regex,

        [Parameter(ValueFromPipeline)]
        [string[]]$Path = @()
    )

    Write-Debug "Find-Text: Searching for text matching '$Regex' in $Path"

    if ($Path.Count -eq 0) {
        $input | Select-String $Regex
    }
    else {
        Get-ChildItem $Path | Select-String $Regex
    }
}

function New-File {
    <#
    .SYNOPSIS
        Creates an empty file, optionally marking it Hidden and/or System.
    .PARAMETER Path
        File path. Defaults to ".\New file".
    .PARAMETER Hidden
        Set the Hidden attribute on the new file.
    .PARAMETER System
        Set the System attribute on the new file.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [string]$Path = ".\New file",

        [Parameter(Position = 1)]
        [switch]$Hidden,

        [Parameter(Position = 2)]
        [switch]$System
    )

    process {
        try {
            Write-Debug "New-File: Creating new file at $Path"
            $NewItem = New-Item -Path $Path -ItemType File -Force
            if ($Hidden) { $NewItem.Attributes += "Hidden" }
            if ($System) { $NewItem.Attributes += "System" }
            Write-Debug "New-File: Created new file at $Path"
        }
        catch [System.UnauthorizedAccessException] {
            Write-Error "New File: You do not have the correct permissions: $_"
        }
        catch {
            Write-Error "New File: An unexpected error occurred: $_"
        }
    }
}

function Invoke-Explorer {
    <#
    .SYNOPSIS
        Opens a Windows File Explorer window at the specified path.
    .DESCRIPTION
        This function uses the 'explorer.exe' process to open a File Explorer
        window to any local path, including network shares and UNC paths.
        It defaults to the current working directory ('.').
    .PARAMETER Path
        The path to open in the File Explorer. This can be a directory 
        or a file (which will open the containing folder and select the file).
        Defaults to the current directory ('.').
    .EXAMPLE
        Invoke-Explorer 
        # Opens File Explorer at the current directory.
    .EXAMPLE
        Invoke-Explorer C:\Users\Public\Documents
        # Opens File Explorer at the specified absolute path.
    .EXAMPLE
        explorer | iex 
        # Note: The alias 'explore' is often used instead of 'Invoke-Explorer'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = "."
    )
    
    process {
        Write-Debug "Invoke-Explorer: Attempting to open explorer at '$Path'"
        
        try {
            $resolvedPath = (Resolve-Path -Path $Path).ProviderPath
            
            Start-Process -FilePath "explorer.exe" -ArgumentList $resolvedPath -NoNewWindow
        }
        catch {
            Write-Error "Invoke-Explorer: Could not resolve or open path '$Path'. Error: $($_.Exception.Message)"
        }
    }
}

function New-Folder {
    <#
    .SYNOPSIS
        Creates a directory, optionally marking it Hidden and/or System.
    .DESCRIPTION
        When invoked via the mkcd alias, also changes into the new directory.
    .PARAMETER Path
        Directory path. Defaults to ".\New folder".
    .PARAMETER Hidden
        Set the Hidden attribute on the new directory.
    .PARAMETER System
        Set the System attribute on the new directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [string]$Path = ".\New folder",
        [Parameter(Position = 1)]
        [switch]$Hidden,
        [Parameter(Position = 2)]
        [switch]$System
    )

    process {
        try {
            Write-Debug "New-Folder: Creating new folder at $Path"
            $NewFolder = New-Item -Path $Path -ItemType Directory -Force
            if ($Hidden) { $NewFolder.Attributes += "Hidden" }
            if ($System) { $NewFolder.Attributes += "System" }
            Write-Debug "New-Folder: Created new folder at $Path"
        }
        catch [System.UnauthorizedAccessException] {
            Write-Error "New-Folder: You do not have the correct permissions: $_" -ErrorAction Continue
            return
        }
        catch {
            Write-Error "New-Folder: An unexpected error occurred: $_" -ErrorAction Continue
            return
        }

        if ($MyInvocation.InvocationName -eq "mkcd") {
            Set-Location $Path
        }
    }
}

function Extract-Archive {
    <#
    .SYNOPSIS
        Expands an archive, creating the destination directory if needed.
    .PARAMETER Path
        Archive to expand.
    .PARAMETER DestinationPath
        Where to extract. Defaults to the current directory.
    .PARAMETER Force
        Passed through to Expand-Archive to overwrite existing files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,

        [Parameter(Position=1)]
        [string]$DestinationPath = $pwd,

        [switch]$Force
    )

    $resolvedPath = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        Write-Error "unzip: File not found at '$Path'"
        return
    }

    if (-not (Test-Path $DestinationPath)) {
        Write-Verbose "Destination '$DestinationPath' not found. Creating it."
        New-Item -Path $DestinationPath -ItemType Directory | Out-Null
    }

    Write-Host "Extracting '$($resolvedPath.ProviderPath)' to '$DestinationPath'..."
    Expand-Archive -LiteralPath $resolvedPath.ProviderPath -DestinationPath $DestinationPath -Force:$Force
}

function Replace-Text {
    <#
    .SYNOPSIS
        Replaces regex matches in files or pipeline text, optionally in place.
    .DESCRIPTION
        With -Path, reads each file and either writes the result back (-InPlace,
        gated by ShouldProcess) or streams the transformed lines to the pipeline.
        Without -Path, transforms the piped input object.
    .PARAMETER Pattern
        Regular expression to match.
    .PARAMETER Replacement
        Replacement text.
    .PARAMETER Path
        Files to process. Accepts pipeline input by property name.
    .PARAMETER InputObject
        Text to transform when -Path is not used. Accepts pipeline input.
    .PARAMETER InPlace
        Write the result back to each file instead of streaming to the pipeline.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Pattern,

        [Parameter(Mandatory, Position = 1)]
        [string]$Replacement,

        [Parameter(Position = 2, ValueFromPipelineByPropertyName)]
        [string[]]$Path,

        [Parameter(ValueFromPipeline)]
        [string]$InputObject,

        [Parameter()]
        [switch]$InPlace
    )

    begin {
        Write-Debug "Replace-Text: Pattern='$Pattern', Replacement='$Replacement', InPlace=$InPlace, Path=$Path"
    }

    process {
        if ($PSBoundParameters.ContainsKey('Path')) {
            foreach ($file in $Path) {
                $resolvedPath = Resolve-Path -LiteralPath $file
                if ($InPlace) {
                    if ($PSCmdlet.ShouldProcess($resolvedPath, "Replace text ('$Pattern' -> '$Replacement')")) {
                        $tempFile = [System.IO.Path]::GetTempFileName()
                        $reader = [System.IO.File]::OpenText($resolvedPath)
                        $writer = [System.IO.File]::CreateText($tempFile)
                        while ($null -ne ($line = $reader.ReadLine())) {
                            $writer.WriteLine($line -replace $Pattern, $Replacement)
                        }
                        $reader.Close()
                        $writer.Close()
                        Move-Item -Path $tempFile -Destination $resolvedPath -Force
                    }
                }
                else {
                    Get-Content -Path $resolvedPath | ForEach-Object { $_ -replace $Pattern, $Replacement }
                }
            }
        }
        else {
            $InputObject -replace $Pattern, $Replacement
        }
    }
}