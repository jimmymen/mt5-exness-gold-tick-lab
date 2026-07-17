$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$commonRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\GoldResearch"
$presets = Join-Path $terminalData "MQL5\Presets"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$python = "C:\Tools\Python312\python.exe"
$dataRoot = "C:\QuantResearch\tick-data\exness\XAUUSDm"
$summaryPath = Join-Path $dataRoot "normalize-summary-monthly.json"
$statusPath = Join-Path $dataRoot "mt5-full-import-status.json"
$runtimeConfig = Join-Path $projectRoot "reports\custom-tick-full-import.runtime.ini"
$preset = Join-Path $presets "custom-tick-full-import.set"
$csvName = "Exness_XAUUSDm_full_import.csv"
$csvPath = Join-Path $commonRoot $csvName
$customSymbol = "XAUUSDm_EXNESS_V2"

function Save-Status($value) {
    $temporary = "$statusPath.tmp"
    $value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $statusPath -Force
}

New-Item -ItemType Directory -Path $commonRoot, $presets -Force | Out-Null
$summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
$completed = @()
if (Test-Path -LiteralPath $statusPath) {
    $previousStatus = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    $completed = @($previousStatus.completed_years | ForEach-Object { [int]$_ })
    if ($previousStatus.state -eq "importing") {
        $recoverYear = [int]$previousStatus.year
        $recoverRows = [long]$previousStatus.expected_rows
        $recovered = Get-ChildItem (Join-Path $terminalData "MQL5\Logs") -Filter "*.log" |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {
                Get-Content -LiteralPath $_.FullName |
                    Where-Object {
                        $_ -match "IMPORT\|summary\|symbol=$customSymbol\|source_rows=$recoverRows\|written=$recoverRows"
                    } |
                    Select-Object -Last 1
            } |
            Select-Object -First 1
        if ($null -ne $recovered -and $recoverYear -notin $completed) {
            $completed += $recoverYear
        }
    }
}
Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

foreach ($item in $summary) {
    $year = [int]$item.year
    $expected = [long]$item.output_rows
    if ($year -in $completed) {
        continue
    }
    $archive = Join-Path $dataRoot "mt5-import-monthly\Exness_XAUUSDm_${year}_MT5_UTC.zip"
    Save-Status @{
        state = "extracting"
        year = $year
        expected_rows = $expected
        completed_years = $completed
        free_bytes = (Get-PSDrive C).Free
        updated = (Get-Date).ToUniversalTime().ToString("o")
    }
    Remove-Item -LiteralPath $csvPath, ([IO.Path]::ChangeExtension($csvPath, ".json")) `
        -Force -ErrorAction SilentlyContinue
    & $python (Join-Path $projectRoot "tools\extract_mt5_year.py") `
        --archive $archive `
        --output $csvPath `
        --expected-rows $expected
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract verified Tick CSV for $year"
    }

    @"
InpSourceSymbol=XAUUSDm
InpCustomSymbol=$customSymbol
InpCustomPath=GoldResearch
InpCsvFile=GoldResearch\$csvName
InpBatchSize=200000
InpCloseTerminal=true
"@ | Set-Content -LiteralPath $preset -Encoding ascii
    @"
[StartUp]
Expert=GoldResearch\CustomTickImporter.ex5
ExpertParameters=custom-tick-full-import.set
Symbol=XAUUSDm
Period=M1
"@ | Set-Content -LiteralPath $runtimeConfig -Encoding ascii

    Save-Status @{
        state = "importing"
        year = $year
        expected_rows = $expected
        completed_years = $completed
        csv_bytes = (Get-Item $csvPath).Length
        free_bytes = (Get-PSDrive C).Free
        updated = (Get-Date).ToUniversalTime().ToString("o")
    }
    $process = Start-Process -FilePath $terminal -ArgumentList "/config:$runtimeConfig" -PassThru
    $deadline = (Get-Date).AddHours(24)
    $evidence = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $log = Get-ChildItem (Join-Path $terminalData "MQL5\Logs") -Filter "*.log" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        $evidence = Get-Content -LiteralPath $log.FullName |
            Where-Object { $_ -match "IMPORT\|summary\|symbol=$customSymbol\|source_rows=$expected\|written=$expected" } |
            Select-Object -Last 1
        if ($null -ne $evidence -and -not (Get-Process terminal64 -ErrorAction SilentlyContinue)) {
            break
        }
    }
    if ($null -eq $evidence) {
        Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
        throw "MT5 import timed out for $year"
    }
    $completed += $year
    Remove-Item -LiteralPath $csvPath, ([IO.Path]::ChangeExtension($csvPath, ".json")) -Force
    Save-Status @{
        state = "year_completed"
        year = $year
        expected_rows = $expected
        completed_years = $completed
        free_bytes = (Get-PSDrive C).Free
        evidence = "source_rows=$expected written=$expected verified=1"
        updated = (Get-Date).ToUniversalTime().ToString("o")
    }
}

Save-Status @{
    state = "completed"
    completed_years = $completed
    total_rows = [long](($summary | Measure-Object output_rows -Sum).Sum)
    free_bytes = (Get-PSDrive C).Free
    updated = (Get-Date).ToUniversalTime().ToString("o")
}
