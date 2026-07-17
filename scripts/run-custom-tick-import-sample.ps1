$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$commonFiles = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\GoldResearch"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$python = "C:\Tools\Python312\python.exe"
$archive = "C:\QuantResearch\tick-data\exness\XAUUSDm\mt5-import-monthly\Exness_XAUUSDm_2021_MT5_UTC.zip"
$sample = Join-Path $commonFiles "Exness_XAUUSDm_sample_MT5_UTC.csv"
$runtimeConfig = Join-Path $projectRoot "reports\custom-tick-importer.runtime.ini"
$terminalLog = Join-Path $projectRoot "reports\custom-tick-importer-terminal.log"

New-Item -ItemType Directory -Path $commonFiles -Force | Out-Null
& $python (Join-Path $projectRoot "tools\extract_mt5_tick_sample.py") `
    --archive $archive `
    --start-date "2021.01.03" `
    --end-date "2021.01.06" `
    --probe-date "2021.01.05" `
    --expected-output (Join-Path $commonFiles "Exness_XAUUSDm_expected_probe_ticks.txt") `
    --output $sample
if ($LASTEXITCODE -ne 0) {
    throw "Sample extraction failed"
}
@"
[StartUp]
Expert=GoldResearch\CustomTickImporter.ex5
Symbol=XAUUSDm
Period=M1
"@ | Set-Content -LiteralPath $runtimeConfig -Encoding ascii

Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
$started = Get-Date
$process = Start-Process -FilePath $terminal -ArgumentList "/config:$runtimeConfig" -PassThru
$deadline = (Get-Date).AddMinutes(10)
$matched = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    $logs = Get-ChildItem (Join-Path $terminalData "MQL5\Logs") -Filter "*.log" |
        Where-Object LastWriteTime -ge $started |
        Sort-Object LastWriteTime -Descending
    foreach ($log in $logs) {
        $content = Get-Content -LiteralPath $log.FullName
        if ($content -match "IMPORT\|summary\|symbol=XAUUSDm_EXNESS_V2") {
            $matched = $log
            break
        }
    }
    if ($null -ne $matched) {
        break
    }
}
if ($null -eq $matched) {
    if (!$process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    throw "Importer did not emit a result"
}
Copy-Item -LiteralPath $matched.FullName -Destination $terminalLog -Force
$evidence = Get-Content -LiteralPath $matched.FullName | Where-Object { $_ -match "IMPORT\|" }
$evidence | Write-Output
if ($evidence -match "IMPORT\|fatal" -or -not ($evidence -match "IMPORT\|summary")) {
    if (!$process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    throw "Custom Tick sample import failed"
}
if (!$process.WaitForExit(30000)) {
    Stop-Process -Id $process.Id -Force
    throw "MT5 did not honor the importer's TerminalClose request"
}
Write-Output "Terminal closed internally with exit code $($process.ExitCode)"
