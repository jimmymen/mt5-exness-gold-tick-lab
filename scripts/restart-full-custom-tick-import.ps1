$ErrorActionPreference = "Stop"

$taskName = "MT5 Gold Research - Full Custom Tick Import"
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
& "C:\QuantResearch\mt5-gold-research\scripts\start-full-custom-tick-import.ps1"
