$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$destinationDir = Join-Path $terminalData "MQL5\Experts\GoldResearch"
$destination = Join-Path $destinationDir "TrendPullback.mq5"
$binary = [System.IO.Path]::ChangeExtension($destination, ".ex5")
$compiler = "C:\Program Files\MetaTrader 5\MetaEditor64.exe"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$compileLog = Join-Path $projectRoot "reports\compile-trend-pullback.log"
$runtimeConfig = Join-Path $projectRoot "reports\trend-pullback.runtime.ini"
$testerProfile = Join-Path $terminalData "MQL5\Profiles\Tester"

New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
New-Item -ItemType Directory -Path $testerProfile -Force | Out-Null
Copy-Item (Join-Path $projectRoot "mql5\Experts\GoldResearch\TrendPullback.mq5") $destination -Force
Copy-Item (Join-Path $projectRoot "config\trend-pullback.set") `
    (Join-Path $testerProfile "trend-pullback.set") -Force

Start-Process $compiler -ArgumentList @("/compile:$destination", "/log:$compileLog") -Wait
$compileOutput = Get-Content $compileLog -Raw
Write-Output $compileOutput
if ($compileOutput -notmatch "Result:\s+0 errors, 0 warnings" -or -not (Test-Path $binary)) {
    throw "MQL5 compilation failed"
}

$config = Get-Content (Join-Path $projectRoot "config\trend-pullback.ini") -Raw
$config = $config -replace '(?m)^Report=.*$', "Report=TrendPullback.html"
Set-Content $runtimeConfig $config -Encoding ascii
Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3
$test = Start-Process $terminal -ArgumentList "/config:$runtimeConfig" -Wait -PassThru
Write-Output "Terminal exit code: $($test.ExitCode)"

$agentLog = Get-ChildItem (Join-Path $env:APPDATA "MetaQuotes\Tester") -Filter "*.log" -Recurse |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$archive = Join-Path $projectRoot "reports\TrendPullback-agent.log"
Copy-Item $agentLog.FullName $archive -Force
$all = Get-Content $agentLog.FullName
$evidence = $all | Where-Object {
    $_ -match "generating based on real ticks" -or $_ -match "TPB\|entry" -or
    $_ -match "TPB\|tester_summary" -or $_ -match "ticks, .* bars generated"
} | Select-Object -Last 30
$evidence | Write-Output
if (-not ($all -match "generating based on real ticks") -or -not ($all -match "TPB\|tester_summary")) {
    throw "Trend pullback validation failed"
}
