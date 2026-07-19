$ErrorActionPreference = "Stop"

$root = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\GoldResearch\Parity"
foreach ($name in "auto-summary.csv", "auto-daily.csv", "auto-deals.csv") {
    $path = Join-Path $root $name
    Write-Output "=== $name ==="
    Get-Content -LiteralPath $path
}
Write-Output "=== hashes ==="
Get-FileHash (Join-Path $root "auto-*.csv") -Algorithm SHA256 |
    Select-Object Path, Hash
