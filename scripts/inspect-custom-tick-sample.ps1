$ErrorActionPreference = "Stop"

$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$log = Get-ChildItem (Join-Path $terminalData "MQL5\Logs") -Filter "*.log" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
Write-Output "LOG=$($log.FullName)"
Get-Content -LiteralPath $log.FullName |
    Where-Object { $_ -match "IMPORT\|" } |
    Select-Object -Last 20
Get-ChildItem (Join-Path $terminalData "bases\Custom") -Recurse -File |
    Select-Object FullName, Length, LastWriteTime
Get-Process terminal64 -ErrorAction SilentlyContinue |
    Select-Object Id, SessionId, CPU, StartTime
