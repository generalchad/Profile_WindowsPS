# =====================================================================
# _Config.ps1 - Built-in allow-lists, protected object tables and tuning
#
# Loaded FIRST by the module loader. Every value here is script-scoped so
# private functions can read them without parameter threading.
#
# The tables below are the safety net for a tool whose whole job is
# deletion. When in doubt an entry belongs here: a printer that survives
# a sweep is an annoyance, a printer that should have survived and did
# not is a support call.
# =====================================================================

# ---------------------------------------------------------------------
# PROTECTED PRINT QUEUES - by name
#
# Wildcard patterns matched with -like against the queue name. These are
# the "defaults" a technician's laptop is expected to have: the two
# Windows in-box virtual printers, whichever OneNote build is installed,
# the fax queue, and the Adobe writer (deliberately spared - older techs
# rely on it and its absence generates more complaints than the clutter
# it causes).
# ---------------------------------------------------------------------
$script:DefaultKeepPrinterNames = @(
    'Microsoft Print to PDF'
    'Microsoft XPS Document Writer*'
    'OneNote*'
    'Send To OneNote*'
    'Fax'
    'Adobe PDF*'
    'Snagit*'
    'Microsoft Software Printer Driver'
)

# ---------------------------------------------------------------------
# PROTECTED PRINT QUEUES - by driver
#
# Name matching alone is not enough: a queue can be renamed ("PDF" or
# "Printer (1)") while still being the in-box Print to PDF, and deleting
# it leaves the machine without a virtual printer until the optional
# feature is toggled off and back on. The driver name never changes, so
# it is the reliable identifier.
# ---------------------------------------------------------------------
$script:DefaultKeepPrinterDrivers = @(
    'Microsoft Print To PDF'
    'Microsoft XPS Document Writer*'
    'Send to Microsoft OneNote*'
    'Microsoft Shared Fax Driver'
    'Adobe PDF Converter'
    'Microsoft Software Printer Driver'
)

# ---------------------------------------------------------------------
# PROTECTED PORTS
#
# Monitors and pseudo-ports that belong to Windows itself or to the
# protected queues above. Deleting any of these either fails outright or
# breaks a queue that was meant to survive.
#
# LPT/COM are physical hardware ports enumerated by the OS, not spooler
# objects; they reappear on reboot but the deletion attempt logs a
# spurious failure, so they are excluded up front.
# ---------------------------------------------------------------------
$script:ProtectedPortNames = @(
    'FILE:'
    'PORTPROMPT:'
    'nul:'
    'NUL'
    'SHRFAX:'
    'XPSPort:*'
    'PORTPROMPT'
    'Microsoft.Office.OneNote*'
    'OneNote*'
    'PDF*'
    'DOT4*'
    'USB*'
    'LPT*'
    'COM*'
    'IPP*'
)

# ---------------------------------------------------------------------
# SWEEPABLE PORT MONITORS
#
# Only ports served by these monitors are candidates for the orphan
# sweep. Restricting by monitor rather than by name means a third-party
# vendor monitor (Canon, Xerox, Kyocera bidirectional monitors) is left
# alone: those often carry configuration the vendor utility depends on,
# and their ports are recreated by the vendor software anyway.
#
# 'Standard TCP/IP Port' covers the ports created when a tech adds a
# device by IP - by far the dominant source of clutter.
# ---------------------------------------------------------------------
$script:SweepablePortMonitors = @(
    'Standard TCP/IP Port'
    'WSD Port'
    'LPR Port'
    'AppleTalk Printing Devices'
    'Local Port'
)

# ---------------------------------------------------------------------
# QUEUE CLASSIFICATION PATTERNS
#
# Redirected queues are projected into the session by RDP, Citrix or a
# VM guest-integration service. They are recreated on the next logon
# regardless of what we do, so removing them accomplishes nothing and
# briefly breaks printing inside the active remote session.
# ---------------------------------------------------------------------
$script:RegexRedirectedPrinter = '(?i)(_redirected_|\bredirected\b|\(redirected\s+\d+\)|^TS\d{3}|\bvia\s+(RDP|Citrix|TS)\b)'

# A queue whose name starts with \\ is a connection to a print server
# rather than a locally defined queue. On a domain-joined laptop these
# are usually pushed by Group Policy and will simply come back.
$script:RegexNetworkPrinter = '^\\\\'

# ---------------------------------------------------------------------
# SCANNER / IMAGING DEVICES
#
# The imaging stack is PnP, not spooler, so it is enumerated and removed
# separately. Network-discovered devices (WSD/eSCL) are the ones that
# accumulate: they are created by discovery, never cleaned up, and each
# one keeps a stale IP association. USB devices re-enumerate the instant
# the cable is plugged back in, so removing them is pointless churn and
# they are skipped unless -Force is given.
# ---------------------------------------------------------------------
$script:ScannerDeviceClasses = @('Image', 'Camera')

# Instance ID prefixes considered "network discovered" and therefore
# sweepable by default.
$script:NetworkDeviceIdPrefixes = @('WSD', 'SWD\WSD', 'ESCL', 'SWD\ESCL', 'ROOT\WSD')

# Instance ID prefixes that indicate a physically attached device.
$script:LocalDeviceIdPrefixes = @('USB', 'USBPRINT', 'DOT4', 'SCSI', 'PCI', '1394')

# Imaging devices that are part of Windows or of a laptop's own hardware
# and must never be removed.
$script:ProtectedScannerNames = @(
    '*Integrated*Camera*'
    '*Integrated*Webcam*'
    '*HD*Camera*'
    '*IR Camera*'
    '*Windows Hello*'
    '*Virtual Camera*'
)

# ---------------------------------------------------------------------
# USER ALLOW-LIST FILE
#
# Techs pin their own keepers here so a personal home printer or a
# long-lived test queue survives every sweep without needing -Keep on
# each invocation. Stored per-user under APPDATA rather than beside the
# module so it is not lost when the profile repository is re-cloned.
# ---------------------------------------------------------------------
$script:AllowListFileName = 'allowlist.json'
$script:AllowListFolderName = 'Restart-PrintStack'
$script:AllowListSchemaVersion = 1

# ---------------------------------------------------------------------
# SPOOLER
#
# The spooler caches port handles: a port whose last queue was deleted
# moments ago can still report as in use. Bouncing the service releases
# the handles, so a failed port deletion is retried once after a
# restart rather than reported as an error the tech has to chase.
# ---------------------------------------------------------------------
$script:SpoolerServiceName = 'Spooler'
$script:SpoolerSettleSeconds = 3
$script:JobCancelTimeoutSeconds = 10

# ---------------------------------------------------------------------
# BACKUP
#
# A JSON snapshot of the inventory is written before anything is
# deleted. It records the port name, driver and address for every queue,
# which is everything needed to recreate one by hand in a few seconds.
# ---------------------------------------------------------------------
$script:BackupFolderPrefix = 'RestartPrintStack'

# ---------------------------------------------------------------------
# SESSION STATE
#
# Assigned at import so Set-StrictMode does not fault on a first read
# before assignment. Populated lazily at runtime.
# ---------------------------------------------------------------------
$script:PrintManagementAvailable = $null
