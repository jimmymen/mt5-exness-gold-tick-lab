$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$source = Join-Path $projectRoot "mql5\Experts\GoldResearch\CustomTickAudit.mq5"
$destinationDir = Join-Path $terminalData "MQL5\Experts\GoldResearch"
$destination = Join-Path $destinationDir "CustomTickAudit.mq5"
$compiler = "C:\Program Files\MetaTrader 5\MetaEditor64.exe"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$compileLog = Join-Path $projectRoot "reports\compile-custom-tick-audit.log"
$runtimeConfig = Join-Path $projectRoot "reports\custom-tick-audit.runtime.ini"
$auditLog = Join-Path $projectRoot "reports\custom-tick-audit-terminal.log"

Copy-Item -LiteralPath $source -Destination $destination -Force
Start-Process $compiler -ArgumentList @("/compile:$destination", "/log:$compileLog") -Wait
$compileOutput = Get-Content $compileLog -Raw
Write-Output $compileOutput
if ($compileOutput -notmatch "Result:\s+0 errors, 0 warnings") {
    throw "Custom Tick audit compilation failed"
}
@"
[StartUp]
Expert=GoldResearch\CustomTickAudit.ex5
Symbol=XAUUSDm
Period=M1
"@ | Set-Content -LiteralPath $runtimeConfig -Encoding ascii

Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
$started = Get-Date
$process = Start-Process $terminal -ArgumentList "/config:$runtimeConfig" -PassThru
$deadline = (Get-Date).AddHours(2)
$evidence = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $log = Get-ChildItem (Join-Path $terminalData "MQL5\Logs") -Filter "*.log" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    $content = Get-Content -LiteralPath $log.FullName
    $evidence = $content | Where-Object { $_ -match "AUDIT\|summary" -or $_ -match "AUDIT\|fatal" } |
        Select-Object -Last 1
    if ($null -ne $evidence) {
        Copy-Item -LiteralPath $log.FullName -Destination $auditLog -Force
        break
    }
}
if ($null -eq $evidence -or $evidence -match "AUDIT\|fatal") {
    Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
    throw "Full custom Tick audit failed: $evidence"
}
Write-Output $evidence
