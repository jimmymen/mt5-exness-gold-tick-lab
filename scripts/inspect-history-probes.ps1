$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Write-Output "===REQUESTED CONFIGURATIONS==="
Get-ChildItem (Join-Path $projectRoot "reports\probe-*.ini") | ForEach-Object {
    Write-Output "--- $($_.Name)"
    Get-Content $_.FullName | Select-String "FromDate|ToDate"
}

Write-Output "===ACTUAL AGENT EVIDENCE==="
$log = Get-ChildItem (Join-Path $env:APPDATA "MetaQuotes\Tester") -Filter "*.log" -Recurse |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
Write-Output $log.FullName
$lines = Get-Content $log.FullName
$lines | Where-Object {
    $_ -match "testing of Experts\\GoldResearch\\EnvironmentProbe" -or
    $_ -match "history synchronized from" -or
    $_ -match "history ticks synchronized from" -or
    $_ -match "real ticks begin from" -or
    $_ -match "ticks data begins from" -or
    $_ -match "PROBE\|summary" -or
    $_ -match "ticks, .* bars generated"
} | Select-Object -Last 120
