$ErrorActionPreference = "Stop"

$taskName = "MT5 Gold Research - Development Dashboard"
$runner = "C:\QuantResearch\mt5-gold-research\scripts\run-development-dashboard-server.cmd"
$action = New-ScheduledTaskAction -Execute $runner
$principal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 10 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output "Dashboard: http://127.0.0.1:8765/development-dashboard.html"
