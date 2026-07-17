$ErrorActionPreference = "Stop"

$paths = @(
    (Join-Path $env:APPDATA "MetaQuotes\Terminal"),
    (Join-Path $env:APPDATA "MetaQuotes\Tester"),
    "C:\QuantResearch"
)

foreach ($path in $paths) {
    $bytes = (Get-ChildItem $path -File -Recurse -ErrorAction SilentlyContinue |
        Measure-Object Length -Sum).Sum
    [pscustomobject]@{
        Path = $path
        GiB = [math]::Round($bytes / 1GB, 3)
    }
}

Write-Output "===BASES==="
$bases = Join-Path $env:APPDATA "MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\bases"
Get-ChildItem $bases -Directory -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName |
    Format-Table -AutoSize

Write-Output "===VOLUME==="
Get-Volume -DriveLetter C | Select-Object Size, SizeRemaining | Format-List
