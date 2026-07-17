$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$testerProfile = Join-Path $terminalData "MQL5\Profiles\Tester"
$runtimeConfig = Join-Path $projectRoot "reports\environment-probe-custom.runtime.ini"
$report = Join-Path $projectRoot "reports\EnvironmentProbe-CustomTicks.html"
$agentArchive = Join-Path $projectRoot "reports\EnvironmentProbe-CustomTicks-agent.log"

New-Item -ItemType Directory -Path $testerProfile -Force | Out-Null
Copy-Item `
    (Join-Path $projectRoot "config\environment-probe-custom.set") `
    (Join-Path $testerProfile "environment-probe-custom.set") `
    -Force
$config = Get-Content (Join-Path $projectRoot "config\environment-probe-custom.ini") -Raw
$config = $config -replace '(?m)^Report=.*$', "Report=$report"
Set-Content -LiteralPath $runtimeConfig -Value $config -Encoding ascii

$started = Get-Date
$test = Start-Process $terminal -ArgumentList "/config:$runtimeConfig" -Wait -PassThru
Write-Output "Terminal exit code: $($test.ExitCode)"
$agentLog = Get-ChildItem (Join-Path $env:APPDATA "MetaQuotes\Tester") -Filter "*.log" -Recurse |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $agentLog) {
    throw "MT5 did not produce a new agent log"
}
Copy-Item -LiteralPath $agentLog.FullName -Destination $agentArchive -Force
$all = Get-Content -LiteralPath $agentLog.FullName
$evidence = $all | Where-Object {
    $_ -match "generating based on real ticks" -or
    $_ -match "PROBE\|summary" -or
    $_ -match "ticks, .* bars generated"
}
$evidence | Select-Object -Last 10 | Write-Output
if (-not ($all -match "generating based on real ticks")) {
    throw "Custom symbol test did not use real Tick modeling"
}
if ($all -match "every tick generation used") {
    throw "Custom symbol test fell back to generated Ticks"
}
$summary = $all | Where-Object { $_ -match "PROBE\|summary" } | Select-Object -Last 1
if ($summary -notmatch "ticks=(\d+)" -or [long]$Matches[1] -le 0) {
    throw "Custom symbol tester did not process imported Ticks"
}
