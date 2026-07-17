$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$source = Join-Path $projectRoot "mql5\Experts\GoldResearch\EnvironmentProbe.mq5"
$destinationDir = Join-Path $terminalData "MQL5\Experts\GoldResearch"
$destination = Join-Path $destinationDir "EnvironmentProbe.mq5"
$compiler = "C:\Program Files\MetaTrader 5\MetaEditor64.exe"
$compileLog = Join-Path $projectRoot "reports\compile-environment-probe.log"

New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $compileLog) -Force | Out-Null
Copy-Item -LiteralPath $source -Destination $destination -Force

$process = Start-Process -FilePath $compiler -ArgumentList @(
    "/compile:$destination",
    "/log:$compileLog"
) -Wait -PassThru

$log = Get-Content -LiteralPath $compileLog -Raw
Write-Output $log
$binary = [System.IO.Path]::ChangeExtension($destination, ".ex5")
if ($log -notmatch "Result:\s+0 errors, 0 warnings" -or -not (Test-Path -LiteralPath $binary)) {
    throw "MQL5 compilation failed"
}

Write-Output "Compiled: $binary"
