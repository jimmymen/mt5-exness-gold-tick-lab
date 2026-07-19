$ErrorActionPreference = "Stop"

$taskName = "MT5 Gold Research - Continuous Worker"
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskName $taskName
Write-Output $taskName
