# Minimal SNMP v1/v2c GET client over UDP. Implemented in-module because Windows
# ships no SNMP client cmdlets and the module must work on a technician laptop
# with nothing extra installed. Only what a GET needs is encoded/decoded.

function ConvertTo-BerLength {
    [OutputType([byte[]])]
    param([int]$Length)

    if ($Length -lt 0x80) { return [byte[]]@($Length) }
    $bytes = [System.Collections.Generic.List[byte]]::new()
    while ($Length -gt 0) { $bytes.Insert(0, [byte]($Length -band 0xFF)); $Length = $Length -shr 8 }
    return [byte[]](@([byte](0x80 -bor $bytes.Count)) + $bytes)
}

function ConvertTo-BerTlv {
    [OutputType([byte[]])]
    param([byte]$Tag, [byte[]]$Value)

    if ($null -eq $Value) { $Value = [byte[]]@() }
    return [byte[]](@($Tag) + (ConvertTo-BerLength $Value.Length) + $Value)
}

function ConvertTo-BerInteger {
    [OutputType([byte[]])]
    param([long]$Value)

    $bytes = [System.Collections.Generic.List[byte]]::new()
    do {
        $bytes.Insert(0, [byte]($Value -band 0xFF))
        $Value = $Value -shr 8
    } while ($Value -ne 0 -and $Value -ne -1)
    # Two's complement: a positive value whose top bit is set needs a 0x00 pad.
    if ($bytes[0] -band 0x80 -and $Value -eq 0) { $bytes.Insert(0, 0) }
    return ConvertTo-BerTlv -Tag 0x02 -Value $bytes.ToArray()
}

function ConvertTo-BerOid {
    [OutputType([byte[]])]
    param([string]$Oid)

    $parts = [long[]]($Oid.TrimStart('.') -split '\.')
    $bytes = [System.Collections.Generic.List[byte]]::new()
    $bytes.Add([byte](40 * $parts[0] + $parts[1]))
    foreach ($arc in $parts[2..($parts.Count - 1)]) {
        # Base-128, high bit set on every byte except the last.
        $chunk = [System.Collections.Generic.List[byte]]::new()
        $chunk.Insert(0, [byte]($arc -band 0x7F))
        $arc = $arc -shr 7
        while ($arc -gt 0) { $chunk.Insert(0, [byte](($arc -band 0x7F) -bor 0x80)); $arc = $arc -shr 7 }
        $bytes.AddRange($chunk)
    }
    return ConvertTo-BerTlv -Tag 0x06 -Value $bytes.ToArray()
}

function Read-BerTlv {
    # Returns @{ Tag; Value (byte[]); Next (offset after this TLV) }.
    param([byte[]]$Data, [int]$Offset)

    $tag = $Data[$Offset]
    $len = [int]$Data[$Offset + 1]
    $pos = $Offset + 2
    if ($len -band 0x80) {
        $count = $len -band 0x7F
        $len = 0
        for ($i = 0; $i -lt $count; $i++) { $len = ($len -shl 8) -bor $Data[$pos + $i] }
        $pos += $count
    }
    $value = if ($len -gt 0) { [byte[]]$Data[$pos..($pos + $len - 1)] } else { [byte[]]@() }
    @{ Tag = $tag; Value = $value; Next = $pos + $len }
}

function ConvertFrom-BerOid {
    param([byte[]]$Value)

    $arcs = [System.Collections.Generic.List[string]]::new()
    $arcs.Add([string][math]::Floor($Value[0] / 40))
    $arcs.Add([string]($Value[0] % 40))
    [long]$acc = 0
    for ($i = 1; $i -lt $Value.Length; $i++) {
        $acc = ($acc -shl 7) -bor ($Value[$i] -band 0x7F)
        if (-not ($Value[$i] -band 0x80)) { $arcs.Add([string]$acc); $acc = 0 }
    }
    $arcs -join '.'
}

