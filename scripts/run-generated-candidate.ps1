param(
    [Parameter(Mandatory = $true)][string]$SpecPath,
    [switch]$SmokeOnly
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$python = "C:\Tools\Python312\python.exe"
$administratorAppData = "C:\Users\Administrator\AppData\Roaming"
$terminalData = Join-Path $administratorAppData "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$compiler = "C:\Program Files\MetaTrader 5\MetaEditor64.exe"
$testerProfile = Join-Path $terminalData "MQL5\Profiles\Tester"
$expertDir = Join-Path $terminalData "MQL5\Experts\GoldResearch\Generated"
$reports = Join-Path $projectRoot "reports"
$published = Join-Path $reports "published"
$registryPath = Join-Path $reports "research-registry.json"
$commonPublished = Join-Path $administratorAppData "MetaQuotes\Terminal\Common\Files\GoldResearch\Published"
$spec = Get-Content $SpecPath -Raw -Encoding UTF8 | ConvertFrom-Json
$id = $spec.id

if ($id -notmatch '^AIResearch\d{4}$') { throw "Invalid candidate ID" }
$source = Join-Path $projectRoot "mql5\Experts\GoldResearch\Generated\$id.mq5"
& $python (Join-Path $projectRoot "tools\render_ai_candidate.py") `
    --template (Join-Path $projectRoot "mql5\Experts\GoldResearch\AdaptiveDailyStrategy.mq5") `
    --spec $SpecPath --output $source
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $source)) { throw "Candidate rendering failed" }

# Reject forbidden capabilities after exact fixed-template rendering.
$sourceText = Get-Content $source -Raw
foreach ($forbidden in '#import','WebRequest','ShellExecute','WinExec','FileDelete','FileMove') {
    if ($sourceText.Contains($forbidden)) { throw "Forbidden generated source token: $forbidden" }
}
if ($sourceText -notmatch '!MQLInfoInteger\(MQL_TESTER\)') {
    throw "Generated candidate is not tester-only"
}

New-Item -ItemType Directory -Path $testerProfile, $expertDir, $published -Force | Out-Null
$destination = Join-Path $expertDir "$id.mq5"
Copy-Item $source $destination -Force
$compileLog = Join-Path $reports "compile-$id.log"
$compileArgs = @("/compile:$destination", "/log:$compileLog")
Start-Process $compiler -ArgumentList $compileArgs -Wait
$compileOutput = Get-Content $compileLog -Raw
if ($compileOutput -notmatch 'Result:\s+0 errors, 0 warnings') {
    throw "$id compilation failed"
}

