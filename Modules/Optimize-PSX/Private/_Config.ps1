# =====================================================================
# _Config.ps1 - Shared lookup tables, extension maps and tuning defaults
#
# Loaded FIRST by the module loader. Every value here is script-scoped so
# private functions can read them without parameter threading.
# =====================================================================

# ---------------------------------------------------------------------
# ARCHIVE FORMATS
#
# Extensions 7Zip4PowerShell (7z.dll) can open. Single-file streams
# (.gz/.bz2/.xz) carry no directory structure but are included because
# releases occasionally ship a lone compressed image.
# ---------------------------------------------------------------------
$script:ArchiveExtensions = @(
    '.7z', '.zip', '.rar', '.gz', '.bz2', '.xz', '.tar', '.tgz', '.cab', '.lzh', '.arj'
)

# Formats Expand-Archive handles natively, used when 7Zip4PowerShell is
# unavailable.
$script:NativeArchiveExtensions = @('.zip')

# ---------------------------------------------------------------------
# DISC IMAGE FORMATS
#
# SHEET extensions describe a disc and are the files handed to chdman.
# TRACK extensions are the payload referenced by a sheet, and are never
# conversion inputs in their own right: passing chdman a bare .bin from a
# multi-track set yields a CHD containing only that track.
# ---------------------------------------------------------------------
$script:SheetExtensions = @('.cue', '.gdi', '.ccd')
$script:TrackExtensions = @('.bin', '.img', '.raw', '.sub', '.iso', '.wav', '.mp3', '.ape', '.flac', '.ogg')

# Sheets plus payloads. Used for size accounting and deletion candidates.
$script:ImageExtensions = @($script:SheetExtensions) + @($script:TrackExtensions) | Sort-Object -Unique

# CloneCD writes .ccd/.img/.sub as a unit.
$script:CcdSidecarExtensions = @('.img', '.sub')

# ---------------------------------------------------------------------
# CHDMAN
#
# createcd  - CD media: PSX, PS2 (CD), Saturn, Dreamcast, PC Engine CD
# createdvd - DVD media: PS2 DVD, Xbox, GameCube/Wii. Added in 0.262.
#
# On binaries older than 0.262 a DVD-sized ISO falls back to createcd,
# which still produces a valid if marginally larger CHD.
# ---------------------------------------------------------------------
$script:ChdmanCommandForSheets = 'createcd'
$script:ChdmanMinVersionForDvd = [version]'0.262'

# An ISO above this size is treated as DVD media. A CD tops out near
# 900 MB even with an oversized 99-minute burn.
$script:DvdSizeThreshold = 1GB

# Codec chains chdman applies by default, stated explicitly so the summary
# can report what was used and -Compression can override it.
$script:DefaultCdCodecs = @('cdlz', 'cdzl', 'cdfl')
$script:DefaultDvdCodecs = @('lzma', 'zlib', 'huff', 'flac')

# Accepted codec names, validated before launch so a typo fails
# immediately rather than after a long batch.
$script:ValidCodecs = @(
    'none', 'zlib', 'zstd', 'lzma', 'huff', 'flac',
    'cdzl', 'cdzs', 'cdlz', 'cdfl', 'avhu'
)

# ---------------------------------------------------------------------
# CONCURRENCY TUNING
#
# Two dials interact multiplicatively:
#   1. --numprocessors N : worker threads inside one chdman process
#   2. concurrent processes : images compressed simultaneously
#
# chdman's internal threading scales sub-linearly because each hunk
# stream has a serial read and hash path, so returns fall off sharply
# past four threads. Several processes with a modest thread count each
# therefore outperform one process with a large count, provided storage
# can feed them.
# ---------------------------------------------------------------------
$script:MaxUsefulThreadsPerJob = 4
$script:DefaultThreadsPerJob = 2

# Ceiling on derived concurrency, regardless of core count or budget.
#
# Past roughly four concurrent conversions the bottleneck stops being CPU:
# every process is streaming a multi-gigabyte image, so the storage queue
# saturates and total throughput stops improving while responsiveness for
# everything else on the machine collapses. Surplus budget is redirected
# into threads-per-job, where it still buys something.
#
# An explicit -MaxConcurrency bypasses this. Asking for it by hand is a
# deliberate act; deriving it from a percentage is not.
$script:MaxDerivedConcurrency = 4


# Extraction is disk-bound and single-threaded per archive, so it takes a
# lower ceiling than compression.
$script:MaxExtractionConcurrency = 3

# Process pump poll interval. Imperceptible in the progress display while
# keeping the orchestrating thread near-idle.
$script:PumpIntervalMs = 150

# ---------------------------------------------------------------------
# PROGRESS BAR IDS
#
# Reserved so parent and child bars never collide. Child slots occupy
# ChildProgressBase + slot index.
# ---------------------------------------------------------------------
$script:ParentProgressId = 1
$script:ChildProgressBase = 10

# ---------------------------------------------------------------------
# CHDMAN OUTPUT PARSING
#
# Progress is written as carriage-return-updated lines of the form
#   Compressing, 42.7% complete... (ratio=38.1%)
# ---------------------------------------------------------------------
$script:RegexChdmanProgress = '(?<Percent>\d{1,3}(?:\.\d+)?)%\s*complete'
$script:RegexChdmanRatio = 'ratio\s*=\s*(?<Ratio>\d{1,3}(?:\.\d+)?)%'
$script:RegexChdmanVersion = 'chdman.*?(?<Version>\d+\.\d+)'

# ---------------------------------------------------------------------
# CUE SHEET PARSING
#
# Cue sheets are line-oriented. FILE lines drive dependency resolution;
# TRACK lines are counted to identify multi-track sets.
# ---------------------------------------------------------------------
$script:RegexCueFile = '(?im)^\s*FILE\s+(?:"(?<Quoted>[^"]+)"|(?<Bare>\S+))\s+(?<Type>\w+)\s*$'
$script:RegexCueTrack = '(?im)^\s*TRACK\s+(?<Number>\d+)\s+(?<Mode>\S+)\s*$'

# ---------------------------------------------------------------------
# GDI PARSING
#
# Dreamcast GDI: first line is the track count, then one line per track,
#   <index> <lba> <type> <sectorSize> <filename> <offset>
# ---------------------------------------------------------------------
$script:RegexGdiTrack = '^\s*(?<Index>\d+)\s+(?<Lba>\d+)\s+(?<Type>\d+)\s+(?<SectorSize>\d+)\s+(?:"(?<Quoted>[^"]+)"|(?<Bare>\S+))'

# ---------------------------------------------------------------------
# OUTPUT SUFFIXES
#
# CHDs are written to a temporary name and moved into place only after a
# clean exit, so an interrupted batch leaves an obviously incomplete
# .chd.tmp rather than a truncated .chd.
#
# Appended to the full output path, which already ends in .chd, giving
# 'Game.chd.tmp'. The suffix therefore carries only '.tmp'; spelling it
# '.chd.tmp' here produced 'Game.chd.chd.tmp'.
# ---------------------------------------------------------------------
$script:TempChdSuffix = '.tmp'

# ---------------------------------------------------------------------
# SESSION STATE
#
# Set at import so Set-StrictMode does not fault on a first read before
# assignment. Populated lazily at runtime.
# ---------------------------------------------------------------------
$script:VisualBasicLoaded = $false
$script:OpsxLogFile = $null
$script:OpsxVerbosity = 'Normal'



