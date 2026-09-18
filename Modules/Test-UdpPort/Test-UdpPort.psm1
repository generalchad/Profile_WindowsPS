# Ports are the *query* port (where a probe elicits a response), not the game port.
# Palworld serves status over HTTP, not a UDP query, so it falls back to a bare probe.
$script:GameRegistry = @{
    Source         = @{ Port = 27015; Probe = 'valve' }
    Quake          = @{ Port = 27960; Probe = 'quake' }
    Minecraft      = @{ Port = 19132; Probe = 'minecraft' }
    Samp           = @{ Port = 7777;  Probe = 'samp' }
    Palworld       = @{ Port = 8211;  Probe = 'none' }
    Arma3          = @{ Port = 2303;  Probe = 'valve' }  # query = game port 2302 + 1
    ArmaReforger   = @{ Port = 17777; Probe = 'valve' }  # fixed query port, game is 2001
    Dragonwilds    = @{ Port = 27015; Probe = 'valve' }  # Steam/UE5; A2S assumed, unverified
    ProjectZomboid = @{ Port = 16261; Probe = 'valve' }
}

function Test-UdpPort {
    <#
    .SYNOPSIS
        Tests UDP connectivity to a target host and optional port.

    .DESCRIPTION
        UDP is connectionless, so this probes a target by sending a datagram and
        interpreting the result:
          - RESPONDED     -> data came back; the port is open and answering.
          - CLOSED        -> an ICMP "port unreachable" (WSAECONNRESET) came back.
          - OPEN/FILTERED -> no reply and no reset; reachable-but-silent or firewalled.

        Includes built-in game query packets and default query ports for common
        game servers, plus a raw payload override for arbitrary protocols.

    .PARAMETER ComputerName
        The target server FQDN or IP address.

    .PARAMETER Protocol
        A built-in game whose query packet and default port are used:
        Source, Quake, Minecraft, Samp, Palworld, Arma3, ArmaReforger,
        Dragonwilds, ProjectZomboid.

    .PARAMETER Port
        The UDP port to test. Required unless -Protocol supplies a default.

    .PARAMETER Payload
        A raw probe override. Interpreted as hex when it contains only hex pairs,
        otherwise sent as ASCII. Ignored when -Protocol is set.

    .PARAMETER Timeout
        The receive timeout in milliseconds. Defaults to 3000ms.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Hostname', 'Target')]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Source', 'Quake', 'Minecraft', 'Samp', 'Palworld', 'Arma3', 'ArmaReforger', 'Dragonwilds', 'ProjectZomboid')]
        [string]$Protocol,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(Mandatory = $false)]
        [string]$Payload,

        [Parameter(Mandatory = $false)]
        [ValidateRange(500, 30000)]
        [int]$Timeout = 3000
    )

    begin {
        if (-not $PSBoundParameters.ContainsKey('Port') -and -not $Protocol) {
            throw 'Either -Port or -Protocol is required.'
        }

        # Build a raw probe from -Payload when no protocol handles it.
        $RawPayload = $null
        if (-not $Protocol -and $PSBoundParameters.ContainsKey('Payload')) {
            $RawPayload = ConvertTo-ProbeBytes -Payload $Payload
        }
    }

    process {
        foreach ($Target in $ComputerName) {
            $ResolvedPort = if ($PSBoundParameters.ContainsKey('Port')) { $Port } else { $script:GameRegistry[$Protocol].Port }
            $ProbeType = if ($Protocol) { $script:GameRegistry[$Protocol].Probe } else { $null }

            try {
                $IPAddresses = [System.Net.Dns]::GetHostAddresses($Target)
                $IP = $IPAddresses[0].IPAddressToString
                Write-Verbose "Resolved $Target to $IP"
            } catch {
                Write-Error "DNS Resolution failed for '$Target'."
                [PSCustomObject]@{
                    ComputerName = $Target
                    IPAddress    = 'N/A'
                    Port         = $ResolvedPort
                    Protocol     = $Protocol
                    Status       = 'DNS_FAILED'
                    ResponseHex  = ''
                }
                continue
            }

            $ProbeBytes = if ($ProbeType) {
                Get-GameProbeBytes -Probe $ProbeType -IPAddress $IP -Port $ResolvedPort
            } else {
                $RawPayload
            }

            # A bare probe (no protocol, no payload) sends a zero-length datagram.
            if ($null -eq $ProbeBytes) { $ProbeBytes = [byte[]]@() }

            $Status = 'OPEN/FILTERED'
            $ResponseHex = ''

            $udp = $null
            try {
                $udp = [System.Net.Sockets.UdpClient]::new()
                $udp.Connect($IP, $ResolvedPort)
                $udp.Client.ReceiveTimeout = $Timeout

                $null = $udp.Send($ProbeBytes, $ProbeBytes.Length)

                $remoteEp = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
                $reply = $udp.Receive([ref]$remoteEp)

                $Status = 'RESPONDED'
                $ResponseHex = ($reply | ForEach-Object { $_.ToString('X2') }) -join ' '
            } catch [System.Net.Sockets.SocketException] {
                # WSAECONNRESET is the ICMP "port unreachable" reply signalling a closed port.
                if ($_.Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::ConnectionReset) {
                    $Status = 'CLOSED'
                } elseif ($_.Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::TimedOut) {
                    $Status = 'OPEN/FILTERED'
                } else {
                    $Status = "ERROR_$($_.Exception.SocketErrorCode)"
                }
            } catch {
                $Status = 'ERROR'
            } finally {
                if ($udp) { $udp.Close(); $udp.Dispose() }
            }

            [PSCustomObject]@{
                ComputerName = $Target
                IPAddress    = $IP
                Port         = $ResolvedPort
                Protocol     = $Protocol
                Status       = $Status
                ResponseHex  = $ResponseHex
            }
        }
    }
}

