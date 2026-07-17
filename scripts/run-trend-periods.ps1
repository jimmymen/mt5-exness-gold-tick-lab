$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$template = Get-Content (Join-Path $projectRoot "config\trend-pullback.ini") -Raw
$periods = @(
    @{ Name = "2025"; From = "2025.01.01"; To = "2026.01.01" },
    @{ Name = "2026H1"; From = "2026.01.01"; To = "2026.07.01" }
)

foreach ($period in $periods) {
    $config = $template
    $config = $config -replace '(?m)^FromDate=.*$', "FromDate=$($period.From)"
    $config = $config -replace '(?m)^ToDate=.*$', "ToDate=$($period.To)"
    $config = $config -replace '(?m)^Report=.*$', "Report=TrendPullback-$($period.Name).html"
    $runtime = Join-Path $projectRoot "reports\trend-pullback-$($period.Name).ini"
    Set-Content $runtime $config -Encoding ascii

    Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 3
    $test = Start-Process $terminal -ArgumentList "/config:$runtime" -Wait -PassThru
    Write-Output "[$($period.Name)] Terminal exit code: $($test.ExitCode)"

    $agentLog = Get-ChildItem (Join-Path $env:APPDATA "MetaQuotes\Tester") -Filter "*.log" -Recurse |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $archive = Join-Path $projectRoot "reports\TrendPullback-$($period.Name)-agent.log"
    Copy-Item $agentLog.FullName $archive -Force
    $all = Get-Content $agentLog.FullName
    $summary = $all | Where-Object { $_ -match "TPB\|tester_summary" } | Select-Object -Last 1
    $ticks = $all | Where-Object { $_ -match "ticks, .* bars generated" } | Select-Object -Last 1
    Write-Output "[$($period.Name)] $summary"
    Write-Output "[$($period.Name)] $ticks"
    if (-not ($all -match "generating based on real ticks") -or [string]::IsNullOrWhiteSpace($summary)) {
        throw "Period validation failed: $($period.Name)"
    }
}

Get-Volume -DriveLetter C | Select-Object Size, SizeRemaining | Format-List
