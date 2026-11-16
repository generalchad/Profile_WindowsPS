# =====================================================================
# Targeting.Check.ps1 - Guards file-level targeting
#
# A run can be aimed at a folder, an archive or a disc image. The
# classification decides which files enter the index, and getting it
# wrong means either converting a payload on its own or converting
# nothing at all. These checks exercise the classifier, the index merge
# and the planner without invoking chdman.
#
#   pwsh -NoProfile -File .\Tests\Targeting.Check.ps1
# =====================================================================

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'Optimize-PSX.psd1') -Force
$module = Get-Module -Name Optimize-PSX

$failures = 0

function Test-Case {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Condition,
        [string]$Detail
    )

    if ($Condition) {
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } else {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor DarkGray }
        $script:failures++
    }
}

function New-SampleFile {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Name,
        [int]$Bytes = 1024,
        [string]$Content
    )

    $path = Join-Path $Directory $Name
    if ($Content) {
        Set-Content -LiteralPath $path -Value $Content -NoNewline
    } else {
        [System.IO.File]::WriteAllBytes($path, [byte[]]::new($Bytes))
    }
    return $path
}

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "OpsxTargeting-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$nested = Join-Path $sandbox 'sub'
$null = New-Item -ItemType Directory -Path $nested -Force

try {
    $cue = New-SampleFile -Directory $sandbox -Name 'Game.cue' -Content @'
FILE "Game.bin" BINARY
  TRACK 01 MODE2/2352
    INDEX 01 00:00:00
'@
    $bin = New-SampleFile -Directory $sandbox -Name 'Game.bin' -Bytes 2048
    $looseBin = New-SampleFile -Directory $sandbox -Name 'Loose.bin' -Bytes 2048
    $iso = New-SampleFile -Directory $sandbox -Name 'Disc.iso' -Bytes 4096
    $payload = New-SampleFile -Directory $sandbox -Name 'Payload.iso' -Bytes 8192
    $mixedCue = New-SampleFile -Directory $sandbox -Name 'Mixed.cue' -Content @'
FILE "Payload.iso" BINARY
  TRACK 01 MODE1/2048
    INDEX 01 00:00:00
'@
    $archive = New-SampleFile -Directory $sandbox -Name 'Archive.7z' -Bytes 1024
    $chd = New-SampleFile -Directory $sandbox -Name 'Old.chd' -Bytes 1024
    $text = New-SampleFile -Directory $sandbox -Name 'notes.txt' -Content 'not a disc image'
    $innerIso = New-SampleFile -Directory $nested -Name 'Inner.iso' -Bytes 1024

    $dc = Join-Path $sandbox 'dc'
    $null = New-Item -ItemType Directory -Path $dc -Force
    $gdi = New-SampleFile -Directory $dc -Name 'Sonic.gdi' -Content @'
2
1 0 4 2352 track01.bin 0
2 600 0 2352 track02.raw 0
'@
    $gdiTrack = New-SampleFile -Directory $dc -Name 'track01.bin' -Bytes 2048
    $null = New-SampleFile -Directory $dc -Name 'track02.raw' -Bytes 1024

    $ambiguous = Join-Path $sandbox 'ambiguous'
    $null = New-Item -ItemType Directory -Path $ambiguous -Force
    $sharedTrack = New-SampleFile -Directory $ambiguous -Name 'shared.bin' -Bytes 1024
    $null = New-SampleFile -Directory $ambiguous -Name 'One.cue' -Content "FILE `"shared.bin`" BINARY`n  TRACK 01 MODE2/2352`n    INDEX 01 00:00:00"
    $null = New-SampleFile -Directory $ambiguous -Name 'Two.cue' -Content "FILE `"shared.bin`" BINARY`n  TRACK 01 MODE2/2352`n    INDEX 01 00:00:00"

    Write-Host 'Target classification' -ForegroundColor Cyan

    $resolve = { param($path) & $module { param($p) Resolve-OpsxTarget -Path $p } $path }

    $folderTarget = & $resolve $sandbox
    Test-Case -Name 'a folder is a folder target' -Condition ($folderTarget.Status -eq 'Directory') `
              -Detail "got: $($folderTarget.Status)"

    $cueTarget = & $resolve $cue
    Test-Case -Name 'a sheet is a disc image target' -Condition ($cueTarget.Status -eq 'DiscImage') `
              -Detail "got: $($cueTarget.Status)"
    Test-Case -Name 'a sheet target carries its tracks' `
              -Condition (@($cueTarget.Files.FullName) -contains $bin -and $cueTarget.Files.Count -eq 2) `
              -Detail (($cueTarget.Files | ForEach-Object FullName) -join ', ')

    $binTarget = & $resolve $bin
    Test-Case -Name 'a track file resolves to its sibling sheet' `
              -Condition ($binTarget.Status -eq 'DiscImage' -and $binTarget.Files[0].FullName -eq $cue) `
              -Detail "status: $($binTarget.Status), first: $($binTarget.Files[0].FullName)"

    $looseTarget = & $resolve $looseBin
    Test-Case -Name 'a track file with no sheet is refused' -Condition ($looseTarget.Status -eq 'Unsupported') `
              -Detail "got: $($looseTarget.Status)"

    $gdiTrackTarget = & $resolve $gdiTrack
    $gdiScope = @($gdiTrackTarget.Files | ForEach-Object Name)
    Test-Case -Name 'a track file resolves to the sheet that references it' `
              -Condition ($gdiTrackTarget.Status -eq 'DiscImage' -and $gdiScope.Count -eq 3 -and $gdiScope[0] -eq [System.IO.Path]::GetFileName($gdi)) `
              -Detail "status: $($gdiTrackTarget.Status), files: $($gdiScope -join ', ')"

    $ambiguousTarget = & $resolve $sharedTrack
    Test-Case -Name 'a track file claimed by several sheets is refused' `
              -Condition ($ambiguousTarget.Status -eq 'Unsupported') `
              -Detail "got: $($ambiguousTarget.Status)"

    $isoTarget = & $resolve $iso
    Test-Case -Name 'a stand-alone ISO is a disc image target' `
              -Condition ($isoTarget.Status -eq 'DiscImage' -and $isoTarget.Files.Count -eq 1 -and $isoTarget.Files[0].FullName -eq $iso) `
              -Detail "status: $($isoTarget.Status), files: $($isoTarget.Files.Count)"

    $mixedTarget = & $resolve $mixedCue
    Test-Case -Name 'a sheet and its differently-named ISO stay one disc' `
              -Condition ($mixedTarget.Status -eq 'DiscImage' -and @($mixedTarget.Files.FullName) -contains $payload) `
              -Detail (($mixedTarget.Files | ForEach-Object FullName) -join ', ')

    $archiveTarget = & $resolve $archive
    Test-Case -Name 'an archive is an archive target' -Condition ($archiveTarget.Status -eq 'Archive') `
              -Detail "got: $($archiveTarget.Status)"

    $chdTarget = & $resolve $chd
    Test-Case -Name 'a CHD is reported as already converted' -Condition ($chdTarget.Status -eq 'Converted') `
              -Detail "got: $($chdTarget.Status)"

    $textTarget = & $resolve $text
    Test-Case -Name 'an unrelated file is unsupported' -Condition ($textTarget.Status -eq 'Unsupported') `
              -Detail "got: $($textTarget.Status)"

    Write-Host ''
    Write-Host 'Index merge' -ForegroundColor Cyan

    $expectedBytes = [long]([System.IO.FileInfo]::new($cue).Length + [System.IO.FileInfo]::new($bin).Length)
    $mergedIndex = & $module {
        param($files) Get-OpsxFileIndex -IncludeFile $files
    } (Get-Item -LiteralPath $cue, $bin, $cue)

    Test-Case -Name 'a repeated explicit file is indexed once' -Condition ($mergedIndex.Count -eq 2) `
              -Detail "count: $($mergedIndex.Count)"
    Test-Case -Name 'merged size matches the distinct files' -Condition ($mergedIndex.TotalBytes -eq $expectedBytes) `
              -Detail "expected: $expectedBytes, got: $($mergedIndex.TotalBytes)"

    $overlapIndex = & $module {
        param($root, $files) Get-OpsxFileIndex -Path $root -IncludeFile $files
    } $sandbox (Get-Item -LiteralPath $cue, $bin)

    Test-Case -Name 'a file under a walked folder is not counted twice' `
              -Condition (@($overlapIndex.All.FullName | Where-Object { $_ -eq $cue }).Count -eq 1) `
              -Detail "occurrences: $(@($overlapIndex.All.FullName | Where-Object { $_ -eq $cue }).Count)"

    Write-Host ''
    Write-Host 'Planner input' -ForegroundColor Cyan

    $chdmanInfo = [pscustomobject]@{ SupportsDvd = $true }
    $cuePlan = & $module {
        param($files, $info) Get-OpsxConversionPlan -Index (Get-OpsxFileIndex -IncludeFile $files) -ChdmanInfo $info
    } $cueTarget.Files $chdmanInfo

    Test-Case -Name 'a sheet target plans exactly one conversion' -Condition ($cuePlan.Jobs.Count -eq 1) `
              -Detail "jobs: $($cuePlan.Jobs.Count)"
    Test-Case -Name 'the sheet target converts the sheet, not its payload' `
              -Condition ($cuePlan.Jobs[0].SourcePath -eq $cue -and $cuePlan.Jobs[0].Command -eq 'createcd') `
              -Detail "source: $($cuePlan.Jobs[0].SourcePath)"

    $mixedPlan = & $module {
        param($files, $info) Get-OpsxConversionPlan -Index (Get-OpsxFileIndex -IncludeFile $files) -ChdmanInfo $info
    } $mixedTarget.Files $chdmanInfo

    Test-Case -Name 'a sheet ISO is not queued a second time' -Condition ($mixedPlan.Jobs.Count -eq 1) `
              -Detail "jobs: $(($mixedPlan.Jobs | ForEach-Object Name) -join ', ')"

    $isoPlan = & $module {
        param($files, $info) Get-OpsxConversionPlan -Index (Get-OpsxFileIndex -IncludeFile $files) -ChdmanInfo $info
    } $isoTarget.Files $chdmanInfo

    Test-Case -Name 'an ISO target plans one conversion' `
              -Condition ($isoPlan.Jobs.Count -eq 1 -and $isoPlan.Jobs[0].SourcePath -eq $iso) `
              -Detail "jobs: $($isoPlan.Jobs.Count)"

    Write-Host ''
    Write-Host 'Cmdlet target plumbing' -ForegroundColor Cyan

    $cueResult = Optimize-PSX -Path $cue -SkipExtraction -SkipConversion -Verbosity Minimal -PassThru
    Test-Case -Name 'a file target returns a summary' -Condition ($null -ne $cueResult) `
              -Detail 'no result object'
    Test-Case -Name 'the summary measures the disc, not the sheet alone' `
              -Condition ($cueResult.InitialBytes -eq $expectedBytes) `
              -Detail "expected: $expectedBytes, got: $($cueResult.InitialBytes)"
    Test-Case -Name 'a file-only run measures its target scope' `
              -Condition ($cueResult.InitialBytes -eq $cueResult.FinalBytes) `
              -Detail "initial: $($cueResult.InitialBytes), final: $($cueResult.FinalBytes)"

    $pipedResult = Get-Item -LiteralPath $iso | Optimize-PSX -SkipExtraction -SkipConversion -Verbosity Minimal -PassThru
    Test-Case -Name 'a piped file binds to -Path' `
              -Condition ($null -ne $pipedResult -and $pipedResult.InitialBytes -eq [System.IO.FileInfo]::new($iso).Length) `
              -Detail "initial: $($pipedResult.InitialBytes)"

    $multiResult = Optimize-PSX -Path $cue, $innerIso -SkipExtraction -SkipConversion -Verbosity Minimal -PassThru
    Test-Case -Name 'several targets share one run' -Condition ($null -ne $multiResult) `
              -Detail 'no result object'
    Test-Case -Name 'several targets are measured together' `
              -Condition ($multiResult.InitialBytes -eq ($expectedBytes + [System.IO.FileInfo]::new($innerIso).Length)) `
              -Detail "got: $($multiResult.InitialBytes)"

    $ignoredResult = Optimize-PSX -Path $text -SkipExtraction -SkipConversion -Verbosity Minimal -PassThru
    Test-Case -Name 'an unsupported target yields no result' -Condition ($null -eq $ignoredResult) `
              -Detail 'an unrelated file produced a summary'
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failures -eq 0) {
    Write-Host 'File targeting is correct.' -ForegroundColor Green
    exit 0
}

Write-Host "$failures check(s) failed." -ForegroundColor Red
exit 1
