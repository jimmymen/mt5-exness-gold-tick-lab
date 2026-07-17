$ErrorActionPreference = "Continue"

$urls = @(
    "https://datafeed.dukascopy.com/datafeed/XAUUSD/2024/00/02/00h_ticks.bi5",
    "https://datafeed.dukascopy.com/datafeed/XAUUSD/2020/00/02/00h_ticks.bi5",
    "https://datafeed.dukascopy.com/datafeed/XAUUSD/2015/00/02/00h_ticks.bi5"
)

foreach ($url in $urls) {
    $target = Join-Path $env:TEMP ([IO.Path]::GetFileName($url))
    Remove-Item $target -Force -ErrorAction SilentlyContinue
    Write-Output "=== $url ==="
    & curl.exe -4 -fL --connect-timeout 20 --max-time 90 -o $target -w "http=%{http_code} size=%{size_download} speed=%{speed_download}`n" $url
    if (Test-Path $target) {
        Get-Item $target | Select-Object FullName, Length, LastWriteTime | Format-List
        Remove-Item $target -Force
    }
}
