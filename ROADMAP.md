# Roadmap

Planned modules not yet built. Each follows the repo conventions in `AGENTS.md`:
self-contained (private helpers copied, not shared), PowerShell 7, structured
object output, `ShouldProcess` on anything that changes state.

## Get-NetworkDiagnostics

One-shot network triage for an unfamiliar site, emitting a single report object
that can be exported for a ticket.

- Adapters: name, status, link speed, MAC, IPv4/IPv6, DHCP vs static, lease times.
- Gateway and DNS servers per adapter; resolution tests against internal and
  public names, and against each configured DNS server individually.
- Reachability: gateway, a public anycast address, and a configurable target
  (ICMP is often blocked, so also test TCP 443).
- Public IP and whether traffic is leaving via a proxy, VPN, or Tailscale exit node.
- WinHTTP/WinINET proxy settings and hosts-file overrides.
- Output: one `PSCustomObject` with nested sections; `-AsHtml`/`-Path` to export.

Open questions: whether to include a traceroute (slow) behind a switch; which
public targets to default to.

## Find-NetworkDevice

Subnet sweep to locate devices (typically the copier) on a network you don't
know.

- Defaults to the local subnet(s) of active adapters; `-Subnet 192.168.1.0/24`
  to override.
- Parallel ping sweep, then ARP table for MAC addresses, then OUI lookup for the
  vendor (bundled offline OUI subset so it works without internet).
- Optional common-port probe (80, 443, 445, 515, 631, 9100, 161/udp) to flag
  likely printers.
- Pipes directly into `Get-PrinterInfo` for anything with SNMP open.
- Throttle and timeout parameters; results sorted by IP.

Open questions: size of the bundled OUI list; whether to fall back to reverse
DNS/NetBIOS names.

## Export-SiteReport

Collects the other modules' output into one document for a job ticket.

- Machine: `Get-WindowsInstallInfo` (OS, build, install date, hardware).
- Printing: `Get-PrintStackInventory -AsObject` and `Get-PrinterInfo` for
  network printers found.
- Network: `Get-NetworkDiagnostics`.
- Output: a single self-contained HTML file (and optional JSON) with a
  timestamped name in a chosen folder.
- Each section degrades gracefully when its source module is unavailable.

Depends on: Get-NetworkDiagnostics (and benefits from Find-NetworkDevice).
