$ErrorActionPreference = "Stop"

$root = "C:\QuantResearch\tick-data\exness\XAUUSDm"
$runner = "C:\QuantResearch\mt5-gold-research\scripts\run-exness-archive-job.cmd"
$taskName = "MT5 Gold Research - Exness Tick Archives"

New-Item -ItemType Directory -Force -Path $root | Out-Null
$stdout = Join-Path $root "processor.stdout.log"
$stderr = Join-Path $root "processor.stderr.log"
Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute $runner
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Days 7) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Settings $settings `
    -Principal $principal `
    -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output $taskName
