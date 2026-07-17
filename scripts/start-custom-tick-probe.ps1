$ErrorActionPreference = "Stop"

$taskName = "MT5 Gold Research - Custom Tick Probe"
$script = "C:\QuantResearch\mt5-gold-research\scripts\run-custom-tick-probe.ps1"
$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$stdout = "C:\QuantResearch\mt5-gold-research\reports\custom-tick-probe-task.log"
$wrapper = "C:\QuantResearch\mt5-gold-research\reports\run-custom-tick-probe-task.cmd"

@"
@echo off
"$powershell" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$script" 1>"$stdout" 2>&1
"@ | Set-Content -LiteralPath $wrapper -Encoding ascii
$action = New-ScheduledTaskAction -Execute $wrapper
$principal = New-ScheduledTaskPrincipal `
    -UserId "Administrator" `
    -LogonType Interactive `
    -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -StartWhenAvailable
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output $taskName
