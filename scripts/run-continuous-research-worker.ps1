$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$python = "C:\Tools\Python312\python.exe"
$parity = Join-Path $projectRoot "reports\parity-result.json"
$state = Join-Path $projectRoot "reports\development-state.json"
$dashboard = Join-Path $projectRoot "reports\development-dashboard.html"
$commonParity = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\Common\Files\GoldResearch\Parity"

while ($true) {
    $guiReady = @("summary", "daily", "deals") |
        ForEach-Object { Test-Path (Join-Path $commonParity "gui-$_.csv") } |
        Where-Object { -not $_ } |
        Measure-Object
    if ($guiReady.Count -eq 0) {
        & $python (Join-Path $projectRoot "tools\compare_parity_runs.py") `
            --directory $commonParity --output $parity
    }
    $result = if (Test-Path $parity) {
        Get-Content $parity -Raw | ConvertFrom-Json
    } else {
        $null
    }
    if ($null -eq $result -or $result.status -ne "passed") {
        @{
            phase = "alignment"
            gate = "blocked"
            message = "Research worker paused until GUI parity passes"
            updated_utc = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json | Set-Content $state -Encoding utf8
    } else {
        @{
            phase = "ready"
            gate = "passed"
            message = "Alignment passed; strategy queue may run"
            updated_utc = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json | Set-Content $state -Encoding utf8
    }
    & $python (Join-Path $projectRoot "tools\render_development_dashboard.py") `
        --state $state --parity $parity --output $dashboard
    Start-Sleep -Seconds 30
}
