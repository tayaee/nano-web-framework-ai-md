param(
    [int]$Start = 18080
)

for ($p = $Start; $p -lt $Start + 100; $p++) {
    $inUse = $true
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        # Plain Connect() blocks up to the OS default (~21s on Windows) when a
        # firewall/AV silently drops the SYN instead of refusing it, instead of
        # failing fast -- with 100 ports to probe that can look like a hang.
        # BeginConnect + a short WaitOne bounds each probe to 300ms.
        $result = $client.BeginConnect("127.0.0.1", $p, $null, $null)
        $connected = $result.AsyncWaitHandle.WaitOne(300)
        if ($connected -and $client.Connected) {
            $client.EndConnect($result)
        } else {
            $inUse = $false
        }
    } catch {
        $inUse = $false
    } finally {
        $client.Close()
    }
    if (-not $inUse) {
        Write-Output $p
        exit 0
    }
}

Write-Error "no free port found in range $Start-$($Start + 99)"
exit 1