function ConvertFrom-BerValue {
    param([byte]$Tag, [byte[]]$Value)

    switch ($Tag) {
        # INTEGER is signed; Counter32 (0x41), Gauge32 (0x42), TimeTicks (0x43) are unsigned.
        0x02 {
            [long]$n = if ($Value.Length -and ($Value[0] -band 0x80)) { -1 } else { 0 }
            foreach ($b in $Value) { $n = ($n -shl 8) -bor $b }
            return $n
        }
        { $_ -in 0x41, 0x42, 0x43, 0x46 } {
            [ulong]$n = 0
            foreach ($b in $Value) { $n = ($n -shl 8) -bor $b }
            return $n
        }
        0x04 {
            # Printers pad strings with NULs and trailing whitespace.
            return ([System.Text.Encoding]::UTF8.GetString($Value) -replace "`0", '').Trim()
        }
        0x06 { return ConvertFrom-BerOid $Value }
        0x40 { return ($Value | ForEach-Object { $_ }) -join '.' }
        # noSuchObject / noSuchInstance / endOfMibView / NULL: the OID has no value.
        { $_ -in 0x05, 0x80, 0x81, 0x82 } { return $null }
        default { return $Value }
    }
}

function Invoke-SnmpGet {
    <#
    .SYNOPSIS
        Sends one SNMP GET for a set of OIDs and returns an OID -> value hashtable.
    .DESCRIPTION
        Throws on timeout or a non-zero SNMP error status so callers can report the
        device as unreachable rather than silently returning an empty result.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$Address,
        [Parameter(Mandatory)] [string[]]$Oid,
        [string]$Community = 'public',
        [ValidateSet('1', '2c')] [string]$Version = '2c',
        [int]$Port = 161,
        [int]$Timeout = 2000
    )

    $varBinds = foreach ($o in $Oid) {
        ConvertTo-BerTlv -Tag 0x30 -Value ([byte[]]((ConvertTo-BerOid $o) + (ConvertTo-BerTlv -Tag 0x05 -Value @())))
    }
    $requestId = Get-Random -Minimum 1 -Maximum 0x7FFFFFFF
    $pdu = ConvertTo-BerTlv -Tag 0xA0 -Value ([byte[]](
            (ConvertTo-BerInteger $requestId) +
            (ConvertTo-BerInteger 0) +
            (ConvertTo-BerInteger 0) +
            (ConvertTo-BerTlv -Tag 0x30 -Value ([byte[]]($varBinds | ForEach-Object { $_ })))))
    $versionNumber = if ($Version -eq '1') { 0 } else { 1 }
    $message = ConvertTo-BerTlv -Tag 0x30 -Value ([byte[]](
            (ConvertTo-BerInteger $versionNumber) +
            (ConvertTo-BerTlv -Tag 0x04 -Value ([System.Text.Encoding]::ASCII.GetBytes($Community))) +
            $pdu))

    $udp = [System.Net.Sockets.UdpClient]::new()
    try {
        $udp.Client.ReceiveTimeout = $Timeout
        $udp.Connect($Address, $Port)
        $null = $udp.Send($message, $message.Length)
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        $reply = $udp.Receive([ref]$remote)
    }
    finally {
        $udp.Dispose()
    }

    $msg = Read-BerTlv $reply 0
    $ver = Read-BerTlv $msg.Value 0
    $comm = Read-BerTlv $msg.Value $ver.Next
    $resp = Read-BerTlv $msg.Value $comm.Next
    $rid = Read-BerTlv $resp.Value 0
    $status = Read-BerTlv $resp.Value $rid.Next
    $index = Read-BerTlv $resp.Value $status.Next
    $list = Read-BerTlv $resp.Value $index.Next

    $errorStatus = ConvertFrom-BerValue $status.Tag $status.Value
    if ($errorStatus -ne 0) {
        # v1 fails the whole request if any OID is missing (noSuchName = 2); the
        # caller retries per-OID in that case.
        throw [System.InvalidOperationException]::new("SNMP error-status $errorStatus")
    }

    $result = @{}
    $offset = 0
    while ($offset -lt $list.Value.Length) {
        $vb = Read-BerTlv $list.Value $offset
        $name = Read-BerTlv $vb.Value 0
        $val = Read-BerTlv $vb.Value $name.Next
        $result[(ConvertFrom-BerOid $name.Value)] = ConvertFrom-BerValue $val.Tag $val.Value
        $offset = $vb.Next
    }
    $result
}
