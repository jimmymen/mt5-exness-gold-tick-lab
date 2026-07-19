$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$commonParity = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\GoldResearch\Parity"
$destinationDir = Join-Path $terminalData "MQL5\Experts\GoldResearch"
$destination = Join-Path $destinationDir "ParityHarness.mq5"
$testerProfile = Join-Path $terminalData "MQL5\Profiles\Tester"
$compiler = "C:\Program Files\MetaTrader 5\MetaEditor64.exe"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$python = "C:\Tools\Python312\python.exe"
$compileLog = Join-Path $projectRoot "reports\compile-parity-harness.log"
$runtimeConfig = Join-Path $projectRoot "reports\parity-auto.runtime.ini"
$agentArchive = Join-Path $projectRoot "reports\parity-auto-agent.log"
$statePath = Join-Path $projectRoot "reports\development-state.json"
$parityPath = Join-Path $projectRoot "reports\parity-result.json"
$dashboard = Join-Path $projectRoot "reports\development-dashboard.html"

function Render-Dashboard {
    & $python (Join-Path $projectRoot "tools\render_development_dashboard.py") `
        --state $statePath --parity $parityPath --output $dashboard
}
function Save-State([string]$message) {
    @{
        phase = "alignment"
        gate = "blocked"
        message = $message
        updated_utc = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8
    Render-Dashboard
}

New-Item -ItemType Directory -Path $destinationDir, $testerProfile, $commonParity -Force | Out-Null
Save-State "Compiling ParityHarness"
Copy-Item (Join-Path $projectRoot "mql5\Experts\GoldResearch\ParityHarness.mq5") $destination -Force
Start-Process $compiler -ArgumentList @("/compile:$destination", "/log:$compileLog") -Wait
$compileOutput = Get-Content $compileLog -Raw
Write-Output $compileOutput
if ($compileOutput -notmatch "Result:\s+0 errors, 0 warnings") {
    throw "ParityHarness compilation failed"
}

Copy-Item (Join-Path $projectRoot "config\parity-auto.set") `
    (Join-Path $testerProfile "parity-auto.set") -Force
Copy-Item (Join-Path $projectRoot "config\parity-gui.set") `
    (Join-Path $testerProfile "parity-gui.set") -Force
Remove-Item (Join-Path $commonParity "auto-*.csv") -Force -ErrorAction SilentlyContinue
$config = Get-Content (Join-Path $projectRoot "config\parity-auto.ini") -Raw
Set-Content -LiteralPath $runtimeConfig -Value $config -Encoding ascii

Save-State "Running automatic MT5 parity baseline"
Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
$test = Start-Process $terminal -ArgumentList "/config:$runtimeConfig" -Wait -PassThru
Write-Output "Terminal exit code: $($test.ExitCode)"
$agentLog = Get-ChildItem (Join-Path $env:APPDATA "MetaQuotes\Tester") -Filter "*.log" -Recurse |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
Copy-Item $agentLog.FullName $agentArchive -Force
$all = Get-Content $agentLog.FullName
if (-not ($all -match "generating based on real ticks") -or $all -match "every tick generation used" -or
    -not ($all -match "PARITY\|summary\|run=auto")) {
    throw "Automatic parity baseline failed real-Tick validation"
}
foreach ($name in "summary", "daily", "deals") {
    $path = Join-Path $commonParity "auto-$name.csv"
    if (-not (Test-Path $path)) {
        throw "Missing automatic parity artifact: $path"
    }
}
& $python (Join-Path $projectRoot "tools\compare_parity_runs.py") `
    --directory $commonParity --output $parityPath
if ($LASTEXITCODE -notin 0, 2) {
    throw "Parity comparator failed"
}
Save-State "Automatic baseline ready; waiting for manual GUI run"
Write-Output "Dashboard: $dashboard"
Write-Output "GUI preset: $(Join-Path $testerProfile 'parity-gui.set')"
Write-Output "Artifacts: $commonParity"