function Get-GameProbeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Probe,

        [Parameter(Mandatory = $false)]
        [string]$IPAddress,

        [Parameter(Mandatory = $false)]
        [int]$Port
    )

    switch ($Probe) {
        'valve' {
            # A2S_INFO: 4x FF header + "TSource Engine Query" + NUL. Answers on any
            # Steam-enabled server, so one packet covers Source, Arma 3/Reforger,
            # Project Zomboid and any Steam-distributed UE title.
            return [byte[]](0xFF, 0xFF, 0xFF, 0xFF, 0x54) +
                [System.Text.Encoding]::ASCII.GetBytes('Source Engine Query') +
                [byte[]]0x00
        }
        'quake' {
            # Q3 getstatus: 4x FF header + "getstatus" + LF.
            return [byte[]](0xFF, 0xFF, 0xFF, 0xFF) +
                [System.Text.Encoding]::ASCII.GetBytes("getstatus`n")
        }
        'minecraft' {
            # Bedrock RakNet unconnected ping: id, ping time, magic, client GUID.
            $magic = [byte[]](0x00, 0xFF, 0xFF, 0x00, 0xFE, 0xFE, 0xFE, 0xFE, 0xFD, 0xFD, 0xFD, 0xFD, 0x12, 0x34, 0x56, 0x78)
            $guid  = [byte[]](0, 0, 0, 0, 0, 0, 0, 0)
            return [byte[]]0x01 + [byte[]](0, 0, 0, 0, 0, 0, 0, 0) + $magic + $guid
        }
        'samp' {
            # SA-MP info query: "SAMP" + reversed IPv4 octets + LE port + opcode 'i'.
            $octets = @($IPAddress -split '\.' | ForEach-Object { [byte]$_ })
            [array]::Reverse($octets)
            $portBytes = [System.BitConverter]::GetBytes([uint16]$Port)
            return [System.Text.Encoding]::ASCII.GetBytes('SAMP') +
                [byte[]]$octets +
                $portBytes +
                [byte[]]0x69
        }
        'none' {
            return [byte[]]@()
        }
    }
}

function ConvertTo-ProbeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Payload
    )

    $trimmed = $Payload -replace '[\s:-]', ''
    if ($trimmed -match '^[0-9A-Fa-f]*$' -and $trimmed.Length -gt 0 -and ($trimmed.Length % 2) -eq 0) {
        $bytes = for ($i = 0; $i -lt $trimmed.Length; $i += 2) {
            [Convert]::ToByte($trimmed.Substring($i, 2), 16)
        }
        return [byte[]]$bytes
    }
    return [System.Text.Encoding]::ASCII.GetBytes($Payload)
}

Set-Alias -Name 'Test-Udp' -Value 'Test-UdpPort'

Export-ModuleMember -Function 'Test-UdpPort' -Alias 'Test-Udp'
