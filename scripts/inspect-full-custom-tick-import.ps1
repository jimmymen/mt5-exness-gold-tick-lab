$ErrorActionPreference = "Stop"

$taskName = "MT5 Gold Research - Full Custom Tick Import"
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$status = "C:\QuantResearch\tick-data\exness\XAUUSDm\mt5-full-import-status.json"
$taskLog = "C:\QuantResearch\mt5-gold-research\reports\full-custom-tick-import-task.log"
$preset = Join-Path $terminalData "MQL5\Presets\custom-tick-full-import.set"

Get-ScheduledTask -TaskName $taskName | Select-Object State
Get-ScheduledTaskInfo -TaskName $taskName | Select-Object LastRunTime, LastTaskResult
Write-Output "STATUS"
Get-Content -LiteralPath $status -ErrorAction SilentlyContinue
Write-Output "TASK LOG"
Get-Content -LiteralPath $taskLog -ErrorAction SilentlyContinue | Select-Object -Last 80
Write-Output "PRESET"
Get-Content -LiteralPath $preset -ErrorAction SilentlyContinue
Write-Output "IMPORT LOG"
$log = Get-ChildItem (Join-Path $terminalData "MQL5\Logs") -Filter "*.log" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
Get-Content -LiteralPath $log.FullName |
    Where-Object { $_ -match "IMPORT\|" } |
    Select-Object -Last 30
Get-Process terminal64 -ErrorAction SilentlyContinue |
    Select-Object Id, SessionId, CPU, WorkingSet64, StartTime
Get-PSDrive C | Select-Object Used, Free
