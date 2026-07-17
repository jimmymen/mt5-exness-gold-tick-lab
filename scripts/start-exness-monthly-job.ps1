$ErrorActionPreference = "Stop"

$root = "C:\QuantResearch\tick-data\exness\XAUUSDm"
$runner = "C:\QuantResearch\mt5-gold-research\scripts\run-exness-monthly-job.cmd"
$taskName = "MT5 Gold Research - Exness Monthly Ticks"

Remove-Item `
    (Join-Path $root "monthly.stdout.log"), `
    (Join-Path $root "monthly.stderr.log") `
    -Force `
    -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute $runner
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Days 7) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Settings $settings `
    -Principal $principal `
    -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output $taskName
