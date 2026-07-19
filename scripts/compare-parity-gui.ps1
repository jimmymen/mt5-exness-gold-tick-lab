$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$commonParity = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\GoldResearch\Parity"
$python = "C:\Tools\Python312\python.exe"
$statePath = Join-Path $projectRoot "reports\development-state.json"
$parityPath = Join-Path $projectRoot "reports\parity-result.json"
$dashboard = Join-Path $projectRoot "reports\development-dashboard.html"

& $python (Join-Path $projectRoot "tools\compare_parity_runs.py") `
    --directory $commonParity --output $parityPath
$exitCode = $LASTEXITCODE
$result = Get-Content $parityPath -Raw | ConvertFrom-Json
@{
    phase = "alignment"
    gate = $result.status
    message = $result.gate
    updated_utc = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json | Set-Content $statePath -Encoding utf8
& $python (Join-Path $projectRoot "tools\render_development_dashboard.py") `
    --state $statePath --parity $parityPath --output $dashboard
Write-Output "Dashboard: $dashboard"
exit $exitCode
