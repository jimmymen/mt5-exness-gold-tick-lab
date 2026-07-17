$ErrorActionPreference = "Stop"

$reports = Join-Path (Split-Path -Parent $PSScriptRoot) "reports"
$run1 = (Select-String -Path (Join-Path $reports "EnvironmentProbe-run1.log") -Pattern "PROBE\|summary" |
    Select-Object -Last 1).Line -replace '^.*PROBE\|summary', 'PROBE|summary'
$run2 = (Select-String -Path (Join-Path $reports "EnvironmentProbe-run2.log") -Pattern "PROBE\|summary" |
    Select-Object -Last 1).Line -replace '^.*PROBE\|summary', 'PROBE|summary'

Write-Output "RUN1: $run1"
Write-Output "RUN2: $run2"
if ($run1 -ne $run2) {
    throw "Repeated real-tick runs differ"
}
Write-Output "Repeated real-tick runs are identical"
