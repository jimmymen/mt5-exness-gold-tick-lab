$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$testerProfile = Join-Path $terminalData "MQL5\Profiles\Tester"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$baseConfig = Get-Content (Join-Path $projectRoot "config\trend-pullback.ini") -Raw
$baseSet = Get-Content (Join-Path $projectRoot "config\trend-pullback.set") -Raw

$variants = @(
    @{ Name = "base"; Key = ""; Value = "" },
    @{ Name = "fast40"; Key = "InpTrendFastPeriod"; Value = "40" },
    @{ Name = "fast60"; Key = "InpTrendFastPeriod"; Value = "60" },
    @{ Name = "slow180"; Key = "InpTrendSlowPeriod"; Value = "180" },
    @{ Name = "slow220"; Key = "InpTrendSlowPeriod"; Value = "220" },
    @{ Name = "pullback15"; Key = "InpPullbackEmaPeriod"; Value = "15" },
    @{ Name = "pullback25"; Key = "InpPullbackEmaPeriod"; Value = "25" },
    @{ Name = "stop125"; Key = "InpStopAtrMultiple"; Value = "1.25" },
    @{ Name = "stop175"; Key = "InpStopAtrMultiple"; Value = "1.75" },
    @{ Name = "rr150"; Key = "InpRewardRisk"; Value = "1.5" },
    @{ Name = "rr250"; Key = "InpRewardRisk"; Value = "2.5" }
)

$results = @()
foreach ($variant in $variants) {
    $set = $baseSet
    if ($variant.Key) {
        $set = $set -replace "(?m)^$([regex]::Escape($variant.Key))=.*$", "$($variant.Key)=$($variant.Value)"
    }
    $setName = "trend-$($variant.Name).set"
    Set-Content (Join-Path $testerProfile $setName) $set -Encoding ascii

    $config = $baseConfig -replace '(?m)^ExpertParameters=.*$', "ExpertParameters=$setName"
    $config = $config -replace '(?m)^Report=.*$', "Report=Trend-$($variant.Name).html"
    $runtime = Join-Path $projectRoot "reports\trend-$($variant.Name).ini"
    Set-Content $runtime $config -Encoding ascii

    Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 2
    Start-Process $terminal -ArgumentList "/config:$runtime" -Wait | Out-Null

    $agentLog = Get-ChildItem (Join-Path $env:APPDATA "MetaQuotes\Tester") -Filter "*.log" -Recurse |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $all = Get-Content $agentLog.FullName
    $summary = $all | Where-Object { $_ -match "TPB\|tester_summary" } | Select-Object -Last 1
    if (-not ($all -match "generating based on real ticks") -or [string]::IsNullOrWhiteSpace($summary)) {
        throw "Sensitivity run failed: $($variant.Name)"
    }
    $clean = $summary -replace '^.*TPB\|tester_summary', 'TPB|tester_summary'
    Write-Output "$($variant.Name): $clean"
    $results += "$($variant.Name): $clean"
}

$results | Set-Content (Join-Path $projectRoot "reports\TrendPullback-sensitivity.txt") -Encoding ascii