$magic = 29000000 + [int]$id.Substring(10)
$setName = "$id.set"
function Run-Stage([string]$Stage, [string]$FromDate, [string]$ToDate) {
    if ([datetime]::ParseExact($ToDate, "yyyy.MM.dd", $null) -gt
        [datetime]::ParseExact("2025.04.13", "yyyy.MM.dd", $null)) {
        throw "Locked holdout period must not be tested"
    }
    $outputName = "$id-$Stage"
    @"
InpMagic=$magic
InpVolume=0.01
InpSignalAType=$($spec.signal_a_type)
InpSignalAPeriod=$($spec.signal_a_period)
InpSignalAInvert=$($spec.signal_a_invert.ToString().ToLower())
InpSignalAWeight=$($spec.signal_a_weight)
InpSignalBType=$($spec.signal_b_type)
InpSignalBPeriod=$($spec.signal_b_period)
InpSignalBInvert=$($spec.signal_b_invert.ToString().ToLower())
InpSignalBWeight=$($spec.signal_b_weight)
InpSignalCType=$($spec.signal_c_type)
InpSignalCPeriod=$($spec.signal_c_period)
InpSignalCInvert=$($spec.signal_c_invert.ToString().ToLower())
InpSignalCWeight=$($spec.signal_c_weight)
InpRegimeMode=$($spec.regime_mode)
InpHoldHours=$($spec.hold_hours)
InpAtrPeriod=$($spec.atr_period)
InpStopAtrMultiple=$($spec.stop_atr)
InpTargetAtrMultiple=$($spec.target_atr)
InpTrailAtrMultiple=$($spec.trail_atr)
InpMaxDeviationPoints=100
InpOutputName=$outputName
"@ | Set-Content (Join-Path $testerProfile $setName) -Encoding ascii
    $runtimeConfig = Join-Path $reports "$outputName.runtime.ini"
    @"
[Tester]
Expert=GoldResearch\Generated\$id.ex5
ExpertParameters=$setName
Symbol=XAUUSDm_EXNESS_V2
Period=D1
Model=4
ExecutionMode=0
Optimization=0
FromDate=$FromDate
ToDate=$ToDate
ForwardMode=0
Deposit=10000
Currency=USD
Leverage=100
Report=$outputName
ReplaceReport=1
ShutdownTerminal=1
Visual=0
"@ | Set-Content $runtimeConfig -Encoding ascii
    $started = Get-Date
    $startedUtc = $started.ToUniversalTime().ToString("o")
    $env:APPDATA = $administratorAppData
    $coverage = Join-Path $commonPublished "$outputName-coverage.csv"
    $curve = Join-Path $commonPublished "$outputName-equity.csv"
    Remove-Item $coverage, $curve -Force -ErrorAction SilentlyContinue
    Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $terminal } | Stop-Process -Force
    Get-Process metatester64 -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq (Join-Path (Split-Path $terminal) "metatester64.exe") } |
        Stop-Process -Force
    Get-ChildItem (Join-Path $terminalData "Tester\logs") -File -Filter "*.log" `
        -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem (Join-Path $administratorAppData "MetaQuotes\Tester") -File -Filter "*.log" `
        -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    $terminalArgs = @("/config:$runtimeConfig")
    $test = Start-Process $terminal -ArgumentList $terminalArgs -Wait -PassThru
    if ($test.ExitCode -ne 0) { throw "MT5 $Stage exited with code $($test.ExitCode)" }
    $testerRoot = Join-Path $administratorAppData "MetaQuotes\Tester"
    $agentLog = Get-ChildItem $testerRoot -Filter "*.log" -Recurse |
        Where-Object { $_.LastWriteTime -ge $started } | Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $agentLog) { throw "MT5 did not produce a new $Stage agent log" }
    $all = Get-Content $agentLog.FullName
    if (-not ($all -match 'generating based on real ticks') -or $all -match 'every tick generation used') {
        throw "$id $Stage failed real-Tick validation"
    }
    $summaryLine = $all | Where-Object { $_ -match 'ADS\|tester_summary' } | Select-Object -Last 1
    $match = [regex]::Match($summaryLine, 'profit=(?<profit>-?[0-9.]+)\|profit_factor=(?<pf>[0-9.]+)\|balance_dd_pct=(?<bdd>[0-9.]+)\|equity_dd_pct=(?<edd>[0-9.]+)\|trades=(?<trades>\d+)\|deals=(?<deals>\d+)\|active_days=(?<active>\d+)\|covered_days=(?<covered>\d+)\|missing_days=(?<missing>\d+)')
    if (-not $match.Success) { throw "Unable to parse $id $Stage summary" }
    $tickLine = $all | Where-Object { $_ -match 'ticks, \d+ bars generated' } | Select-Object -Last 1
    $tickMatch = [regex]::Match($tickLine, '(?<ticks>\d+) ticks, (?<bars>\d+) bars generated')
    if (-not $tickMatch.Success) { throw "Unable to parse $id $Stage Tick evidence" }
    if (-not (Test-Path $coverage) -or -not (Test-Path $curve)) {
        throw "$id $Stage did not export evidence"
    }
    if ((Get-Item $coverage).LastWriteTime -lt $started -or
        (Get-Item $curve).LastWriteTime -lt $started) {
        throw "$id $Stage evidence is stale"
    }
    Copy-Item $coverage (Join-Path $reports "$outputName-coverage.csv") -Force
    $all | Where-Object {
        $_ -match 'generating based on real ticks' -or
        $_ -match 'ADS\|tester_summary' -or
        $_ -match 'ticks, \d+ bars generated'
    } | Select-Object -Last 12 | Set-Content (Join-Path $reports "$outputName-agent.log") -Encoding UTF8
    $finishedUtc = (Get-Date).ToUniversalTime().ToString("o")
    return [pscustomobject]@{
        stage = $Stage; from = $FromDate; to = $ToDate
        started_utc = $startedUtc; finished_utc = $finishedUtc
        profit = [double]$match.Groups['profit'].Value
        profit_factor = [double]$match.Groups['pf'].Value
        equity_dd_pct = [double]$match.Groups['edd'].Value
        trades = [int]$match.Groups['trades'].Value
        deals = [int]$match.Groups['deals'].Value
        active_days = [int]$match.Groups['active'].Value
        covered_days = [int]$match.Groups['covered'].Value
        missing_days = [int]$match.Groups['missing'].Value
        ticks = [long]$tickMatch.Groups['ticks'].Value
        bars = [int]$tickMatch.Groups['bars'].Value
        curve = $curve
    }
}

$backtestStarted = (Get-Date).ToUniversalTime().ToString("o")
$development = Run-Stage "development" "2021.07.02" "2024.01.09"
$developmentPass = $development.profit -gt 0 -and $development.active_days -gt 0 -and
    $development.covered_days -eq $development.active_days -and $development.missing_days -eq 0
$oos = $null
if ($developmentPass) {
    $oos = Run-Stage "oos" "2024.01.09" "2025.04.13"
}
$backtestFinished = (Get-Date).ToUniversalTime().ToString("o")
$oosPass = $null -ne $oos -and $oos.profit -gt 0 -and $oos.active_days -gt 0 -and
    $oos.covered_days -eq $oos.active_days -and $oos.missing_days -eq 0
