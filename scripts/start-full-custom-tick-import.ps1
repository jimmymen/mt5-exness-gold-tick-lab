$ErrorActionPreference = "Stop"

$taskName = "MT5 Gold Research - Full Custom Tick Import"
$script = "C:\QuantResearch\mt5-gold-research\scripts\run-full-custom-tick-import.ps1"
$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$log = "C:\QuantResearch\mt5-gold-research\reports\full-custom-tick-import-task.log"
$wrapper = "C:\QuantResearch\mt5-gold-research\reports\run-full-custom-tick-import-task.cmd"

@"
@echo off
"$powershell" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$script" 1>"$log" 2>&1
"@ | Set-Content -LiteralPath $wrapper -Encoding ascii
$action = New-ScheduledTaskAction -Execute $wrapper
$principal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Days 7) `
    -RestartCount 1 `
    -RestartInterval (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output $taskName
