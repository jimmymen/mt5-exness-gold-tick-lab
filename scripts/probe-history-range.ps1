$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$template = Get-Content (Join-Path $projectRoot "config\environment-probe.ini") -Raw
$periods = @(
    @{ Name = "2020"; From = "2020.01.01"; To = "2020.01.08" },
    @{ Name = "2022"; From = "2022.01.01"; To = "2022.01.08" },
    @{ Name = "2023"; From = "2023.01.01"; To = "2023.01.08" },
    @{ Name = "2024Sep"; From = "2024.09.20"; To = "2024.10.01" },
    @{ Name = "2024Dec"; From = "2024.12.30"; To = "2025.01.08" },
    @{ Name = "2025"; From = "2025.01.01"; To = "2025.01.08" }
)

$results = @()
foreach ($period in $periods) {
    $config = $template
    $config = $config -replace '(?m)^FromDate=.*$', "FromDate=$($period.From)"
    $config = $config -replace '(?m)^ToDate=.*$', "ToDate=$($period.To)"
    $config = $config -replace '(?m)^Report=.*$', "Report=Probe-$($period.Name).html"
    $runtime = Join-Path $projectRoot "reports\probe-$($period.Name).ini"
    Set-Content $runtime $config -Encoding ascii

    Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 2
    Start-Process $terminal -ArgumentList "/config:$runtime" -Wait | Out-Null

    $testerLog = Get-ChildItem (Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\Tester\logs") `
        -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $lines = Get-Content $testerLog.FullName | Select-Object -Last 120
    $evidence = $lines | Where-Object {
        $_ -match "ticks data begins" -or
        $_ -match "real ticks begin" -or
        $_ -match "generating based on real ticks" -or
        $_ -match "no real ticks" -or
        $_ -match "no data" -or
        $_ -match "test passed" -or
        $_ -match "cannot start"
    } | Select-Object -Last 12
    $header = "=== $($period.Name): $($period.From) to $($period.To) ==="
    Write-Output $header
    $evidence | Write-Output
    $results += $header
    $results += $evidence
}

$results | Set-Content (Join-Path $projectRoot "reports\history-range-probe.txt") -Encoding utf8
Get-Volume -DriveLetter C | Select-Object Size, SizeRemaining | Format-List