if ($SmokeOnly) {
    [pscustomobject]@{
        id = $id
        slot = 0
        development = $development
        oos = $oos
        development_pass = $developmentPass
        oos_pass = $oosPass
    } | ConvertTo-Json -Depth 6
    exit 0
}
$registryMutex = New-Object System.Threading.Mutex($false, "Global\MT5GoldResearchRegistry")
$registryMutex.WaitOne() | Out-Null
try {
$registry = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$decision = if (-not $developmentPass) { "REJECT_DEVELOPMENT" } elseif (-not $oosPass) { "REJECT_OOS" } else { "PUBLISH" }
$evaluation = @{
    id = $id
    parent_id = $spec.parent_id
    decision = $decision
    generated_utc = $spec.generated_utc
    backtest_started_utc = $backtestStarted
    backtest_finished_utc = $backtestFinished
    failure_analysis_zh = $spec.failure_analysis_zh
    hypothesis_zh = $spec.hypothesis_zh
    changes_zh = $spec.changes_zh
    development = $development
    oos = $oos
}
$registry.evaluations = @($registry.evaluations) + $evaluation
if ($developmentPass -and $oosPass) {
    $sourceName = "$id.mq5"
    $curveName = "$id-development-equity.csv"
    $oosCurveName = "$id-oos-equity.csv"
    Copy-Item $source (Join-Path $published $sourceName) -Force
    Copy-Item $development.curve (Join-Path $published $curveName) -Force
    Copy-Item $oos.curve (Join-Path $published $oosCurveName) -Force
    $registry.published = @($registry.published) + @{
        name = $id
        chinese_name = $spec.chinese_name
        explanation_zh = $spec.explanation_zh
        failure_analysis_zh = $spec.failure_analysis_zh
        hypothesis_zh = $spec.hypothesis_zh
        changes_zh = $spec.changes_zh
        parent_id = $spec.parent_id
        profit = $development.profit
        profit_factor = $development.profit_factor
        trades = $development.trades
        deals = $development.deals
        equity_dd_pct = $development.equity_dd_pct
        active_days = $development.active_days
        covered_days = $development.covered_days
        missing_days = $development.missing_days
        period = "2021.07.02 - 2024.01.09"
        ticks = $development.ticks
        bars = $development.bars
        oos_profit = $oos.profit
        oos_profit_factor = $oos.profit_factor
        oos_trades = $oos.trades
        oos_equity_dd_pct = $oos.equity_dd_pct
        oos_active_days = $oos.active_days
        oos_covered_days = $oos.covered_days
        oos_missing_days = $oos.missing_days
        oos_period = "2024.01.09 - 2025.04.13"
        blind_period = "2025.04.13 - 2026.07.17 (LOCKED, NOT TESTED)"
        generated_utc = $spec.generated_utc
        backtest_started_utc = $backtestStarted
        backtest_finished_utc = $backtestFinished
        development_started_utc = $development.started_utc
        development_finished_utc = $development.finished_utc
        oos_started_utc = $oos.started_utc
        oos_finished_utc = $oos.finished_utc
        source_url = "/published/$sourceName"
        curve_file = "published/$curveName"
        oos_curve_file = "published/$oosCurveName"
        published_utc = (Get-Date).ToUniversalTime().ToString("o")
    }
} else {
    $registry.rejected = [int]$registry.rejected + 1
}
$temporary = "$registryPath.tmp"
$registry | ConvertTo-Json -Depth 10 | Set-Content $temporary -Encoding utf8
Move-Item $temporary $registryPath -Force
} finally {
    $registryMutex.ReleaseMutex()
    $registryMutex.Dispose()
}
try {
    if ($decision -eq "PUBLISH") {
        & $python (Join-Path $projectRoot "tools\send_feishu_strategy.py") `
            --credentials "C:\ProgramData\MT5GoldResearch\feishu-credentials.json" `
            --registry $registryPath --strategy-id $id
        if ($LASTEXITCODE -ne 0) { throw "Detailed Feishu strategy notification failed" }
        Write-Output "ID=$id DEVELOPMENT_PASS=$developmentPass OOS_PASS=$oosPass"
        exit 0
    }
    $notification = @{
        Id = $id
        Decision = $decision
        DevelopmentProfit = $development.profit
        DevelopmentProfitFactor = $development.profit_factor
        DevelopmentDrawdown = $development.equity_dd_pct
        DevelopmentActiveDays = $development.active_days
        DevelopmentCoveredDays = $development.covered_days
        DevelopmentMissingDays = $development.missing_days
    }
    if ($null -ne $oos) {
        $notification.OosProfit = $oos.profit
        $notification.OosProfitFactor = $oos.profit_factor
        $notification.OosDrawdown = $oos.equity_dd_pct
        $notification.OosActiveDays = $oos.active_days
        $notification.OosCoveredDays = $oos.covered_days
        $notification.OosMissingDays = $oos.missing_days
    }
    & (Join-Path $PSScriptRoot "send-feishu-result.ps1") @notification
} catch {
    Write-Warning "Feishu notification failed without interrupting research: $($_.Exception.Message)"
}
Write-Output "ID=$id DEVELOPMENT_PASS=$developmentPass OOS_PASS=$oosPass"
