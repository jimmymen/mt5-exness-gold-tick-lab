$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$python = "C:\Tools\Python312\python.exe"
$parity = Join-Path $projectRoot "reports\parity-result.json"
$state = Join-Path $projectRoot "reports\alignment-state.json"
$commonParity = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\Common\Files\GoldResearch\Parity"
$log = Join-Path $projectRoot "reports\continuous-worker.log"
$mutex = New-Object System.Threading.Mutex($false, "Global\MT5GoldResearchContinuousWorker")

if (-not $mutex.WaitOne(0, $false)) {
    Write-Output "Continuous worker is already running"
    exit 0
}

function Write-State([string]$Phase, [string]$Gate, [string]$Message, [string]$ErrorMessage = "") {
    $value = @{
        phase = $Phase
        gate = $Gate
        message = $Message
        error = $ErrorMessage
        worker_pid = $PID
        updated_utc = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json
    $temporary = "$state.tmp"
    Set-Content $temporary $value -Encoding utf8
    Move-Item $temporary $state -Force
}

try {
    while ($true) {
        try {
            $guiReady = @("summary", "daily", "deals") |
                ForEach-Object { Test-Path (Join-Path $commonParity "gui-$_.csv") } |
                Where-Object { -not $_ } |
                Measure-Object
            if ($guiReady.Count -eq 0) {
                & $python (Join-Path $projectRoot "tools\compare_parity_runs.py") `
                    --directory $commonParity --output $parity *> $log
            }
            $result = if (Test-Path $parity) {
                Get-Content $parity -Raw | ConvertFrom-Json
            } else {
                $null
            }
            if ($guiReady.Count -ne 0) {
                Write-State "alignment" "blocked" "Research paused; GUI parity artifacts are incomplete"
            } elseif ($null -eq $result -or $result.status -ne "passed") {
                Write-State "alignment" "blocked" "Research paused until exact GUI parity passes"
            } else {
                Write-State "ready" "passed" "Alignment passed; no strategy job is currently queued"
            }
        } catch {
            $errorText = $_.Exception.Message
            Add-Content $log "$(Get-Date -Format o) ERROR $errorText"
            Write-State "alignment" "blocked" "Worker iteration failed; research remains paused" $errorText
        }
        Start-Sleep -Seconds 30
    }
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
