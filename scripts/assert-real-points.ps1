param(
    [Parameter(Mandatory = $true)]
    [string]$AgentLog,

    [Parameter(Mandatory = $true)]
    [datetime]$RequestedStart,

    [Parameter(Mandatory = $true)]
    [datetime]$RequestedEnd,

    [Parameter(Mandatory = $true)]
    [string]$SummaryPrefix
)

$ErrorActionPreference = "Stop"
$lines = Get-Content -LiteralPath $AgentLog
$summaryLine = $lines | Select-String -Pattern ([regex]::Escape($SummaryPrefix)) | Select-Object -Last 1
if ($null -eq $summaryLine) {
    throw "Missing strategy summary: $SummaryPrefix"
}

$runEndIndex = $summaryLine.LineNumber - 1
$runStartMatch = $lines[0..$runEndIndex] | Select-String -Pattern "testing of Experts" | Select-Object -Last 1
if ($null -eq $runStartMatch) {
    throw "Could not locate run start in agent log"
}
$runStartIndex = $runStartMatch.LineNumber - 1
$run = $lines[$runStartIndex..$runEndIndex]

if (-not ($run -match "generating based on real ticks")) {
    throw "Invalid formal test: MT5 did not select 每个点基于实时点"
}
if ($run -match "every tick generation used") {
    throw "Invalid formal test: MT5 fell back to generated points"
}

$tickStartLine = $run | Select-String -Pattern "real ticks begin from ([0-9.]+ [0-9:]+)" | Select-Object -Last 1
if ($null -eq $tickStartLine) {
    throw "Invalid formal test: native real-point start was not reported"
}
$tickStartText = [regex]::Match($tickStartLine.Line, "real ticks begin from ([0-9.]+ [0-9:]+)").Groups[1].Value
$tickStart = [datetime]::ParseExact($tickStartText, "yyyy.MM.dd HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
if ($tickStart -gt $RequestedStart) {
    throw "Invalid formal test: native real points begin at $tickStart after requested start $RequestedStart"
}

Write-Output "Formal real-point validation passed"
Write-Output "Requested: $RequestedStart to $RequestedEnd"
Write-Output "Native real points begin: $tickStart"
Write-Output $summaryLine.Line
