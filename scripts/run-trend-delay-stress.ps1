$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$config = Get-Content (Join-Path $projectRoot "config\trend-pullback.ini") -Raw
$config = $config -replace '(?m)^ExecutionMode=.*$', 'ExecutionMode=-1'
$config = $config -replace '(?m)^Report=.*$', 'Report=TrendPullback-RandomDelay.html'
$runtime = Join-Path $projectRoot "reports\trend-pullback-random-delay.ini"
Set-Content $runtime $config -Encoding ascii

Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3
$test = Start-Process $terminal -ArgumentList "/config:$runtime" -Wait -PassThru
Write-Output "Terminal exit code: $($test.ExitCode)"

$agentLog = Get-ChildItem (Join-Path $env:APPDATA "MetaQuotes\Tester") -Filter "*.log" -Recurse |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$archive = Join-Path $projectRoot "reports\TrendPullback-RandomDelay-agent.log"
Copy-Item $agentLog.FullName $archive -Force
$all = Get-Content $agentLog.FullName
$summary = $all | Where-Object { $_ -match "TPB\|tester_summary" } | Select-Object -Last 1
$delay = $all | Where-Object { $_ -match "delay" } | Select-Object -First 5
$delay | Write-Output
$summary | Write-Output
if (-not ($all -match "generating based on real ticks") -or [string]::IsNullOrWhiteSpace($summary)) {
    throw "Random-delay stress test failed"
}
