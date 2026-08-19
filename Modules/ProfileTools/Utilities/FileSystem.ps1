function Find-File {
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