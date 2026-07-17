$ErrorActionPreference = "Stop"

$testerTicks = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester\D0E8209F77C8CF37AD8BF550E51FF075\bases\Exness-MT5Real5\ticks\XAUUSDm"
$terminalTicks = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\bases\Exness-MT5Real5\ticks\XAUUSDm"

foreach ($entry in @(
    @{ Name = "Tester"; Path = $testerTicks },
    @{ Name = "Terminal"; Path = $terminalTicks }
)) {
    Write-Output "=== $($entry.Name) ==="
    Write-Output $entry.Path
    if (-not (Test-Path -LiteralPath $entry.Path)) {
        Write-Output "MISSING"
        continue
    }

    $files = Get-ChildItem -LiteralPath $entry.Path -File -Recurse | Sort-Object FullName
    $total = ($files | Measure-Object Length -Sum).Sum
    Write-Output "Files: $($files.Count)"
    Write-Output "Bytes: $total"
    Write-Output "MiB: $([math]::Round($total / 1MB, 3))"
    $files | Select-Object FullName, Length, CreationTime, LastWriteTime | Format-Table -AutoSize

    Write-Output "--- HEADERS ---"
    foreach ($file in $files) {
        $stream = [IO.File]::OpenRead($file.FullName)
        try {
            $buffer = New-Object byte[] 64
            $count = $stream.Read($buffer, 0, $buffer.Length)
            $hex = -join ($buffer[0..($count - 1)] | ForEach-Object { $_.ToString("X2") })
            Write-Output "$($file.Name)|$($file.Length)|$hex"
        } finally {
            $stream.Dispose()
        }
    }
}
