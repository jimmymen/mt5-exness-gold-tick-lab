$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$terminalData = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$testerData = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Tester"
$reports = Join-Path $projectRoot "reports"
$statusPath = Join-Path $reports "storage-maintenance.json"
$removedBytes = 0L
$removedFiles = 0

function Remove-RebuildableFiles([System.IO.FileInfo[]]$Files) {
    foreach ($file in $Files) {
        if ($null -eq $file -or -not (Test-Path $file.FullName)) { continue }
        try {
            Remove-Item $file.FullName -Force -ErrorAction Stop
            $script:removedBytes += $file.Length
            $script:removedFiles++
        } catch {}
    }
}

# Never delete Tick caches, registry JSON, source code, coverage CSV, or equity CSV.
if (-not (Get-Process terminal64 -ErrorAction SilentlyContinue)) {
    Remove-RebuildableFiles @(
        Get-ChildItem (Join-Path $terminalData "Tester\logs") -File -Filter "*.log" `
            -ErrorAction SilentlyContinue
    )
    Remove-RebuildableFiles @(
        Get-ChildItem $testerData -File -Filter "*.log" -Recurse `
            -ErrorAction SilentlyContinue
    )
}

$cutoff = (Get-Date).AddDays(-2)
Remove-RebuildableFiles @(
    Get-ChildItem $reports -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LastWriteTime -lt $cutoff -and (
                $_.Name -like "compile-*.log" -or
                $_.Name -like "*.runtime.ini" -or
                $_.Name -like "*.htm" -or
                $_.Name -like "*.html.tmp" -or
                $_.Name -like "*.tmp"
            )
        }
)

$curves = @(
    Get-ChildItem $reports -File -Filter "*equity.csv" -Recurse -ErrorAction SilentlyContinue
)
$commonCurves = @(
    Get-ChildItem "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\Common\Files\GoldResearch\Published" `
        -File -Filter "*equity.csv" -ErrorAction SilentlyContinue
)
$value = @{
    updated_utc = (Get-Date).ToUniversalTime().ToString("o")
    removed_files = $removedFiles
    removed_bytes = $removedBytes
    free_bytes = (Get-PSDrive C).Free
    retained_report_curves = $curves.Count
    retained_common_curves = $commonCurves.Count
}
$temporary = "$statusPath.tmp"
$value | ConvertTo-Json | Set-Content $temporary -Encoding UTF8
Move-Item $temporary $statusPath -Force
$value | ConvertTo-Json
