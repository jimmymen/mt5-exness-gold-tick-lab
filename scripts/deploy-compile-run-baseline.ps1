$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$source = Join-Path $projectRoot "mql5\Experts\GoldResearch\AsiaLondonBreakout.mq5"
$destinationDir = Join-Path $terminalData "MQL5\Experts\GoldResearch"
$destination = Join-Path $destinationDir "AsiaLondonBreakout.mq5"
$binary = [System.IO.Path]::ChangeExtension($destination, ".ex5")
$compiler = "C:\Program Files\MetaTrader 5\MetaEditor64.exe"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$compileLog = Join-Path $projectRoot "reports\compile-asia-london.log"
$runtimeConfig = Join-Path $projectRoot "reports\asia-london.runtime.ini"
$report = Join-Path $projectRoot "reports\AsiaLondonBaseline.html"
$testerProfile = Join-Path $terminalData "MQL5\Profiles\Tester"

New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
New-Item -ItemType Directory -Path $testerProfile -Force | Out-Null
Copy-Item -LiteralPath $source -Destination $destination -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "config\asia-london-baseline.set") `
    -Destination (Join-Path $testerProfile "asia-london-baseline.set") -Force

$compileProcess = Start-Process -FilePath $compiler -ArgumentList @(
    "/compile:$destination",
    "/log:$compileLog"
) -Wait -PassThru
$log = Get-Content -LiteralPath $compileLog -Raw
Write-Output $log
if ($log -notmatch "Result:\s+0 errors, 0 warnings" -or -not (Test-Path -LiteralPath $binary)) {
    throw "MQL5 compilation failed"
}

$config = Get-Content -LiteralPath (Join-Path $projectRoot "config\asia-london-baseline.ini") -Raw
$config = $config -replace '(?m)^Report=.*$', "Report=$report"
Set-Content -LiteralPath $runtimeConfig -Value $config -Encoding ascii

Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
$testProcess = Start-Process -FilePath $terminal -ArgumentList "/config:$runtimeConfig" -PassThru -Wait
Write-Output "Terminal exit code: $($testProcess.ExitCode)"

$agentLog = Get-ChildItem (Join-Path $env:APPDATA "MetaQuotes\Tester") -Filter "*.log" -Recurse |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
Copy-Item -LiteralPath $agentLog.FullName -Destination (Join-Path $projectRoot "reports\AsiaLondonBaseline-agent.log") -Force

$evidence = Get-Content -LiteralPath $agentLog.FullName |
    Where-Object {
        $_ -match "generating based on real ticks" -or
        $_ -match "ALB\|entry" -or
        $_ -match "ALB\|tester_summary" -or
        $_ -match "final balance" -or
        $_ -match "ticks, .* bars generated"
    } |
    Select-Object -Last 30
$evidence | Write-Output

$fullAgentLog = Get-Content -LiteralPath $agentLog.FullName
if (-not ($fullAgentLog -match "generating based on real ticks")) {
    throw "Baseline test did not use real ticks"
}
if (-not ($evidence -match "ALB\|tester_summary")) {
    throw "Baseline test did not produce machine-readable tester statistics"
}
if (Test-Path -LiteralPath $report) {
    Write-Output "Report: $report"
} else {
    Write-Output "No HTML report emitted; native agent log and tester summary archived."
}
