$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$testerProfile = Join-Path $terminalData "MQL5\Profiles\Tester"
$runtimeConfig = Join-Path $projectRoot "reports\trend-pullback-custom.runtime.ini"
$reportName = "TrendPullback-CustomTicks"
$report = Join-Path $projectRoot "reports\TrendPullback-CustomTicks.html"
$agentArchive = Join-Path $projectRoot "reports\TrendPullback-CustomTicks-agent.log"

New-Item -ItemType Directory -Path $testerProfile -Force | Out-Null
Copy-Item `
    (Join-Path $projectRoot "config\trend-pullback.set") `
    (Join-Path $testerProfile "trend-pullback.set") `
    -Force
$config = Get-Content (Join-Path $projectRoot "config\trend-pullback-custom.ini") -Raw
$config = $config -replace '(?m)^Report=.*$', "Report=$reportName"
Set-Content -LiteralPath $runtimeConfig -Value $config -Encoding ascii

Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
$test = Start-Process $terminal -ArgumentList "/config:$runtimeConfig" -Wait -PassThru
Write-Output "Terminal exit code: $($test.ExitCode)"
$agentLog = Get-ChildItem (Join-Path $env:APPDATA "MetaQuotes\Tester") -Filter "*.log" -Recurse |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $agentLog) {
    throw "MT5 did not produce an agent log"
}
Copy-Item -LiteralPath $agentLog.FullName -Destination $agentArchive -Force
$all = Get-Content -LiteralPath $agentLog.FullName
$evidence = $all | Where-Object {
    $_ -match "generating based on real ticks" -or
    $_ -match "TPB\|tester_summary" -or
    $_ -match "ticks, .* bars generated"
}
$evidence | Select-Object -Last 20 | Write-Output
if (-not ($all -match "generating based on real ticks")) {
    throw "TrendPullback custom-symbol test did not use real Tick modeling"
}
if ($all -match "every tick generation used") {
    throw "TrendPullback custom-symbol test fell back to generated Ticks"
}
if (-not ($all -match "TPB\|tester_summary")) {
    throw "TrendPullback did not emit its tester summary"
}
$generated = Get-ChildItem `
    (Split-Path $terminal), `
    $terminalData, `
    $projectRoot `
    -Filter "TrendPullback-CustomTicks*.htm*" `
    -Recurse `
    -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $generated) {
    Write-Output "MT5 did not emit an HTML report; native agent log is authoritative."
} else {
    Copy-Item -LiteralPath $generated.FullName -Destination $report -Force
    Write-Output "Report: $report"
}
