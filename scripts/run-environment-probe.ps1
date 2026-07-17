$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$sourceConfig = Join-Path $projectRoot "config\environment-probe.ini"
$sourceParameters = Join-Path $projectRoot "config\environment-probe.set"
$testerProfile = Join-Path $terminalData "MQL5\Profiles\Tester"
$runtimeConfig = Join-Path $projectRoot "reports\environment-probe.runtime.ini"
$report = Join-Path $projectRoot "reports\EnvironmentProbe-RealTicks.html"
$stdoutLog = Join-Path $projectRoot "reports\terminal-run.log"
$stderrLog = Join-Path $projectRoot "reports\terminal-run-error.log"
$archivedAgentLog = Join-Path $projectRoot "reports\EnvironmentProbe-agent.log"

New-Item -ItemType Directory -Path $testerProfile -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $report) -Force | Out-Null
Copy-Item -LiteralPath $sourceParameters -Destination (Join-Path $testerProfile "environment-probe.set") -Force

$config = Get-Content -LiteralPath $sourceConfig -Raw
$config = $config -replace '(?m)^Report=.*$', "Report=$report"
Set-Content -LiteralPath $runtimeConfig -Value $config -Encoding ascii

Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

$process = Start-Process -FilePath $terminal -ArgumentList "/config:$runtimeConfig" -PassThru -Wait `
    -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog

Write-Output "Terminal exit code: $($process.ExitCode)"
$agentLog = Get-ChildItem (Join-Path $env:APPDATA "MetaQuotes\Tester") -Filter "*.log" -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $agentLog) {
    throw "MT5 did not produce an agent log"
}
Copy-Item -LiteralPath $agentLog.FullName -Destination $archivedAgentLog -Force

$evidence = Get-Content -LiteralPath $agentLog.FullName |
    Where-Object {
        $_ -match "generating based on real ticks" -or
        $_ -match "OnTester result" -or
        $_ -match "PROBE\|summary" -or
        $_ -match "ticks, .* bars generated"
    } |
    Select-Object -Last 4
$evidence | Write-Output

if (-not ($evidence -match "generating based on real ticks")) {
    throw "MT5 test did not confirm real tick modeling"
}
if (-not ($evidence -match "PROBE\|summary")) {
    throw "Environment probe did not complete"
}

if (Test-Path -LiteralPath $report) {
    $reportFile = Get-Item -LiteralPath $report
    Write-Output "Report: $($reportFile.FullName) ($($reportFile.Length) bytes)"
} else {
    Write-Output "No HTML report was emitted for this zero-trade diagnostic run; native agent log archived."
}
